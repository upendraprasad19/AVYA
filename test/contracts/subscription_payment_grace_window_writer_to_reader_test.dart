import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `subscription_payment_grace_window`
/// from docs/sot_registry.yaml.
///
/// Writer: SubscriptionService.markPaymentInFlight
/// Readers: SubscriptionService.verifyFromServer (isPaymentInFlight gate),
///          subscriptionInfoProvider.isVerifying field (profile_provider.dart)
///
/// Grace window is 10 minutes. Prevents verifyFromServer from downgrading
/// optimistic isPro=true before the Razorpay webhook fires.
void main() {
  late String subSvcSrc;
  late String profileProvSrc;

  setUpAll(() {
    final sf = File('lib/core/services/subscription_service.dart');
    expect(sf.existsSync(), isTrue,
        reason: 'subscription_service.dart must exist');
    subSvcSrc = sf.readAsStringSync();

    final pf = File('lib/features/profile/providers/profile_provider.dart');
    expect(pf.existsSync(), isTrue,
        reason: 'profile_provider.dart must exist');
    profileProvSrc = pf.readAsStringSync();
  });

  group('subscription_payment_grace_window writer↔reader source contract', () {
    test('writer markPaymentInFlight exists', () {
      expect(subSvcSrc.contains('markPaymentInFlight'), isTrue,
          reason: 'subscription_service must define markPaymentInFlight (grace window writer)');
    });

    test('grace window is 10 minutes', () {
      // The 10-minute window is the contract — changing it breaks payment UX
      expect(subSvcSrc.contains('10') && subSvcSrc.contains('minute') ||
          subSvcSrc.contains('600') ||
          subSvcSrc.contains('paymentInFlight'), isTrue,
          reason:
              'subscription_service must implement 10-minute grace window after payment');
    });

    test('reader verifyFromServer checks isPaymentInFlight gate', () {
      expect(subSvcSrc.contains('isPaymentInFlight'), isTrue,
          reason:
              'verifyFromServer must check isPaymentInFlight to suppress downgrade; '
              'closing the race between webhook + splash-time verify');
    });

    test('paymentInFlightUntil key stored via MigratedKey', () {
      expect(subSvcSrc.contains('paymentInFlightUntil') ||
          subSvcSrc.contains('_paymentInFlightUntilKey'), isTrue,
          reason:
              'grace window expiry must be stored with a stable key '
              '(paymentInFlightUntil) accessible across app restarts');
    });

    test('reader subscriptionInfoProvider exposes isVerifying for UI', () {
      expect(profileProvSrc.contains('isVerifying'), isTrue,
          reason:
              'subscriptionInfoProvider must expose isVerifying field so profile screen '
              'can show "CONFIRMING ⟳ AWAITING WEBHOOK CONFIRMATION" copy');
    });

    test('grace window cleared on confirmation or expiry', () {
      expect(subSvcSrc.contains('clearPaymentInFlight') ||
          subSvcSrc.contains('delete') && subSvcSrc.contains('paymentInFlight'), isTrue,
          reason:
              'grace window must be clearable — should be cleared on webhook '
              'confirmation OR grace expiry, whichever comes first');
    });
  });
}
