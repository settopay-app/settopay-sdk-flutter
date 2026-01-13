library setto_sdk;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:http/http.dart' as http;

// MARK: - Types

enum SettoEnvironment {
  dev('https://dev-wallet.settopay.com', 'https://dev-app.settopay.com'),
  prod('https://wallet.settopay.com', 'https://app.settopay.com');

  /// API 서버 (백엔드 gRPC-Gateway)
  final String apiURL;
  /// 웹앱 (프론트엔드 결제 페이지)
  final String webAppURL;
  const SettoEnvironment(this.apiURL, this.webAppURL);
}

class SettoConfig {
  final SettoEnvironment environment;
  final bool debug;

  SettoConfig({
    required this.environment,
    this.debug = false,
  });
}

enum PaymentStatus { success, failed, cancelled }

class PaymentResult {
  final PaymentStatus status;
  final String? paymentId;
  final String? txHash;
  /// 결제자 지갑 주소 (서버에서 반환)
  final String? fromAddress;
  /// 결산 수신자 주소 (pool이 아닌 최종 수신자, 서버에서 반환)
  final String? toAddress;
  /// 결제 금액 (USD, 예: "10.00", 서버에서 반환)
  final String? amount;
  /// 체인 ID (예: 8453, 56, 900001, 서버에서 반환)
  final int? chainId;
  /// 토큰 심볼 (예: "USDC", "USDT", 서버에서 반환)
  final String? tokenSymbol;
  final String? error;

  PaymentResult({
    required this.status,
    this.paymentId,
    this.txHash,
    this.fromAddress,
    this.toAddress,
    this.amount,
    this.chainId,
    this.tokenSymbol,
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
  /// 항상 PaymentToken을 발급받아서 결제 페이지로 전달합니다.
  /// - IdP Token 없음: Setto 로그인 필요
  /// - IdP Token 있음: 자동로그인
  ///
  /// [merchantId] 머천트 ID
  /// [amount] 결제 금액
  /// [idpToken] IdP 토큰 (선택, 있으면 자동로그인)
  Future<PaymentResult> openPayment({
    required String merchantId,
    required String amount,
    String? idpToken,
  }) async {
    final config = _config;
    if (config == null) {
      return PaymentResult(
        status: PaymentStatus.failed,
        error: 'SDK not initialized',
      );
    }

    _debugLog('Requesting PaymentToken...');
    return _requestPaymentTokenAndOpen(config, merchantId, amount, idpToken);
  }

  Future<PaymentResult> _requestPaymentTokenAndOpen(
    SettoConfig config,
    String merchantId,
    String amount,
    String? idpToken,
  ) async {
    try {
      final tokenUri = Uri.parse(
        '${config.environment.apiURL}/api/external/payment/token',
      );

      final body = <String, String>{
        'merchant_id': merchantId,
        'amount': amount,
      };
      if (idpToken != null) {
        body['idp_token'] = idpToken;
      }

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
        '${config.environment.webAppURL}/pay/wallet#pt=$encodedToken',
      );

      _debugLog('Opening payment page');
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
      '${config.environment.apiURL}/api/external/payment/$paymentId',
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
    final fromAddress = uri.queryParameters['from_address'];
    final toAddress = uri.queryParameters['to_address'];
    final amount = uri.queryParameters['amount'];
    final chainIdStr = uri.queryParameters['chain_id'];
    final chainId = chainIdStr != null ? int.tryParse(chainIdStr) : null;
    final tokenSymbol = uri.queryParameters['token_symbol'];
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
      fromAddress: fromAddress,
      toAddress: toAddress,
      amount: amount,
      chainId: chainId,
      tokenSymbol: tokenSymbol,
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
