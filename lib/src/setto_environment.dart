/// Setto SDK 환경 설정
enum SettoEnvironment {
  /// 개발 환경
  development('https://dev-wallet.settopay.com'),

  /// 프로덕션 환경
  production('https://wallet.settopay.com');

  const SettoEnvironment(this.baseUrl);

  /// 환경에 해당하는 Base URL
  final String baseUrl;
}
