---
bug_id: f2a6d1
date: 2026-09-29
batch: oi-182-202-subscription-state
status: fixed
blast_radius: catastrophic
symptom: |
  OI-182. After a successful Razorpay checkout the app opens a payment grace
  window (SubscriptionService.markPaymentInFlight) that suppresses the server
  downgrade path (verifyFromServer -> _downgradeLocally). Its length was a bare
  10-minute literal, but the activation flow that has to fit inside it is
  Phase 1 (15 polls, 45 s of sleeps) + Phase 2 (verify-payment) + three
  background retries scheduled AFTER both exhaust, at +60 s, +5 m and +15 m.
  The last retry therefore fires at ~phase1 + phase2 + 15 min after the grace
  clock started -- later than the 10-minute window. A paying user whose
  webhook was slow could be downgraded locally while their last retry was
  still pending.
concept: subscription_payment_grace_window
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: "markPaymentInFlight / isPaymentInFlight -- opens and reads the grace window", line: 217 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: "_scheduleVerificationRetry -- hands the real session user / in-flight order / verify call to scheduleVerificationRetries", line: 915 }
  - { file: lib/core/services/payment_retry_attempt.dart, method_or_widget: "scheduleVerificationRetries (session compare, only-this-order's-grace guard, stop-after-first-verified latch) + runVerificationRetryAttempt (write PRO state, clear grace, refresh, clear localActivationAt, in that order)", line: 55 }
  - { file: lib/core/constants/payment_timing.dart, method_or_widget: "kPaymentGraceWindow -- DERIVED from the retry schedule and the per-call bounds", line: 82 }
readers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: "isPaymentInFlight -- compares against kPaymentGraceWindow", line: 181 }
  - { file: lib/core/services/subscription_service.dart, method_or_widget: "refreshFromSupabase / verifyFromServer -- return early or skip the downgrade while in flight", line: 742 }
hive_key_prefix: paymentInFlightOrder
hive_key_formula: "configBox['paymentInFlightOrder'] = {order_id, started_at} (plus the legacy 'paymentInFlightUntil', read for back-compat) -- SubscriptionService._paymentInFlightOrderKey; unchanged by this batch"
sync_methods: []
restore_methods: []
cloud_table: "subscriptions (read-only for this fix)"
cloud_columns:
  - status
  - end_date
contract_test_path: test/contracts/subscription_payment_grace_window_behavioral_test.dart
ist_handling: []
provider_invalidations:
  - subscriptionInfoProvider
telemetry_op_types:
  success: [subscription_refresh_grace_skip, subscription_refresh_success]
  failure: [razorpay_poll_timeouts]
cross_account_guard: "runVerificationRetryAttempt checks sessionUnchanged() BEFORE any write; a retry that lands after an account switch writes nothing (H-20 class). Future.timeout does not cancel the underlying call, so all writes live outside the bounded unit."
forbidden_patterns_checked:
  - { pattern: "a bare Duration(minutes: N) literal for the grace window or the retry delays in razorpay_service.dart / subscription_service.dart", absent: true }
  - { pattern: "an un-bounded network await that GATES THE GRACE BUDGET (post-checkout refreshSession, the two Phase-1 poll queries, Phase-2 verify-payment, each retry's refresh+call). NOT claimed bounded: refreshFromSupabase() inside the retry and the two Future.delayed refreshes, which run AFTER the grace is cleared and cannot make it fail; and create-razorpay-order before checkout, which precedes the grace clock", absent: true }
proposed_fix: |
  1. New pure lib/core/constants/payment_timing.dart is the ONE source for the
     retry schedule (kVerificationRetryDelays = 60 s / 5 m / 15 m), the Phase-1
     poll schedule, the per-call bounds (8 s poll, 60 s phase-2, 60 s retry
     attempt) and the grace window:
       kPaymentGraceWindow = last retry (15 m) + kActivationPhasesBudget
       (45 s sleeps + 15 x 8 s + 60 s = 225 s) + kRetryAttemptTimeout (60 s)
       + 2 m margin = 1305 s (21 m 45 s).
     Every network call in the activation flow is wrapped in boundedAttempt so
     the budget is a real upper bound, not an estimate.
  2. The retry success branch used to call refreshFromSupabase and clear
     localActivationAt but NEVER clearPaymentInFlight. With the window widened
     that would have turned every retry's reconcile into a no-op (the
     refresh returns early while in flight). runVerificationRetryAttempt now
     runs writeState -> clearGrace -> refresh -> clearLocalActivation in that
     order, with the session-unchanged guard before the call AND before every
     write. Write-first is chosen because if the write THROWS the grace stays
     open and keeps protecting the user; clear-first would leave a cleared
     window and no PRO write. (An earlier draft justified the order by a stale
     in-flight verifyFromServer "not pro" reply; B-pass finding 2 showed that
     reply downgrades either way, so that reason was dropped.) The scheduling
     wiring (session compare, only-this-order's-grace guard, stop-after-first-
     verified latch) lives in scheduleVerificationRetries so it is testable.
  4. B-pass also added a post-query session check to Phase 1 before its write
     (the only check was before the query, which can now run up to 8 s).
  3. SubscriptionService._paymentGraceWindow (10 min literal) is removed;
     isPaymentInFlight reads kPaymentGraceWindow. The separate
     localActivationAt 10-minute grace is deliberately untouched.
  Caveat stated in payment_timing.dart, not fixed: the retries are in-memory
  timers, so they do not fire while the process is suspended or after an app
  kill; the wall-clock grace survives. "Derived" holds under continuous
  foreground execution.
regression_test_planned: |
  test/core/payment_timing_test.dart (11): independent recompute of 45 s /
  225 s / 1305 s from literals, the window outliving every retry, boundedAttempt
  under fakeAsync (times out AT the bound, does not cancel the source).
  test/core/payment_retry_attempt_test.dart (22): a recorder asserts the ORDER
  of the four side effects, server end_date/plan vs fallbacks, the no-verdict
  cases, the session guard before AND after the call, writeState-throws leaves
  the grace open, and scheduleVerificationRetries with an injected scheduler
  (account switch, signed-out, newer order's marker survives, stop-after-first-
  verified, not-verified does not latch, an error does not stop later timers).
  test/subscription/payment_grace_window_test.dart and
  test/contracts/subscription_payment_grace_window_behavioral_test.dart: the
  11-minute case re-seeded to window + 1 min, plus 17-minute and per-retry-delay
  cases. test/contracts/payment_grace_window_derived_wiring_test.dart is a
  presence-only source pin of the razorpay_service wiring.

  Mutation-proven 2026-09-29 (each mutation confirmed applied by an exact
  single-match replace, none a compile error, every red read):
  M1 window -> 10-minute literal: 6 reds. M2 budget drops the phase-2 term: 2.
  M3 delete clearGrace: 1. M4 clear BEFORE write: 1. M5 drop writeState: 4.
  M6 boundedAttempt without the timeout: 3. M7 retry loop on a literal list: 1.
  M8 drop the session guard: 1. M9 razorpay retry closure without the clear: 1.
  Source-pin mutation (fewer bounded calls): found 3 vs required >= 4.
  B-pass finding 1 (the service wiring guards had no test; five mutations of
  them reddened nothing) closed by extracting scheduleVerificationRetries and
  re-proven 2026-09-29: C1 session compare -> true: 2 reds. C2 clear guard ->
  always: 1. C3 -> never: 3. C4 drop the done check: 1. C5 drop the done latch: 1.
  C6 drop the pre-call session check: 3. C7 clear before write: 3. C8 service
  passes a blank userId: 1 (source pin). C9 service session source replaced: 1
  (source pin). C10 an attempt's error aborts later timers: 1.
impact_analysis: |
  Who is affected: a paying user whose Razorpay webhook / verify-payment lands
  more than ~10 minutes after checkout success while the app is in the
  foreground. Before the fix the grace could close with retry 3 (+15 m) still
  pending and verifyFromServer could run _downgradeLocally against a
  not-yet-written subscription. After: the window outlives the last retry plus
  its bounded attempt plus a 2-minute margin.
  Reaches users only with the next founder-initiated APK build; there is no
  server-side component to this half. No data repair is needed (the failure was
  a transient local downgrade that a later refresh restores).
  Not covered: an app kill or process suspension loses the in-memory retries
  (stated in payment_timing.dart).
  DEVIATION from CLAUDE.md section 4.6, disclosed rather than assumed away:
  this rewrites the payment retry path with NO kill-switch and NO preserved old
  path. The old path is the defect (a window that closes early), a flag could
  only keep that value reachable, and the change is client-only and a single
  revert restores it; the Dart files also classify as account-tier on their own
  (the catastrophic tier comes from the Edge Function half of the batch). The
  founder approved the plan without a gate; this note is here so that is a
  visible decision.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "payment_timing.dart + payment_retry_attempt.dart new; razorpay_service.dart, subscription_service.dart, profile_provider.dart edited. flutter analyze lib/ on the whole tree: 0 warnings, 0 errors. 55 targeted tests and 279 tests in 43 related files pass." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "payment_in_flight_at / payment_in_flight_order_id keys unchanged; only the comparison constant changed. The localActivationAt 10-minute windows are untouched (pinned by the wiring contract)." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client-only fix." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data written or repaired." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None for this half (migration 152 belongs to the OI-202 diagnose in the same batch)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "verify-payment is called by the retries but its contract (200 { verified, plan, end_date }) is unchanged by this fix; the OI-202 half of the batch redeploys it separately." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Traced checkout success -> markPaymentInFlight -> Phase 1 poll -> Phase 2 verify-payment -> retries -> clearPaymentInFlight by file:line; the retry now consumes the same {verified, plan, end_date} shape Phase 2 does." }
recurrence: 7ad0cf (2026-05-11, docs/diagnoses/2026-05-11-payment-in-flight-event-based-7ad0cf.md -- the grace window's event-based clear)
related_bugs: [7ad0cf, 7ad0d5]
---

# The payment grace window was shorter than the retry it was meant to protect

## Summary

Two independent literals described one timeline: a 10-minute
`_paymentGraceWindow` in `subscription_service.dart` and an inline
`[60 s, 5 m, 15 m]` retry list in `razorpay_service.dart`. The window opens at
payment success, but the retries are only scheduled after Phase 1 and Phase 2
have exhausted, so the last one fires at roughly `phase1 + phase2 + 15 min` --
after the window had closed. Nothing tied the two numbers together, so nothing
noticed they had drifted apart.

## Writers and readers

Named above by file:line (section 4.1). The window is opened by
`markPaymentInFlight`, read by `isPaymentInFlight`, and cleared event-first by
Phase 1 / Phase 2 / the retry; the time ceiling is only the fallback.

## Fix and what the review rounds changed

The window is now derived from the schedule and the per-call bounds, so
lengthening a delay or a timeout moves the window with it. Three plan-review
rounds shaped this: round 2 caught that widening the window alone would turn the
retry's reconcile into a no-op (the missing `clearPaymentInFlight`), and round 3
caught that the clear must come AFTER the write of PRO state. No round 4 was
run; the record says so.

## Server quota budget (Hermes L29, 2026-09-29)

`verify-payment` rate-limits per USER, not per payment: `consume_quota('verify_payment',
20 per fixed 10-minute bucket)` (`verify-payment/index.ts:236-255`, keyed on
`(user_id, quota_key, window_start)`, `128_usage_counters.sql`). Two `lib/` call
sites invoke it (`razorpay_service.dart` Phase 2 and the retry). Each logical call
can run the handler up to 4 times, because `callFunction`'s cold-start loop
re-invokes on 502/503/504 (`retryColdStart`, up to 3 more).

Budget for one payment on one device: Phase 2 + 3 retries = 4 logical calls x up to
4 handler runs = **at most 16 executions, against a limit of 20**. The margin is 4,
and it is per user: a second device or a second checkout overlapping the first
could exceed it and get a 429 (`Retry-After`, which the client ignores and keeps its
fixed schedule; a refused call is not counted in the ledger). Splash-time
`verifyFromServer` and `gate()` call `verify-subscription`, which has no quota.

`Future.timeout` does not cancel the underlying work, so a call cut by
`boundedAttempt` can keep issuing its cold-start re-invokes for a while. Their
results are discarded and they write nothing, so they cannot threaten the grace
window, but they still spend quota. Stated so nobody widens the retry list or the
cold-start loop without re-deriving this budget.

Two pre-existing points, recorded and not changed by this batch: a retry loop still
running after an account switch can spend the NEW user's quota (`retryColdStart`
has no session check between invokes), and `gate()` now goes without a verify cache
for 21m45s instead of 10m during grace (`verify-subscription` is unlimited, and
calls are driven by user taps).
