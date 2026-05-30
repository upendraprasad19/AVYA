---
bug_id: d5c1b8
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Surfaced during live web E2E by reloading onto the /#/coach/induction hash
  route. The app rendered GoRouter's error page ("Page Not Found") with:
  "GoException: Exception during redirect: Bad state: HiveUserSession not
  opened — cannot wrap user-scoped box coachBox. Call
  HiveUserSession.openForUser(userId) after sign-in." Cold-start /
  deep-link / process-death-restore onto /coach/* crashes routing.
concept: hive_session_init_race
sot_registry_entry: auth_hive_owner_agreement
blast_radius: account
writers:
  - { file: lib/features/ai_coach/services/induction_service.dart, method: completeMuster, line: 108 }
  - { file: lib/features/ai_coach/services/induction_service.dart, method: recordCommitment, line: 32 }
readers:
  - { file: lib/features/ai_coach/services/induction_service.dart, method: inductionCompleted, line: 33 }
  - { file: lib/features/ai_coach/services/induction_service.dart, method: hasCommitted, line: 30 }
  - { file: lib/core/router/app_router.dart, method: _authRedirect, line: 542 }
hive_key_prefix: "coachBox (user-scoped)"
hive_key_formula: "coachBox['induction_completed_at'] / coachBox['committed_to_lt_cdr']"
sync_methods: []
restore_methods: []
cloud_table: coach_memory
cloud_columns: []
contract_test_path: test/contracts/induction_service_session_guard_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  This bug IS a cross-account-guard interaction: coachBox is wrapped by
  wrapUserScopedBox, which throws "HiveUserSession not opened" before
  openForUser runs. The guard correctly refuses the read; the caller
  (GoRouter redirect) failed to anticipate the not-open state.
forbidden_patterns_checked:
  - { pattern: "inductionCompleted reads coachBox without a session-open guard", absent: true }
proposed_fix: >
  GoRouter._authRedirect (isOnCoachInduction branch) calls
  InductionService.inductionCompleted during redirect, which reads the
  user-scoped coachBox. At cold start the redirect fires BEFORE
  HiveUserSession.openForUser, so the GuardedBox throws and the exception
  escapes the redirect -> GoRouter error page. Fix: inductionCompleted and
  hasCommitted short-circuit to false when HiveUserSession.currentOwnerFullId
  == null, BEFORE touching coachBox. "Session not open yet" means induction
  state is unknown; not-completed is the safe default (the induction flow
  re-evaluates once the session opens). Guards both getters (defense for every
  caller, not just the router).
regression_test_planned:
  - test/contracts/induction_service_session_guard_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "induction_service.dart hasCommitted + inductionCompleted now short-circuit on HiveUserSession.currentOwnerFullId == null; verified failing-then-passing via induction_service_session_guard_test.dart (reproduces the exact StateError)" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "no Hive contract change; same coachBox keys, just guarded read; wrapUserScopedBox behaviour unchanged" }
  - { tier: 12, layer: end_to_end_contract, status: fixed_in_this_batch, evidence: "live web reload onto /#/coach/induction reproduced GoException; behavioral test pins no-throw + false return with no session open" }
impact_analysis: >
  Trigger requires landing on /coach/induction (or /coach/muster) at cold start
  before the session opens. On Android the app cold-starts at /splash, so the
  common path is unaffected; the trigger is web reload, deep-link, or
  process-death restoration onto /coach/* (GoRouter preserves the last route).
  Primarily a web-target and deep-link crash, but real: the redirect's
  inductionCompleted read had only a HiveService.isInitialized guard, not a
  session-open guard. Same root class as diagnose dc52a4 (HiveUserSession not
  opened — userBox touched before openForUser), here on the read side via the
  router redirect. No data loss; the failure mode is a routing crash to the
  GoRouter error page. Account-tier: per-user auth/coach-flow routing.
---

# d5c1b8 — induction redirect read a user-scoped box before the session opened

## What happened
Reloading the live web app onto `/#/coach/induction` rendered GoRouter's error
page. `_authRedirect`'s `isOnCoachInduction` idempotency branch
(`app_router.dart:541–547`) calls `InductionService.instance.inductionCompleted`
to bounce already-inducted users to `/home`. That getter reads the user-scoped
`coachBox` (`induction_service.dart:25–26`), guarded only by
`HiveService.isInitialized` — **not** by `HiveUserSession` being open. At cold
start the redirect runs before `openForUser`, so the wrapped box throws
"HiveUserSession not opened", the exception escapes the redirect, and GoRouter
shows its error page.

## Root cause
A user-scoped read performed at redirect time, before the session is guaranteed
open. Same class as dc52a4 (splash touched `userBox` pre-`openForUser`), here on
the read side and triggered by deep-link/reload onto `/coach/*`.

## Fix
`inductionCompleted` and `hasCommitted` short-circuit to `false` when
`HiveUserSession.currentOwnerFullId == null`, before touching `coachBox`. The
redirect then treats the user as not-yet-inducted and passes through
(`return null`), letting `InductionScreen` run; it re-evaluates once the session
opens. Guarding both getters defends every caller, not just the router.

## Verification
`induction_service_session_guard_test.dart` reproduces the exact StateError on
`main` (both getters throw with no session) and passes with the fix (both return
`false` without touching Hive) — this is the authoritative proof. Live web
re-verification (reload onto /#/coach/induction no longer crashing) requires a
web rebuild, since the running dev server still holds the pre-fix bundle.
