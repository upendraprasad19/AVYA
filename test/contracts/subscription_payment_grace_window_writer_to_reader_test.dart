import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `subscription_payment_grace_window`
/// from docs/sot_registry.yaml.
///
/// Writer: SubscriptionService.markPaymentInFlight
/// Readers: SubscriptionService.verifyFromServer (isPaymentInFlight gate),
///          subscriptionInfoProvider.isVerifying field (profile_provider.dart)
///
/// The grace window (`kPaymentGraceWindow`, payment_timing.dart) is DERIVED
/// from the verify-payment retry schedule — OI-182: it used to be a bare
/// 10-minute literal that closed before the last retry fired. Prevents
/// verifyFromServer from downgrading optimistic isPro=true before the Razorpay
/// webhook fires.
void main() {
  late String subSvcSrc;
  late String profileProvSrc;
  late String razorpaySrc;

  setUpAll(() {
    final sf = File('lib/core/services/subscription_service.dart');
    expect(sf.existsSync(), isTrue,
        reason: 'subscription_service.dart must exist');
    subSvcSrc = sf.readAsStringSync();

    final pf = File('lib/features/profile/providers/profile_provider.dart');
    expect(pf.existsSync(), isTrue,
        reason: 'profile_provider.dart must exist');
    profileProvSrc = pf.readAsStringSync();

    final rf = File('lib/core/services/razorpay_service.dart');
    expect(rf.existsSync(), isTrue, reason: 'razorpay_service.dart must exist');
    razorpaySrc = rf.readAsStringSync();
  });

  group('subscription_payment_grace_window writer↔reader source contract', () {
    test('writer markPaymentInFlight exists', () {
      expect(subSvcSrc.contains('markPaymentInFlight'), isTrue,
          reason: 'subscription_service must define markPaymentInFlight (grace window writer)');
    });

    test('grace window is DERIVED (kPaymentGraceWindow), not a bare literal', () {
      // Replaces a vacuous check ('10' && 'minute' || '600' || 'paymentInFlight'
      // — the last term is always true in this file, so it could never fail).
      expect(subSvcSrc.contains('_paymentGraceWindow'), isFalse,
          reason: 'the private 10-minute constant must be gone (OI-182)');
      final getter = RegExp(r'bool get isPaymentInFlight \{[\s\S]*?\n  \}')
          .firstMatch(subSvcSrc);
      expect(getter, isNotNull, reason: 'isPaymentInFlight getter must exist');
      expect(getter!.group(0)!.contains('kPaymentGraceWindow'), isTrue,
          reason:
              'isPaymentInFlight must compare against the derived window so it '
              'always outlives the last verify-payment retry');
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

    test('grace window is cleared on every confirmation path, INCLUDING the retry', () {
      // Replaces `contains('clearPaymentInFlight') || (contains('delete') &&
      // contains('paymentInFlight'))` — the definition alone satisfied it.
      // Phase 1 + Phase 2 + the top-of-flow path clear it, and (OI-182) so does
      // the retry's success branch: without it the widened window turns the last
      // retry's refreshFromSupabase() into a no-op.
      expect(subSvcSrc.contains('Future<void> clearPaymentInFlight()'), isTrue,
          reason: 'the clear must be defined');
      final calls = 'clearPaymentInFlight()'.allMatches(razorpaySrc).length;
      expect(calls, greaterThanOrEqualTo(4),
          reason:
              'razorpay_service must clear the grace window at Phase 1, Phase 2, '
              'the top-of-flow path AND the retry success branch (found $calls)');
      final retry = RegExp(r'void _scheduleVerificationRetry\([\s\S]*')
          .firstMatch(razorpaySrc);
      expect(retry, isNotNull);
      expect(retry!.group(0)!.contains('clearPaymentInFlight()'), isTrue,
          reason: 'the retry success branch must clear the grace window (OI-182)');
    });
  });
}
