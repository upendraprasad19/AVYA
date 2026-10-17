---
bug_id: c7e1a4
date: 2026-05-31
batch: rank-deployment-sequential-2026-05-31
status: fixed
symptom: >
  During the live-web year-sim (driving amar to Lieutenant), the dev PRO grant
  was silently wiped within ~1 second of being granted — BEFORE the sim loop
  started. The `/dev` autorun logged `isPro right after grant = false` and
  `post-grant raw: isPro=false expiresAt=null`, and every `[sim-diag]` line
  read `pro=false`. Because phase advancement is gated on `sub.isPro()`, the
  schedule stayed at Phase 1 for the entire run (`phase=1` at day 0/7/14/21/28…
  even after `expired=true`), so no phases generated, no deployments accrued,
  and rank never climbed past LS. The earlier `pausedForSimulation` guard added
  at the TOP of `refreshFromSupabase` did not fix it.
concept: subscription_state
sot_registry_entry: subscription_state
blast_radius: account
writers:
  - { file: lib/core/services/subscription_service.dart, method: writeSubscriptionState (MigratedKey.write isPro/expiresAt/plan), line: 230 }
  - { file: lib/core/services/subscription_service.dart, method: _downgradeLocally (clears isPro + deletes expiresAt/plan/localActivationAt/lastVerifiedAt), line: 762 }
  - { file: lib/features/dev/dev_panel_screen.dart, method: _grantPro → writeSubscriptionState(isPro true, 10-yr expiry), line: 208 }
readers:
  - { file: lib/core/services/subscription_service.dart, method: isPro() reads MigratedKey isPro + expiresAt, line: 278 }
  - { file: lib/features/dev/simulation_service.dart, method: run() day-loop gates _maybeAdvancePhase on sub.isPro(), line: 258 }
hive_key_prefix: "userBox['isPro'] / userBox['expiresAt'] / userBox['plan'] (via MigratedKey)"
hive_key_formula: "n/a — top-level entitlement keys"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [status, end_date, plan]
contract_test_path: test/contracts/subscription_paused_for_simulation_guard_test.dart
ist_handling:
  - { site: "_grantPro expiry = nowWall()+3650d; isPro() expiry compares DateTime.now() (real wall clock, intentionally not sim clock)", helper: nowWall, status: ok }
provider_invalidations: [subscriptionInfoProvider]
telemetry_op_types:
  success: [subscription_state_write]
  failure: []
cross_account_guard: >
  isPro()'s cross-account check (localId vs sessionId) is unaffected — both
  resolve to amar (0f35f3dd) during the sim. The guard added here is gated on
  the debug-only static `pausedForSimulation` (always false in release/normal
  flow), so production downgrade behaviour — including the Auto-Backup
  cross-account leak downgrade — is unchanged.
forbidden_patterns_checked:
  - { pattern: "pause/suppression flag checked only at function entry while the suppressed work can already be in flight", absent: true }
  - { pattern: "dev-only grant survives a real refreshFromSupabase with no cloud row", absent: false }
proposed_fix: >
  Move the `pausedForSimulation` guard from the TOP of `refreshFromSupabase`
  to the shared SINK `_downgradeLocally()` (an early-return no-op while paused).
  An entry-guard cannot catch a refresh that passed the check BEFORE the flag
  was set and is still awaiting its network response — exactly what happens
  during the ~100s boot restore: splash / sync / auth_session_bootstrapper all
  fire `unawaited(refreshFromSupabase())` while paused=false; the response
  (no active subscriptions row → _downgradeLocally) lands after the autorun
  sets paused=true and grants PRO, wiping it. Guarding the sink covers every
  downgrade caller (refreshFromSupabase ×3, verifyFromServer, and the in-line
  expiry / cross-account branches inside isPro()) regardless of in-flight
  timing. Kept the existing entry guard too (cheap belt-and-braces).
regression_test_planned:
  - test/contracts/subscription_paused_for_simulation_guard_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "guard added at _downgradeLocally top; flutter analyze clean; 3/3 behavioral tests pass (CASE A downgrades, CASE B preserves, flag-scope restores)" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "behavioral test asserts userBox isPro/expiresAt/plan preserved while paused, wiped while un-paused; live web autorun console: post-grant isPro=true expiresAt=2036, [sim-diag] pro=true all days, phase advanced 1→2 at day 28" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "live-web diag run (49d) end-to-end: grant→preserve→phase-gen confirmed in browser console on the real amar account" }
impact_analysis: >
  Account-tier and debug-only in EFFECT: the guard is gated on a static flag
  that is always false outside the dev year-sim, so real users' downgrade
  behaviour is untouched. The bug only manifested in the sim harness, but it
  fully blocked the harness from demonstrating the deployment→rank→Lieutenant
  loop (the whole point of the 2.5-year run + plan export). The underlying
  lesson generalises: a suppression/pause flag must be enforced at the point
  of the side-effect, not only at the entry of an async function whose body
  can already be in flight when the flag flips.
---

# c7e1a4 — dev year-sim PRO grant wiped by an in-flight refreshFromSupabase

## What happened
The `/dev` autorun (driving amar to Lieutenant) does:
`pausedForSimulation = true` → `resetJourney` → `_grantPro()` (writes
`isPro=true`, `expiresAt = now+3650d`) → `run(910 days)`. Yet the very next log
read `isPro right after grant = false` with `expiresAt=null` — the exact
signature of `_downgradeLocally()` (it sets `isPro=false` and *deletes*
`expiresAt`/`plan`). Phase advancement (`if (sub.isPro()) _maybeAdvancePhase`)
therefore never fired; the schedule was frozen at Phase 1 for the whole run.

## Why the first fix didn't work
The initial `pausedForSimulation` guard was placed at the **top of
`refreshFromSupabase`**. But the boot sequence fires several
`unawaited(refreshFromSupabase())` calls (splash_screen:166,
sync_service:1099, auth_session_bootstrapper:470) DURING the ~100s boot
restore, while `paused` was still `false`. Those calls pass the entry guard,
make their network round-trip, and resolve ~seconds later — AFTER the autorun
set `paused=true` and granted PRO. Their `response == null` (amar has no
`subscriptions` row) branch calls `_downgradeLocally()`, wiping the grant. An
entry-guard is structurally unable to stop an already-in-flight call.

## Fix
Guard the shared **sink**: `_downgradeLocally()` returns early (no-op) while
`pausedForSimulation` is true. This is the single funnel for every downgrade
path — `refreshFromSupabase` (×3 branches), `verifyFromServer`, and the
in-line expiry / cross-account checks inside `isPro()` — so it holds
regardless of which caller, and regardless of in-flight timing. The flag is
debug-only and always false in release/normal flow, so production downgrade
behaviour (including the cross-account Auto-Backup leak downgrade) is
unchanged.

## Verification
- `flutter analyze` clean.
- `test/contracts/subscription_paused_for_simulation_guard_test.dart` — 3/3
  pass: CASE A (un-paused) downgrades; CASE B (paused) preserves
  `isPro`/`expiresAt`/`plan`; flag-flip restores normal downgrade. Fails
  without the guard (CASE B's `isPro()` expiry branch wipes the state).
- Live-web diag (49-day) on the real amar account: `post-grant raw: isPro=true
  expiresAt=2036…`, `[SubscriptionService._downgradeLocally] paused for
  simulation — preserving dev-granted PRO`, every `[sim-diag] pro=true`, and
  `phase` advanced 1→2 at day 28 (phase generation confirmed live).
