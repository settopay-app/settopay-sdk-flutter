import 'dart:async';

import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';

import 'setto_environment.dart';
import 'setto_error.dart';
import 'payment_result.dart';

/// Setto Flutter SDK
///
/// url_launcher를 사용하여 시스템 브라우저로 wallet.settopay.com과 연동합니다.
///
/// ## 사용 예시
/// ```dart
/// // 초기화
/// final sdk = SettoSDK();
/// sdk.initialize(
///   merchantId: 'merchant-123',
///   environment: SettoEnvironment.production,
///   returnScheme: 'mygame',
/// );
///
/// // 결제 요청
/// final result = await sdk.openPayment(
///   params: PaymentParams(orderId: 'order-456', amount: 100.00),
/// );
/// print('결제 성공: ${result.txId}');
/// ```
class SettoSDK {
  static final SettoSDK _instance = SettoSDK._internal();

  factory SettoSDK() => _instance;

  SettoSDK._internal();

  String _merchantId = '';
  String _returnScheme = '';
  SettoEnvironment _environment = SettoEnvironment.production;

  Completer<PaymentResult>? _paymentCompleter;
  StreamSubscription? _linkSubscription;
  final AppLinks _appLinks = AppLinks();

  /// SDK 초기화
  ///
  /// 앱 시작 시 한 번만 호출합니다.
  void initialize({
    required String merchantId,
    required SettoEnvironment environment,
    required String returnScheme,
  }) {
    _merchantId = merchantId;
    _environment = environment;
    _returnScheme = returnScheme;

    _setupDeepLinkListener();
  }

  /// 결제 창을 열고 결제를 진행합니다.
  ///
  /// 결제 완료 시 [PaymentResult]를 반환합니다.
  /// 사용자 취소 또는 실패 시 [SettoException]을 throw합니다.
  Future<PaymentResult> openPayment({
    required PaymentParams params,
  }) async {
    _paymentCompleter = Completer<PaymentResult>();

    final url = _buildPaymentUrl(params);

    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      throw SettoException(SettoErrorCode.networkError, '브라우저를 열 수 없습니다.');
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    return _paymentCompleter!.future;
  }

  /// Deep Link 리스너 설정
  void _setupDeepLinkListener() {
    // 앱이 실행 중일 때 Deep Link 수신
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleDeepLink(uri);
    });

    // 앱 시작 시 Deep Link 확인 (Cold Start)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
  }

  /// Deep Link 처리
  void _handleDeepLink(Uri uri) {
    // Scheme 확인
    if (uri.scheme != _returnScheme) return;

    // 결제 진행 중이 아니면 무시
    if (_paymentCompleter == null || _paymentCompleter!.isCompleted) return;

    final status = uri.queryParameters['status'];
    final txId = uri.queryParameters['txId'];
    final paymentId = uri.queryParameters['paymentId'];
    final error = uri.queryParameters['error'];

    final result = PaymentResult(
      status: PaymentStatus.fromString(status),
      txId: txId,
      paymentId: paymentId,
      error: error,
    );

    switch (result.status) {
      case PaymentStatus.success:
        _paymentCompleter?.complete(result);
      case PaymentStatus.cancelled:
        _paymentCompleter?.completeError(
          SettoException(SettoErrorCode.userCancelled),
        );
      case PaymentStatus.failed:
        _paymentCompleter?.completeError(
          SettoException.fromErrorCode(error),
        );
    }

    _paymentCompleter = null;
  }

  String _buildPaymentUrl(PaymentParams params) {
    final encodedMerchantId = Uri.encodeComponent(_merchantId);
    final encodedOrderId = Uri.encodeComponent(params.orderId);
    final encodedScheme = Uri.encodeComponent(_returnScheme);

    var url = '${_environment.baseUrl}/pay';
    url += '?merchantId=$encodedMerchantId';
    url += '&orderId=$encodedOrderId';
    url += '&amount=${params.amount}';
    url += '&returnScheme=$encodedScheme';

    if (params.currency != null) {
      final encodedCurrency = Uri.encodeComponent(params.currency!);
      url += '&currency=$encodedCurrency';
    }

    return url;
  }

  /// 리소스 해제
  void dispose() {
    _linkSubscription?.cancel();
  }
}
