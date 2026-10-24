// OI-182 — SOURCE-GREP pin of the wiring that payment_timing_test.dart cannot
// prove: that razorpay_service.dart and subscription_service.dart actually USE
// the derived constants and bounded helpers.
//
// PRESENCE ONLY, and honest about it (CLAUDE.md §4.4 rule 21): the behavioural
// halves live in test/core/payment_timing_test.dart (helper times out at the
// bound), test/core/payment_retry_attempt_test.dart (ordering of the retry's
// side effects) and the seeded isPaymentInFlight tests. This file only fails if
// someone stops CALLING them.
//
// Run: flutter test test/contracts/payment_grace_window_derived_wiring_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  late String razorpay;
  late String subscription;

  setUpAll(() {
    razorpay = _stripComments(
        File('lib/core/services/razorpay_service.dart').readAsStringSync());
    subscription = _stripComments(
        File('lib/core/services/subscription_service.dart').readAsStringSync());
  });

  group('razorpay_service.dart uses the shared schedule and bounds', () {
    test('the retry schedule is kVerificationRetryDelays, not an inline list', () {
      expect(razorpay.contains('kVerificationRetryDelays'), isTrue);
      expect(razorpay.contains('Duration(minutes: 15)'), isFalse,
          reason: 'the 15-minute retry delay must come from payment_timing.dart');
      expect(razorpay.contains('Duration(seconds: 60),\n      Duration(minutes: 5)'),
          isFalse);
    });

    test('each retry goes through scheduleVerificationRetries -> runVerificationRetryAttempt (ordered side effects)', () {
      expect(razorpay.contains('scheduleVerificationRetries('), isTrue);
      // The guards themselves are behaviourally tested in
      // test/core/payment_retry_attempt_test.dart with injected sources; what
      // only a source pin can prove is that the SERVICE hands the real session
      // user and the real in-flight order to it (B-pass 2026-09-29).
      expect(razorpay.contains('currentUserId: () => SupabaseService.instance.currentUser?.id'), isTrue);
      expect(razorpay.contains('SubscriptionService.instance.paymentInFlightOrderId'), isTrue);
      expect(RegExp(r'scheduleVerificationRetries\([\s\S]{0,200}userId: userId,').hasMatch(razorpay), isTrue,
          reason: 'the closure must be keyed on the CAPTURED user, not a blank');
      expect(RegExp(r'scheduleVerificationRetries\([\s\S]{0,300}orderId: orderId,').hasMatch(razorpay), isTrue);
    });

    test('Phase 1 uses pollDelaySeconds / kPhase1PollAttempts / kPhase1ExactMatchAttempts', () {
      expect(razorpay.contains('pollDelaySeconds('), isTrue);
      expect(razorpay.contains('kPhase1PollAttempts'), isTrue);
      expect(razorpay.contains('kPhase1ExactMatchAttempts'), isTrue);
      // The bare literals the constants replaced.
      expect(razorpay.contains('attempt < 15'), isFalse);
      expect(razorpay.contains('attempt < 12'), isFalse);
    });

    test('every network call in the activation flow is bounded', () {
      // session refresh + poll (exact) + poll (fallback) + Phase 2 = 4.
      final bounded = 'boundedAttempt'.allMatches(razorpay).length;
      expect(bounded, greaterThanOrEqualTo(4),
          reason: 'found $bounded boundedAttempt uses in razorpay_service.dart');
      expect(razorpay.contains('kPollCallTimeout'), isTrue);
      expect(razorpay.contains('kPhase2CallTimeout'), isTrue);
    });

    test('a timed-out poll is counted, never reported per attempt', () {
      expect(razorpay.contains('on TimeoutException'), isTrue);
      expect(razorpay.contains('razorpay_poll_timeouts'), isTrue);
    });
  });

  group('subscription_service.dart reads the derived window', () {
    test('kPaymentGraceWindow is used and the private literal is gone', () {
      expect(subscription.contains('kPaymentGraceWindow'), isTrue);
      expect(subscription.contains('_paymentGraceWindow'), isFalse);
    });

    test('the localActivationAt 10-minute windows are deliberately untouched', () {
      // OI-182 widens ONLY the payment-in-flight window. localActivationAt has
      // its own 10-minute grace (refreshFromSupabase / verify paths) that the
      // diagnose-doc calls out as intentionally unchanged.
      expect(subscription.contains('localActivationAt'), isTrue);
      // They are spelled `.inMinutes < 10` / `.inMinutes >= 10`, not as a
      // Duration constant, so this pins the spelling that actually exists.
      expect(subscription.contains('.inMinutes < 10'), isTrue,
          reason: 'the separate localActivationAt grace must still be 10 min');
      expect(subscription.contains('.inMinutes >= 10'), isTrue,
          reason: 'the separate localActivationAt expiry check must still be 10 min');
    });
  });
}
