---
bug_id: b3f8e5
date: 2026-09-26
batch: ci-green-batch-a (U2a — the OI-242 flake)
status: fixed
blast_radius: feature
symptom: >
  CI "Unit Tests" failed intermittently on
  `test/contracts/realtime_pro_gate_behavioral_test.dart` — "e4a7c9 — the
  teardown half … THE SECOND BUG: a downgrade fires onDowngrade" —
  `Expected: true  Actual: <false>` ("an expiry downgrade must release
  PRO-owned resources"), followed by a trailing
  `HiveError: Box not found` from `StreakProgressService.resetToFreeCapOnLapse`
  ← `SubscriptionService._downgradeLocally` (:1225). Green in isolation (9/9).
  Flapped on main independently of any PR (024d7a82 red, e7733cb8 green, PR #37
  red; OI-242). Same class also sat latent in the expiry-banner and
  paused-for-simulation files, which awaited the same chain with a proxy.
concept: >
  `isPro()` on an expired row starts `_downgradeLocally()` WITHOUT awaiting it
  (`subscription_service.dart:480-483`, and :461 for the cross-account wipe) —
  correct, since isPro() is a synchronous bool. `_downgradeLocally` (:1175)
  awaits its Hive writes one at a time (:1191-1195), then fires onStateChanged
  (:1199), then onDowngrade (:1213). The tests waited for that chain with a
  PROXY (`pumpEventQueue()`, a banner `_settle` quiescence sampler, a fixed
  sleep). Every write after the first await sits behind real per-box-serialised
  file I/O, so on a loaded runner the proxy returned first: the assertion read
  pre-downgrade state, and the file's tearDown then closed Hive under the still
  running chain, which is where the trailing Box-not-found comes from. The fix
  waits for the production signal (onDowngrade, which has exactly one caller)
  instead of any proxy.
sot_registry_entry: >
  None added. No production file changes; subscription_state already registers
  this writer/reader set. The change is a test-harness synchronisation primitive.
writers:
  - { file: lib/core/services/subscription_service.dart, method: "isPro() genuine-expiry branch — `_downgradeLocally();` with no await", line: 483 }
  - { file: lib/core/services/subscription_service.dart, method: "_downgradeLocally — awaited writes, then onStateChanged", line: 1199 }
  - { file: lib/core/services/subscription_service.dart, method: "_downgradeLocally — onDowngrade?.call(), the ONLY caller of that hook; the completion signal this fix waits for", line: 1213 }
readers:
  - { file: test/contracts/realtime_pro_gate_behavioral_test.dart, method: "THE SECOND BUG — was isPro() + pumpEventQueue(); now arm → isPro() → await downgrade.wait()", line: 1 }
  - { file: test/contracts/subscription_expiry_banner_behavioral_test.dart, method: "two expiry sites — `_settle` quiescence sampler DELETED (0 callers would be an unused_element warning); now arm/wait", line: 1 }
  - { file: test/contracts/subscription_paused_for_simulation_guard_test.dart, method: "case A + the un-paused re-call — now arm/wait; the PAUSED cases keep their sleep because a paused downgrade fires no hook", line: 102 }
hive_key_prefix: expiresAt
hive_key_formula: "userBox['expiresAt'|'plan'|'lastVerifiedAt'] via MigratedKey — user-scoped; deleted by _downgradeLocally after its first await."
sync_methods: not_applicable — written locally by _downgradeLocally, never pushed by this path.
restore_methods: not_applicable — re-derived from the subscription row on refresh.
cloud_table: none — local mirror; the authoritative row is subscriptions.current_period_end.
cloud_columns: none — see cloud_table.
contract_test_path: test/contracts/pro_downgrade_waiter_behavioral_test.dart
recurrence: >
  FOURTH instance of this class. 2026-08-10 (cqrs file) replaced a 20 ms sleep
  with a quiescence sampler; 2026-08-25 f3c7d2 added a setUp drain loop;
  2026-08-27 a3e9b7 chained onStateChanged inside the cqrs `_settle`. Each fix
  was local to ONE file, so the realtime / banner / paused-guard files kept
  their own proxies and this one flaked on CI. This fix is a SHARED helper
  (`test/helpers/pro_downgrade_waiter.dart`) so the next call site imports the
  wait instead of re-deriving it. It waits on onDowngrade, not onStateChanged,
  because onStateChanged has two other writers (:70, :326) that would resolve a
  waiter early.
related_bugs: [a3e9b7, f3c7d2, e4a7c9]
ist_handling: not_applicable — expiry is an absolute-instant comparison, not an IST day key.
cross_account_guard: >
  Unchanged. The :477-480 lapse-marker write stays gated on
  HiveUserSession.currentOwnerFullId; no production code changes.
provider_invalidations: >
  None changed. The waiter CHAINS onDowngrade (calls the previously-installed
  hook inside try/finally), so a test's own hook still runs, in order.
telemetry_op_types: none — no telemetry event emitted or altered.
forbidden_patterns_checked: >
  No production code. No fixed sleep introduced; the one retained 50 ms sleep is
  on the PAUSED path, where no signal exists by design (asserting a non-event).
  No teardown that can throw (a teardown failure stacks on top of and hides the
  real one, CLAUDE.md §4.9).
impact_analysis: >
  Test-harness only, feature tier. Four test files + one new helper + one new
  behavioural test. The waiter's `wait()` bound (10 s) is below the 30 s default
  test budget so a genuine regression fails BY NAME rather than as "test timed
  out". Suite cost is unchanged on the happy path (the signal arrives in ms).
proposed_fix: >
  New `ProDowngradeWaiter` (arm / wait / self-draining teardown / idempotent
  restore / nested-arm refusal). arm() chains onDowngrade and registers an
  addTearDown drain — test_api runs teardowns LIFO, so it runs BEFORE the file's
  tearDown closes Hive. Rejected: widening the proxy again (what the three prior
  fixes did); waiting on onStateChanged (other writers); a drainArmed() call in
  each file's tearDown (R2 F1 — LIFO order runs it after the addTearDown).
regression_test_planned: >
  test/contracts/pro_downgrade_waiter_behavioral_test.dart (new, 11 tests) +
  the three migrated files; 27/27 green together. The race is made
  DETERMINISTIC rather than waited for: 2000 unawaited puts are queued on the
  user box right before isPro(), so every downgrade write sits behind ≥2000
  serialised I/O completions. MEASURED 2026-09-26 — old wait (pumpEventQueue)
  RED 5/5 on `fired`; waiter green 3/3. A single 16 MiB put (the plan-review
  probe fixture) was NOT deterministic on this machine — the old wait passed
  with it — so count, not size, is the lever. MUTATIONS, each applied (grep
  confirmed) and reverted: (a) `wait()` body → `pumpEventQueue()` reddened 5
  (REAL chain, 300 ms late signal, never-fires, hook-replaced, restores-previous);
  (b) the teardown drain skips its await reddened 1 ("…and the waiter drained
  it in its own teardown, first"). (c) the realtime file's header mutation 2
  (delete `onDowngrade?.call()` at :1213) re-measured: 1 red, THE SECOND BUG,
  now failing BY NAME ("onDowngrade never fired within 10000 ms"). The
  `[HiveUserSession] migrationBox unavailable` debugPrint lines seen during these
  runs also appear in fully GREEN runs (11 and 9 lines) — setup-ordering noise,
  not a signal of this defect.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No lib/ file changed. flutter analyze on the touched test files: 0 warnings/errors." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Real-chain test asserts expiresAt/plan/lastVerifiedAt deleted (seeded, so not vacuous) after wait(); old wait red 5/5, waiter green 3/3 under the 2000-write backlog." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed; CI → main is the observable, verified via the OI-242 run logs." }
---

# The downgrade wait sampled a proxy, and lost the race on CI

## What failed

`realtime_pro_gate_behavioral_test.dart` "THE SECOND BUG" asserted that
`onDowngrade` had fired after `isPro()` + `pumpEventQueue()`. On a loaded CI
runner the downgrade chain was still inside its awaited Hive writes, so the
hook had not fired (`Expected: true Actual: <false>`), and the file's tearDown
then closed Hive under the running chain, producing the trailing
`Box not found` that made the failure look like an isolation bug.

## Root cause

`isPro()` fires `_downgradeLocally()` without awaiting it (`:480-483`). Every
test that waited for it did so with a proxy. The proxy is bounded by event-loop
turns; the chain is bounded by file I/O. They are unrelated clocks.

## Fix

`test/helpers/pro_downgrade_waiter.dart` waits for `onDowngrade`, the one
signal fired only by `_downgradeLocally` after all its awaited writes. It
chains any existing hook, fails by name on timeout or on a replaced hook, and
drains itself in a teardown that runs before the file's own.

## Scope, stated

U2a only. The cqrs file's 12 `_settle` sites and the grace-window file keep
their a3e9b7 behaviour; the three review rounds kept finding new issues in the
machinery proposed for them, so per §4.12.1 they were split out (U2b). OI-86
stays OPEN, narrowed to those two files.

## Regression test

See `regression_test_planned` — deterministic reproduction plus three mutations.
