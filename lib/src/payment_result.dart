/// 결제 상태
enum PaymentStatus {
  success,
  failed,
  cancelled;

  static PaymentStatus fromString(String? value) {
    return switch (value) {
      'success' => PaymentStatus.success,
      'cancelled' => PaymentStatus.cancelled,
      _ => PaymentStatus.failed,
    };
  }
}

/// 결제 결과
class PaymentResult {
  /// 결제 상태
  final PaymentStatus status;

  /// 블록체인 트랜잭션 해시 (성공 시)
  final String? txId;

  /// Setto 결제 ID
  final String? paymentId;

  /// 에러 메시지 (실패 시)
  final String? error;

  PaymentResult({
    required this.status,
    this.txId,
    this.paymentId,
    this.error,
  });
}

/// 결제 요청 파라미터
class PaymentParams {
  /// 주문 ID
  final String orderId;

  /// 결제 금액
  final double amount;

  /// 통화 (기본: USD)
  final String? currency;

  PaymentParams({
    required this.orderId,
    required this.amount,
    this.currency,
  });
}
