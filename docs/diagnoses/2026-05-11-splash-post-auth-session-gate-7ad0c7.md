---
bug_id: 7ad0c7
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 4 splash-time post-auth fire-and-forget startup paths (`RankService.evaluateAndPromote`, `SubscriptionService.refreshFromSupabase`, `ScheduledWorkoutsResyncMigrator.runIfNeeded`, splash `_autoGenerateNextPhaseForPro`) read user-scoped Hive boxes BEFORE `_ensureLocalUser` has opened the namespaced session. Every box read threw `HiveUserSession not opened`; the surrounding catch swallowed it; rank promotions / PRO refresh / one-shot resync / PRO auto-generate next phase silently no-opped on every cold start. Test #12.6 added defensive bootstrap to only the SyncService path; the other 4 still raced.
concept: splash_post_auth_session_gate
sot_registry_entry: splash_post_auth_session_gate
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: ensureOpenedForCurrentSession, line: 70 }
readers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: evaluateAndPromote, line: 45 }
  - { file: lib/core/services/subscription_service.dart, method_or_widget: refreshFromSupabase, line: 291 }
  - { file: lib/core/services/scheduled_workouts_resync_migrator.dart, method_or_widget: runIfNeeded, line: 49 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: _autoGenerateNextPhaseForPro, line: 209 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _ensureSessionOpen, line: 68 }
hive_key_prefix: "userBox_<8hex>"
hive_key_formula: "n/a — gate is read-only path-bootstrap"
sync_methods: []
restore_methods: []
cloud_table: "n/a — gate runs entirely client-side at session open"
cloud_columns: []
contract_test_path: test/contracts/splash_post_auth_session_gate_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [hive_session_opened]
  failure: [ensure_session_open]
cross_account_guard: yes
forbidden_patterns_checked: ["fire_and_forget_userbox_read_pre_ensure_local_user"]
proposed_fix: Lift `SyncService._ensureSessionOpen` into a public static `HiveUserSession.ensureOpenedForCurrentSession()` that reads `SupabaseService.currentUser?.id`, calls `openForUser` if not already open for that id, funnels failures through `ErrorTelemetry.recordNonFatal`, and returns the uid (or null if no session). Refactor `SyncService._ensureSessionOpen` to delegate. Add `await HiveUserSession.ensureOpenedForCurrentSession()` to the top of the 4 racing entry points so each one inherits the same idempotent bootstrap. Telemetry surfaces both successful opens (`hive_session_opened`) and failures (`ensure_session_open`).
regression_test_planned:
  - test/contracts/splash_post_auth_session_gate_test.dart
---
# Audit C-7: 6 startup mutations ran before user session opened

## Bug

`splash_screen.dart` fires 6 post-auth fire-and-forget startup paths
during `_runDeferredInit`. Each touches user-scoped Hive
(`userBox` / `workoutBox` / `coachBox` / etc.) which are `GuardedBox`
instances that throw `HiveUserSession not opened` until
`auth_provider._ensureLocalUser` runs and calls
`HiveUserSession.openForUser(user.id)`.

Pre-fix:

- `pushSnapshot` (line 149) — already bootstrapped via Test #12.7
  `SyncService._ensureSessionOpen`. ✓
- `ScheduledWorkoutsResyncMigrator.runIfNeeded` (line 158) — raced.
- `checkAndSync` (line 162) — already bootstrapped. ✓
- `RankService.evaluateAndPromote` (line 165) — raced.
- `SubscriptionService.refreshFromSupabase` (line 170) — raced.
- `_autoGenerateNextPhaseForPro` (line 182) — raced.

Effect of each race:

- **RankService**: `_readEvaluationState` reads `workoutBox.keys` for
  streak math + `userBox.get('profile')` → throws → catch swallows →
  user misses every catch-up rank promotion until the next non-cold-
  start event.
- **SubscriptionService**: `configBox.get('isPro')` + MigratedKey
  reads / writes → throws → catch swallows → upgrade pill stays grey
  even after server confirms PRO.
- **ScheduledWorkoutsResyncMigrator**: `userBox.get(flagKey)` +
  `workoutBox.keys` → throws → catch swallows → one-shot resync of
  divergent `schedule_<date>` rows from APK Test #14 never runs.
- **_autoGenerateNextPhaseForPro**: `UserRepository.getProfile()` reads
  userBox → throws → catch swallows → PRO users on cold start with an
  expired Phase silently miss next-phase auto-generation.

## Cause

`HiveUserSession.openForUser` is the bootstrap that opens namespaced
boxes. It only runs from `auth_provider._ensureLocalUser`, which is
triggered by the Supabase auth listener. Splash kicks off the 4 racing
paths from `_runDeferredInit` in parallel — without awaiting the auth
listener.

Test #12.6 closed this for the SyncService paths via a private
`_ensureSessionOpen` helper. The other 4 paths never got the same
treatment.

## Fix

Lift `_ensureSessionOpen` into a public static
`HiveUserSession.ensureOpenedForCurrentSession()`. Refactor
`SyncService._ensureSessionOpen` to a one-liner delegation. Add
`await HiveUserSession.ensureOpenedForCurrentSession()` at the top of
the 4 racing entry points.

The helper is idempotent: when the session is already open for the
current uid, it short-circuits without re-opening. When no Supabase
session exists, it returns `null` and the caller short-circuits.

## Regression test

`test/contracts/splash_post_auth_session_gate_test.dart` — 6 source-grep
assertions covering:

1. The shared helper exists.
2-5. Each of the 4 racing entry points calls
     `HiveUserSession.ensureOpenedForCurrentSession`.
6. `splash_screen.dart` no longer carries the legacy no-op
   `HiveService.instance.userBox.get('profile')` block (C-6 sibling).

Plus updates to two existing tests (`test/safety/guarded_box_auto_open_test.dart`,
`test/sync/sync_telemetry_test.dart`) so they accept the delegation
form alongside the old inline form.

## Related

- 7ad0c6 (C-6 — sibling fix lifting the cross-account guard into
  `openForUser` itself)
- CLAUDE.md §15 (sync fan-out contract)
- Test #12.6 (the original defensive openForUser added to one path)
