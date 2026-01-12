/// Setto SDK 에러 코드
enum SettoErrorCode {
  // 사용자 액션
  userCancelled('USER_CANCELLED'),

  // 결제 실패
  paymentFailed('PAYMENT_FAILED'),
  insufficientBalance('INSUFFICIENT_BALANCE'),
  transactionRejected('TRANSACTION_REJECTED'),

  // 네트워크/시스템
  networkError('NETWORK_ERROR'),
  sessionExpired('SESSION_EXPIRED'),

  // 파라미터
  invalidParams('INVALID_PARAMS'),
  invalidMerchant('INVALID_MERCHANT');

  const SettoErrorCode(this.code);

  final String code;

  static SettoErrorCode fromString(String? code) {
    return SettoErrorCode.values.firstWhere(
      (e) => e.code == code,
      orElse: () => SettoErrorCode.paymentFailed,
    );
  }
}

/// Setto SDK 에러
class SettoException implements Exception {
  final SettoErrorCode errorCode;
  final String? message;

  SettoException(this.errorCode, [this.message]);

  @override
  String toString() => message ?? errorCode.code;

  /// Deep Link error 파라미터로부터 에러 생성
  factory SettoException.fromErrorCode(String? code) {
    final errorCode = SettoErrorCode.fromString(code);
    final message = switch (errorCode) {
      SettoErrorCode.userCancelled => '사용자가 결제를 취소했습니다.',
      SettoErrorCode.insufficientBalance => '잔액이 부족합니다.',
      SettoErrorCode.transactionRejected => '트랜잭션이 거부되었습니다.',
      SettoErrorCode.networkError => '네트워크 오류가 발생했습니다.',
      SettoErrorCode.sessionExpired => '세션이 만료되었습니다.',
      SettoErrorCode.invalidParams => '잘못된 파라미터입니다.',
      SettoErrorCode.invalidMerchant => '유효하지 않은 고객사입니다.',
      _ => code,
    };
    return SettoException(errorCode, message);
  }
}
