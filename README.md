# Setto SDK for Flutter

Setto Flutter SDK - url_launcher 기반 결제 연동 SDK

## 요구사항

- Flutter 3.10.0+
- Dart 3.0.0+

## 설치

### pub.dev

```yaml
# pubspec.yaml
dependencies:
  setto_sdk: ^0.1.0
```

## 설정

### iOS - Info.plist

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>mygame</string>  <!-- 고객사 Scheme -->
        </array>
    </dict>
</array>
```

### Android - AndroidManifest.xml

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTask">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="mygame" />  <!-- 고객사 Scheme -->
    </intent-filter>
</activity>
```

## 사용법

### SDK 초기화

```dart
import 'package:setto_sdk/setto_sdk.dart';

void main() {
  // SDK 초기화 (앱 시작 시)
  SettoSDK().initialize(
    merchantId: 'your-merchant-id',
    environment: SettoEnvironment.production,
    returnScheme: 'mygame',
  );

  runApp(MyApp());
}
```

### 결제 요청

```dart
import 'package:setto_sdk/setto_sdk.dart';

Future<void> handlePayment() async {
  final params = PaymentParams(
    orderId: 'order-123',
    amount: 100.00,
    currency: 'USD',  // 선택
  );

  try {
    final result = await SettoSDK().openPayment(params: params);
    print('결제 성공! TX ID: ${result.txId}');
    // 서버에서 결제 검증 필수!
  } on SettoException catch (e) {
    if (e.errorCode == SettoErrorCode.userCancelled) {
      print('사용자가 결제를 취소했습니다.');
    } else {
      print('결제 실패: ${e.message}');
    }
  }
}
```

## API

### SettoSDK

#### `initialize({merchantId, environment, returnScheme})`

SDK를 초기화합니다. 앱 시작 시 한 번만 호출합니다.

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `merchantId` | `String` | 고객사 ID |
| `environment` | `SettoEnvironment` | `development` 또는 `production` |
| `returnScheme` | `String` | Custom URL Scheme |

#### `openPayment({params}) -> Future<PaymentResult>`

결제 창을 열고 결제를 진행합니다.

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `params` | `PaymentParams` | 결제 파라미터 |

**반환값**: `PaymentResult` (성공 시) 또는 `SettoException` throw (실패/취소 시)

#### `dispose()`

리소스를 해제합니다.

### PaymentParams

| 속성 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `orderId` | `String` | ✅ | 주문 ID |
| `amount` | `double` | ✅ | 결제 금액 |
| `currency` | `String?` | | 통화 (기본: USD) |

### PaymentResult

| 속성 | 타입 | 설명 |
|------|------|------|
| `status` | `PaymentStatus` | `success`, `failed`, `cancelled` |
| `txId` | `String?` | 블록체인 트랜잭션 해시 |
| `paymentId` | `String?` | Setto 결제 ID |
| `error` | `String?` | 에러 메시지 |

### SettoErrorCode

| 값 | 설명 |
|----|------|
| `userCancelled` | 사용자 취소 |
| `paymentFailed` | 결제 실패 |
| `insufficientBalance` | 잔액 부족 |
| `transactionRejected` | 트랜잭션 거부 |
| `networkError` | 네트워크 오류 |
| `sessionExpired` | 세션 만료 |
| `invalidParams` | 잘못된 파라미터 |
| `invalidMerchant` | 유효하지 않은 고객사 |

## 보안 참고사항

1. **결제 결과는 서버에서 검증 필수**: SDK에서 반환하는 결과는 UX 피드백용입니다. 실제 결제 완료 여부는 고객사 서버에서 Setto API를 통해 검증해야 합니다.

2. **Custom URL Scheme 보안**: 다른 앱이 동일한 Scheme을 등록할 수 있으므로, 결제 결과는 반드시 서버에서 검증하세요.

## License

MIT
