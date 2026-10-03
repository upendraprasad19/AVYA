import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/razorpay_web_checkout.dart';

void main() {
  group('isWebCheckoutDisabledByConfig — §4.6 kill-switch convention', () {
    test('absent (null) ⇒ ACTIVE (checkout enabled)', () {
      expect(isWebCheckoutDisabledByConfig(null), isFalse);
    });
    test('true ⇒ disabled (old mobile-only behavior)', () {
      expect(isWebCheckoutDisabledByConfig(true), isTrue);
    });
    test('false ⇒ ACTIVE', () {
      expect(isWebCheckoutDisabledByConfig(false), isFalse);
    });
    test("string 'true' ⇒ ACTIVE (type-strict, matches isSyncAutoDrainDisabled)",
        () {
      expect(isWebCheckoutDisabledByConfig('true'), isFalse);
    });
  });
}
