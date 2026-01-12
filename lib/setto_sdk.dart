library setto_sdk;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:http/http.dart' as http;

// MARK: - Types

enum SettoEnvironment {
  dev('https://dev-wallet.settopay.com'),
  prod('https://wallet.settopay.com');

  final String baseURL;
  const SettoEnvironment(this.baseURL);
}

class SettoConfig {
  final SettoEnvironment environment;
  final String? idpToken; // IdP 토큰 (있으면 자동로그인)
  final bool debug;

  SettoConfig({
    required this.environment,
    this.idpToken,
    this.debug = false,
  });
}

enum PaymentStatus { success, failed, cancelled }

class PaymentResult {
  final PaymentStatus status;
  final String? paymentId;
  final String? txHash;
  final String? error;

  PaymentResult({
    required this.status,
    this.paymentId,
    this.txHash,
    this.error,
  });
}

class PaymentInfo {
  final String paymentId;
  final String status;
  final String amount;
  final String currency;
  final String? txHash;
  final int createdAt;
  final int? completedAt;

  PaymentInfo({
    required this.paymentId,
    required this.status,
    required this.amount,
    required this.currency,
    this.txHash,
    required this.createdAt,
    this.completedAt,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      paymentId: json['payment_id'],
      status: json['status'],
      amount: json['amount'],
      currency: json['currency'],
      txHash: json['tx_hash'],
      createdAt: json['created_at'],
      completedAt: json['completed_at'],
    );
  }
}

// MARK: - SDK

class SettoSDK {
  static SettoSDK? _instance;
  static SettoSDK get instance => _instance ??= SettoSDK._();

  SettoSDK._();

  SettoConfig? _config;
  void Function(PaymentResult)? _pendingCallback;

  /// SDK 초기화
  void initialize(SettoConfig config) {
    _config = config;
    _debugLog('Initialized with environment: ${config.environment}');
  }

  /// 결제 요청
  ///
  /// IdP Token 유무에 따라 자동로그인 여부가 결정됩니다.
  /// - IdP Token 없음: Setto 로그인 필요
  /// - IdP Token 있음: PaymentToken 발급 후 자동로그인
  Future<PaymentResult> openPayment({
    required String merchantId,
    required String amount,
    String? orderId,
  }) async {
    final config = _config;
    if (config == null) {
      return PaymentResult(
        status: PaymentStatus.failed,
        error: 'SDK not initialized',
      );
    }

    if (config.idpToken != null) {
      // IdP Token 있음 → PaymentToken 발급 → Fragment로 전달
      _debugLog('Requesting PaymentToken...');
      return _requestPaymentTokenAndOpen(config, merchantId, amount, orderId);
    } else {
      // IdP Token 없음 → Query param으로 직접 전달
      final uri = Uri.parse('${config.environment.baseURL}/pay/wallet').replace(
        queryParameters: {
          'merchant_id': merchantId,
          'amount': amount,
          if (orderId != null) 'order_id': orderId,
        },
      );

      _debugLog('Opening payment with Setto login: $uri');
      return _openCustomTabs(uri);
    }
  }

  Future<PaymentResult> _requestPaymentTokenAndOpen(
    SettoConfig config,
    String merchantId,
    String amount,
    String? orderId,
  ) async {
    try {
      final tokenUri = Uri.parse(
        '${config.environment.baseURL}/api/external/payment/token',
      );

      final body = {
        'merchant_id': merchantId,
        'amount': amount,
        if (orderId != null) 'order_id': orderId,
        'idp_token': config.idpToken,
      };

      final response = await http.post(
        tokenUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        _debugLog('PaymentToken request failed: ${response.statusCode}');
        return PaymentResult(
          status: PaymentStatus.failed,
          error: 'Token request failed: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body);
      final paymentToken = json['payment_token'] as String;

      // Fragment로 전달 (보안: 서버 로그에 남지 않음)
      final encodedToken = Uri.encodeComponent(paymentToken);
      final uri = Uri.parse(
        '${config.environment.baseURL}/pay/wallet#pt=$encodedToken',
      );

      _debugLog('Opening payment with auto-login');
      return _openCustomTabs(uri);
    } catch (e) {
      _debugLog('PaymentToken request error: $e');
      return PaymentResult(
        status: PaymentStatus.failed,
        error: 'Network error',
      );
    }
  }

  /// 결제 상태 조회
  Future<PaymentInfo> getPaymentInfo({
    required String merchantId,
    required String paymentId,
  }) async {
    final config = _config;
    if (config == null) {
      throw Exception('SDK not initialized');
    }

    final uri = Uri.parse(
      '${config.environment.baseURL}/api/external/payment/$paymentId',
    );

    final response = await http.get(
      uri,
      headers: {'X-Merchant-ID': merchantId},
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    return PaymentInfo.fromJson(json);
  }

  /// URL Scheme 콜백 처리
  bool handleCallback(Uri uri) {
    // setto-{merchantId}://callback?status=success&payment_id=xxx&tx_hash=xxx
    if (!(uri.scheme.startsWith('setto-')) || uri.host != 'callback') {
      return false;
    }

    final statusString = uri.queryParameters['status'] ?? '';
    final paymentId = uri.queryParameters['payment_id'];
    final txHash = uri.queryParameters['tx_hash'];
    final errorMsg = uri.queryParameters['error'];

    PaymentStatus status;
    switch (statusString) {
      case 'success':
        status = PaymentStatus.success;
        break;
      case 'failed':
        status = PaymentStatus.failed;
        break;
      default:
        status = PaymentStatus.cancelled;
    }

    final result = PaymentResult(
      status: status,
      paymentId: paymentId,
      txHash: txHash,
      error: errorMsg,
    );

    _pendingCallback?.call(result);
    _pendingCallback = null;

    _debugLog('Callback received: $statusString');
    return true;
  }

  /// 초기화 여부 확인
  bool get isInitialized => _config != null;

  // MARK: - Private Methods

  Future<PaymentResult> _openCustomTabs(Uri uri) async {
    try {
      await launchUrl(
        uri,
        customTabsOptions: CustomTabsOptions(
          showTitle: true,
          urlBarHidingEnabled: true,
        ),
        safariVCOptions: SafariViewControllerOptions(
          preferredBarTintColor: const Color(0xFFFFFFFF),
          preferredControlTintColor: const Color(0xFF000000),
          barCollapsingEnabled: true,
        ),
      );

      // Custom Tabs가 닫히면 취소로 처리
      // 실제 결과는 URL Scheme 콜백으로 받음
      return PaymentResult(status: PaymentStatus.cancelled);
    } catch (e) {
      return PaymentResult(
        status: PaymentStatus.failed,
        error: e.toString(),
      );
    }
  }

  void _debugLog(String message) {
    if (_config?.debug == true) {
      debugPrint('[SettoSDK] $message');
    }
  }
}

// Color class for CustomTabsOptions
class Color {
  final int value;
  const Color(this.value);
}
