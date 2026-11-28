---
bug_id: e3f7a8
date: 2026-05-10
batch: APK Test #14
status: in_progress
symptom: A subset of users (founder included) holds Hive `schedule_<date>` rows with `status='completed'` while the cloud `scheduled_workouts` row stays at `status='planned'` for those dates. Once Bugs B.1 + B.2 ship, future writes stay consistent — but existing divergence won't self-heal without an explicit re-push.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/scheduled_workouts_resync_migrator.dart, method_or_widget: ScheduledWorkoutsResyncMigrator.runIfNeeded, line: 50 }
readers:
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: SplashScreen._runDeferredInit, line: 108 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods:
  - SyncService.syncWorkoutData
restore_methods:
  - SyncService._restoreScheduledWorkouts
cloud_table: scheduled_workouts
cloud_columns:
  - status
  - completed_at
contract_test_path: test/safety/scheduled_workouts_resync_migrator_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - calendarWeekProvider
  - todayWorkoutProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: per-user flag in userBox makes the migrator user-scoped — different users on the same device get separate gates
forbidden_patterns_checked: []
proposed_fix: |
  One-shot, idempotent migrator gated by
  userBox['apk_test_14_completion_resync_done']. Iterates
  workoutBox.keys looking for `schedule_<date>` entries with
  status=='completed' and non-null completed_at. If any candidates
  exist, calls SyncService.instance.syncWorkoutData() once — the
  hardened _syncScheduledWorkouts (Bug B.1 fix) handles each row's
  cloud-template-id resolution and 23503 self-heal. After completion
  the flag is set; subsequent launches short-circuit immediately.
  On error, the flag stays UNSET so the next launch retries. Wired
  into SplashScreen._runDeferredInit fire-and-forget after Supabase
  initialize and before checkAndSync.
regression_test_planned:
  - test/safety/scheduled_workouts_resync_migrator_test.dart
---

# Bug B.3 — One-shot resync migrator for pre-fix completion divergence (APK Test #14)

## Symptom

Founder's account (and likely a small population of users who hit the same FK-violation window) holds Hive `schedule_<date>` rows with `status='completed'` while the cloud `scheduled_workouts` row stays at `status='planned'`. Once Bug B.1 (self-healing push) and Bug B.2 (non-destructive merge) ship, future writes stay consistent — but the existing divergence cannot self-heal without explicitly re-pushing the affected rows.

## Root cause

This is not a "live bug" so much as the **forensic fallout** of Bugs B.1 + B.2:
- Bug B.1: `_syncScheduledWorkouts` 23503'd silently on every push that carried a non-null `template_id`, so completed rows never reached cloud.
- Bug B.2: `_restoreScheduledWorkouts` then overwrote those local 'completed' rows with cloud's stale 'planned' on every restore.

Net result: even though the user genuinely completed the workout, every cold-start renders the calendar with no tick. Bug B.2's fix prevents future destruction; Bug B.1's fix prevents future failures. But neither is retroactive — old `completed` Hive rows stay stranded unless something nudges them.

## Fix

`ScheduledWorkoutsResyncMigrator.runIfNeeded()` (lib/core/services/scheduled_workouts_resync_migrator.dart:50):

1. Reads `userBox['apk_test_14_completion_resync_done']`. If `true`, returns immediately.
2. Iterates `workoutBox.keys` where the key starts with `'schedule_'`. For each entry with `status == 'completed'` AND non-empty `completed_at`, increments a candidate counter.
3. If any candidates exist, calls `SyncService.instance.syncWorkoutData()` once. The hardened `_syncScheduledWorkouts` (Bug B.1) handles per-row template-id resolution + 23503 self-heal + null-template fallback.
4. Sets the flag.

Failure handling: any exception (Hive corruption, network error in `syncWorkoutData`) leaves the flag UNSET so the next launch retries. The migrator is purely opportunistic — it must never escalate failures to the user.

Wired into `SplashScreen._runDeferredInit` fire-and-forget after `SupabaseService.instance.initialize()` (auth ready) and before `SyncService.instance.checkAndSync()` so the migrator's `syncWorkoutData()` call benefits from a warm session and runs through the new lookup-by-name path.

## Verification

Source-grep contract test pins:
- Class `ScheduledWorkoutsResyncMigrator` declared with static `runIfNeeded` method
- Flag literal `'apk_test_14_completion_resync_done'` present
- Migrator iterates `'schedule_'` prefixed keys
- Migrator calls `SyncService.instance.syncWorkoutData()`

After-state on founder's user_id `d7a67a37…`: on next post-update cold start, the migrator finds Saturday May 9 (and any other completed-but-not-pushed dates) and triggers a re-push. The hardened sync resolves cloud `workout_templates.id` by name, succeeds, and the `scheduled_workouts.status` row transitions `planned → completed`.

## Related

- Bug B.1 (`docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md`) — push-side root cause.
- Bug B.2 (`docs/diagnoses/2026-05-10-restore-overwrite-d9b2c5.md`) — restore-side fix that made re-push viable.
- CLAUDE.md §15 "Restore-completeness sync" — pattern for one-shot migrators.
