// One background verify-payment retry attempt, with every side effect injected
// (OI-182, plan-review R2 N1 + R3 P1/P2-2).
//
// WHY THIS IS A SEPARATE FUNCTION
// -------------------------------
// The retry's success branch used to call `refreshFromSupabase()` and delete
// `localActivationAt` — and NEVER `clearPaymentInFlight()` (Phase 1 and Phase 2
// both do). With the grace window widened to outlive the last retry, every retry
// now sits INSIDE grace, and `refreshFromSupabase` returns early while
// `isPaymentInFlight` — so the retry's reconcile would have become a no-op, the
// "verifying" UI would have lingered for the whole window, and local expiry
// would have stayed at the optimistic value.
//
// The order of the side effects matters, and it can only be TESTED if each one
// is a separately injected callback (a single `onVerified` closure would make
// "delete the clear" a zero-red mutation):
//
//   1. writeState   — PRO state from the server's verified response, mirroring
//                     Phase 2. Done FIRST so that if the write THROWS the grace
//                     window is still open (it is only closed by step 2, which
//                     is then never reached) and keeps protecting the user until
//                     its ceiling; clear-first would leave a cleared window and
//                     no PRO write. (B-pass 2026-09-29 correctly noted that the
//                     earlier stated reason — a stale in-flight verifyFromServer
//                     "not pro" reply — does not depend on this order: such a
//                     reply landing after step 2 downgrades either way.)
//   2. clearGrace   — event-based clear of the payment-in-flight marker.
//   3. refresh      — courtesy reconcile (a no-op for retries 1–2 while the
//                     separate 10-minute `localActivationAt` grace is open,
//                     which is why step 1 exists).
//   4. clearLocalActivation
//
// The network call is the ONLY thing inside the timeout ([boundedAttempt]); all
// writes happen after it and only if the session is unchanged, because
// `Future.timeout` does not cancel the underlying work and a retry can land
// minutes later, after an account switch (the H-20 class). The session is ALSO
// checked BEFORE the call, so a timer that fires after an account switch spends
// nothing (verify-payment rate-limits per caller: 20 / 10 min).
//
// [scheduleVerificationRetries] owns the wiring the per-attempt function cannot
// see: the session comparison itself, the "only end THIS order's grace" guard
// and the stop-after-first-verified latch. It is separate from RazorpayService
// so all three are testable with an injected scheduler (B-pass 2026-09-29: with
// the closures inline in the service, deleting any of them reddened no test).

import 'package:icanbefitter/core/constants/payment_timing.dart';

/// Result of the network half of one retry: the parsed 200 body, or `null`
/// when the server answered with a non-200 status.
typedef VerifyCall = Future<Map<String, dynamic>?> Function();

/// Runs one retry attempt. Returns `true` only when the server confirmed the
/// payment (`verified == true`) AND the session was still the same, i.e. when
/// the caller should stop retrying.
///
/// Throws whatever [callVerify] throws, including the [TimeoutException] from
/// [boundedAttempt] — the caller owns telemetry, this function owns ordering.
Future<bool> runVerificationRetryAttempt({
  required VerifyCall callVerify,
  required bool Function() sessionUnchanged,
  required String fallbackPlan,
  required String Function(String plan) fallbackEndDate,
  required Future<void> Function({
    required String expiresAt,
    required String plan,
  }) writeState,
  required Future<void> Function() clearGrace,
  required Future<void> Function() refresh,
  required Future<void> Function() clearLocalActivation,
}) async {
  // Nothing to spend and nothing to write if the account already changed.
  if (!sessionUnchanged()) return false;

  final data = await boundedAttempt<Map<String, dynamic>?>(
    callVerify,
    kRetryAttemptTimeout,
    label: 'verify-payment retry',
  );
  if (data == null) return false;
  // Only `verified: true` is a verdict. verify-payment answers 200 with
  // `verified: false` for a payment Razorpay has not captured yet.
  if (data['verified'] != true) return false;

  // The retry can land long after the account switched; never write PRO state
  // for a user who is no longer signed in.
  if (!sessionUnchanged()) return false;

  final plan = (data['plan'] as String?) ?? fallbackPlan;
  final endDate = data['end_date'] as String?;
  await writeState(
    expiresAt: (endDate != null && endDate.isNotEmpty)
        ? endDate
        : fallbackEndDate(plan),
    plan: plan,
  );
  await clearGrace();
  await refresh();
  await clearLocalActivation();
  return true;
}

/// Runs [run] after [delay]. Injected so tests drive the timers without real time.
typedef RetryScheduler = void Function(Duration delay, Future<void> Function() run);

void _defaultScheduler(Duration delay, Future<void> Function() run) {
  Future<void>.delayed(delay, run);
}

/// Schedules one [runVerificationRetryAttempt] per entry of [delays], all from
/// now. Once one attempt is verified the later ones do nothing.
///
/// Owns three guards the per-attempt function does not:
///  * the session comparison (`currentUserId() == userId`),
///  * "only end THIS order's grace": a late retry of an OLDER order must not end
///    a NEWER order's grace window (`inFlightOrderId` is null when none is open),
///  * the stop-after-first-verified latch.
///
/// Never throws: an attempt's error goes to [onError] and the next timer still
/// runs.
void scheduleVerificationRetries({
  required List<Duration> delays,
  required VerifyCall callVerify,
  required String userId,
  required String orderId,
  required String? Function() currentUserId,
  required String? Function() inFlightOrderId,
  required String fallbackPlan,
  required String Function(String plan) fallbackEndDate,
  required Future<void> Function({
    required String expiresAt,
    required String plan,
  }) writeState,
  required Future<void> Function() clearPaymentInFlight,
  required Future<void> Function() refresh,
  required Future<void> Function() clearLocalActivation,
  required void Function(Duration delay) onVerified,
  required void Function(Duration delay) onNotVerified,
  required void Function(Duration delay, Object error, StackTrace stack) onError,
  RetryScheduler scheduler = _defaultScheduler,
}) {
  var done = false;
  for (final delay in delays) {
    scheduler(delay, () async {
      if (done) return;
      try {
        final verified = await runVerificationRetryAttempt(
          callVerify: callVerify,
          sessionUnchanged: () => currentUserId() == userId,
          fallbackPlan: fallbackPlan,
          fallbackEndDate: fallbackEndDate,
          writeState: writeState,
          clearGrace: () async {
            final inFlight = inFlightOrderId();
            if (inFlight == null || inFlight == orderId) {
              await clearPaymentInFlight();
            }
          },
          refresh: refresh,
          clearLocalActivation: clearLocalActivation,
        );
        if (verified) {
          done = true;
          onVerified(delay);
        } else {
          onNotVerified(delay);
        }
      } catch (e, st) {
        onError(delay, e, st);
      }
    });
  }
}
