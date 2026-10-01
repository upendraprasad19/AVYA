// Payment activation timing — the ONE source for the verify-payment retry
// schedule, the per-call network bounds, and the payment grace window that
// must outlive all of them (OI-182).
//
// WHY THIS FILE EXISTS
// --------------------
// Before OI-182 two independent literals described one timeline:
//   - `SubscriptionService._paymentGraceWindow = Duration(minutes: 10)`
//   - `RazorpayService._scheduleVerificationRetry`'s inline `[60s, 5m, 15m]`
// The grace window opens at payment success (`markPaymentInFlight`), BEFORE
// Phase 1 (15 polls) and Phase 2 (verify-payment call). The retries are only
// scheduled AFTER both exhaust, so the last retry fires at roughly
// `phase1 + phase2 + 15 min` after the grace clock started — later than the
// 10-minute window, which therefore closed while a paying user's last retry
// was still pending and let `verifyFromServer` run `_downgradeLocally`.
//
// The window is now DERIVED from the schedule, and every network call in the
// activation flow is bounded by a timeout that sums into the derived budget,
// so lengthening a delay or a timeout moves the window with it.
//
// BEST-EFFORT CAVEAT (stated, not fixed): the retries are in-memory Dart
// timers. They do not fire while the process is suspended and an app kill
// loses all three, while the wall-clock grace survives. "Derived" therefore
// holds under continuous foreground execution, not for the whole class.
//
// QUOTA CAVEAT: verify-payment allows 20 calls per user per 10 minutes. One payment
// makes at most 4 logical calls (Phase 2 + 3 retries), and each can run the handler
// up to 4 times (cold-start re-invokes), so <= 16 executions. Lengthening the retry
// list or the cold-start loop eats the margin of 4; re-derive before changing either.
//
// This file is PURE — it imports nothing from `services/` — so its tests need
// no Hive, no Supabase and no Razorpay plugin.

import 'dart:async';

/// Delays of the background verify-payment retries, each measured from the
/// moment Phase 1 + Phase 2 exhausted (all three timers are scheduled together).
const List<Duration> kVerificationRetryDelays = <Duration>[
  Duration(seconds: 60),
  Duration(minutes: 5),
  Duration(minutes: 15),
];

/// Number of Phase-1 polls of the `subscriptions` table.
const int kPhase1PollAttempts = 15;

/// Phase-1 polls before this index match on the exact `razorpay_payment_id`;
/// from it onward they fall back to "any active row for this plan in the last
/// five minutes". Kept here (not a bare `12` in the loop) so it cannot drift
/// from [kPhase1PollAttempts] unnoticed.
const int kPhase1ExactMatchAttempts = 12;

/// Sleep before Phase-1 poll [attempt]: 2 s for the first five, 3 s for the
/// next five, 4 s for the rest (exponential-ish backoff, 45 s in total).
int pollDelaySeconds(int attempt) => attempt < 5 ? 2 : (attempt < 10 ? 3 : 4);

/// Bound on ONE Phase-1 poll query. 5 s is too tight
/// for TLS + a cold connection to ap-southeast-1 over Indian mobile networks.
const Duration kPollCallTimeout = Duration(seconds: 8);

/// Bound on the Phase-2 verify-payment call. `callFunction` itself runs a
/// cold-start loop (up to 4 invokes + 20 s backoff); a slow-but-successful
/// verify is cut here and falls through to the retries.
const Duration kPhase2CallTimeout = Duration(seconds: 60);

/// Bound on ONE background retry attempt (the token refresh AND the call, as
/// a single unit — see [boundedAttempt]).
const Duration kRetryAttemptTimeout = Duration(seconds: 60);

Duration _phase1NominalDelay() {
  var seconds = 0;
  for (var attempt = 0; attempt < kPhase1PollAttempts; attempt++) {
    seconds += pollDelaySeconds(attempt);
  }
  return Duration(seconds: seconds);
}

/// Worst-case wall time from grace-open to the moment the retries are
/// scheduled: Phase 1's sleeps + every poll hitting its timeout + Phase 2
/// hitting its timeout. DERIVED — not a literal.
final Duration kActivationPhasesBudget =
    _phase1NominalDelay() + kPollCallTimeout * kPhase1PollAttempts + kPhase2CallTimeout;

/// How long a payment counts as "in flight" (grace against a downgrade). Must
/// outlive the LAST retry: last delay + the phases before it + that retry's own
/// bounded attempt + a safety margin. DERIVED — not a literal.
final Duration kPaymentGraceWindow = kVerificationRetryDelays.last +
    kActivationPhasesBudget +
    kRetryAttemptTimeout +
    const Duration(minutes: 2);

/// Runs [thunk] and fails with a [TimeoutException] naming [label] and the
/// bound if it has not completed within [timeout].
///
/// The thunk must contain ONLY the network call. Anything that writes state
/// (Hive, provider invalidation) belongs OUTSIDE it: `Future.timeout` does not
/// cancel the underlying work, so a late completion after the timeout must not
/// be able to write for a session that has since changed.
///
/// A thunk (not a Future) so a test can hand in a never-completing future and
/// so a synchronous throw is captured as a Future error.
Future<T> boundedAttempt<T>(
  Future<T> Function() thunk,
  Duration timeout, {
  String label = 'call',
}) async {
  return thunk().timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      '$label timed out after ${timeout.inSeconds}s',
      timeout,
    ),
  );
}
