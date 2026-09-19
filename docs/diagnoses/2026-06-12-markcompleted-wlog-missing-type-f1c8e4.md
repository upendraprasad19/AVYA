---
bug_id: f1c8e4
date: 2026-06-12
batch: audit-2026-06-10
status: fixed
blast_radius: account
symptom: >
  Quarterly audit deep-verify finding (surfaced while verifying apk34 c2e8b4).
  The canonical LIVE completion writer WorkoutWriteService.markCompleted (which
  the A-13 derive-only refactor made "replace saveWorkoutLog + markWorkoutCompleted"
  — train_provider.completeWorkout routes here) wrote its wlog_<date> row WITHOUT
  `type: 'workout_log'` and used `completed_at_ms` instead of the ISO
  `completed_at`. EVERY count/history reader filters `type == 'workout_log'`
  (getWeeklyWorkoutCounts → reports "This Week" tile + 4-week frequency chart,
  getWorkoutLogs → history, BadgeService.totalWorkouts, AiSnapshotBuilder) and
  getRecentWorkoutCompletionHours reads `completed_at`. So a workout completed
  live on the current install was INVISIBLE to all of them — the "This Week"
  count (repointed here by apk34 c2e8b4), frequency chart, history, badge total
  and AI coach context all undercounted — until a reinstall+restore
  (_restoreWorkoutLogs DOES stamp type + completed_at) re-tagged the row. The
  additive restore guard never upgrades a pre-existing type-less row, so counts
  were correct right after a reinstall then drifted down per completion.
concept: hive_field_name_wlog
sot_registry_entry: hive_field_name_wlog
writers: >
  workout_write_service.dart markCompleted (the canonical live writer — fixed to
  stamp type:'workout_log' + completed_at ISO) + sync/sync_workout.dart
  _restoreWorkoutLogs (restore path, already stamped both) +
  wlog_type_backfill_migrator.dart runIfNeeded (one-shot heal for legacy rows).
readers: >
  workout_repository.dart getWeeklyWorkoutCounts (type+date),
  getWorkoutLogs (type+date+workout_name),
  getRecentWorkoutCompletionHours (completed_at ISO); badge_service.dart
  totalWorkouts (type); ai_snapshot_builder.dart recent-workouts (type).
hive_key_prefix: "wlog_"
hive_key_formula: "wlog_${istDateStr(date)} (WorkoutWriteService.wlogKey)"
sync_methods: _syncWorkoutLogs
restore_methods: _restoreWorkoutLogs
cloud_table: workout_logs
cloud_columns: "user_id, workout_name, date, logged_at, duration_seconds, created_at (NO type column — type is a Hive-only field; _syncWorkoutLogs selects rows by wlog_ key-prefix and projects explicit columns, so the writer fix is push-safe)"
contract_test_path: test/contracts/markcompleted_wlog_counted_test.dart
ist_handling: >
  wlog key + the `date` field use istDateStr (unchanged). `completed_at` /
  `completed_at_ms` are an instant timestamp (an authoring time), NOT an IST
  date-key, so DateTime.now() is correct there.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["wlog_type_backfill_migrator_run_if_needed", "wlog_type_backfill_migrator_migration_box_unavailable"]
cross_account_guard: true
forbidden_patterns_checked:
  - "markCompleted wlog map missing 'type' — readers filter type=='workout_log'; the writer now stamps it (pinned by the behavioral test + the hive_field_name_wlog SoT class_constraints)."
  - "markCompleted writing only completed_at_ms — getRecentWorkoutCompletionHours reads the ISO completed_at; both are now written from one instant."
proposed_fix: >
  (1) markCompleted's wlog map stamps `type: 'workout_log'` + `completed_at`
  (ISO, from the same instant as completed_at_ms) so all count/history readers
  see the live row. (2) WlogTypeBackfillMigrator (one-shot, migrationBox-gated,
  wired into the auth_provider boot migrator sequence after LoggingTypeRepairMigrator)
  heals legacy type-less wlog rows already on-device so historical weeks count
  without a reinstall. (3) New hive_field_name_wlog SoT concept pins type +
  completed_at as REQUIRED so a future refactor can't silently drop them again.
regression_test_planned: >
  test/contracts/markcompleted_wlog_counted_test.dart — behavioral: a live
  markCompleted is counted by getWeeklyWorkoutCounts (==1) + surfaced by
  getWorkoutLogs + the row carries type:'workout_log' + ISO completed_at. Fails
  RED against the pre-fix writer (count 0, history empty, type null).
  test/safety/wlog_type_backfill_migrator_test.dart — pure repairRow cases +
  behavioral heal of a legacy type-less row + idempotency.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "markCompleted writer fix + WlogTypeBackfillMigrator + auth_provider wiring; flutter analyze clean" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "markcompleted_wlog_counted_test (7 assertions) + wlog_type_backfill_migrator_test (heal + idempotent) all green" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "_syncWorkoutLogs (sync_workout.dart:70) selects wlog_ rows by KEY-PREFIX and projects explicit columns (user_id/workout_name/date/logged_at/duration_seconds/created_at) — it does NOT read `type`; cloud workout_logs has no `type` column. Adding `type` to the Hive row is push-safe + round-trips (restore re-stamps it)." }
impact_analysis: >
  Account blast radius (canonical completion writer + a boot-path migrator,
  per-user data only — no schema/cron/payment). User-visible undercount on a
  CORE engagement metric: every workout completed
  live on the current install was missing from the reports "This Week" tile +
  4-week frequency chart, the workout history list, the badge lifetime total and
  the AI coach's recent-workout context — only restore-sourced (reinstall) rows
  counted. NOT affected (so P1, not catastrophic, no data loss): the daily streak
  (reads schedule_<date> status=='completed') and the lifetime total_workouts_done
  counter (incremented separately in train_provider) were both correct; the cloud
  workout_logs rows were intact (pushed by wlog_ key-prefix). The drift was an
  accidental field drop in the A-13 derive-only refactor (the replaced
  saveWorkoutLog stamped both fields); no test pinned `type` on the wlog row —
  the one test touching it (schedule_completion_duration_writer_to_reader) pins
  duration_seconds only. related: c2e8b4 (apk34 — repointed "This Week" to
  getWeeklyWorkoutCounts, making the undercount visible).
---

# markCompleted wlog row missing `type: 'workout_log'` (f1c8e4)

## What happened
`WorkoutWriteService.markCompleted` is the canonical LIVE completion writer
(`train_provider.completeWorkout` calls it; the A-13 derive-only refactor made it
"Replace repo.saveWorkoutLog + repo.markWorkoutCompleted"). It wrote the
`wlog_<date>` row **without** `type: 'workout_log'` and with `completed_at_ms`
instead of the ISO `completed_at`. Every count/history reader filters
`type == 'workout_log'` and the streak-warning time reader parses `completed_at`,
so a live completion was invisible to all of them until a reinstall+restore
re-tagged the row.

## Root cause
The replaced `saveWorkoutLog` (now dead) stamped both `type: 'workout_log'` and
`completed_at`; the A-13 refactor dropped both when it routed completion through
`markCompleted`. No test pinned `type` on the wlog row, so the drop went unnoticed
— and `_restoreWorkoutLogs` quietly masked it on reinstall (it stamps both),
which is why it looked correct after a fresh install then drifted down.

## Fix
1. `markCompleted` stamps `type: 'workout_log'` + ISO `completed_at` (same instant
   as `completed_at_ms`, which is kept for the duration-join + epoch readers).
2. `WlogTypeBackfillMigrator` (one-shot, migrationBox-gated, wired into the
   auth_provider boot migrator sequence) heals legacy type-less rows on-device.
3. New `hive_field_name_wlog` SoT concept pins `type` + `completed_at` as REQUIRED.

## Verification
- `test/contracts/markcompleted_wlog_counted_test.dart` 3/3 — RED before the fix
  (count 0, history empty, type null), GREEN after.
- `test/safety/wlog_type_backfill_migrator_test.dart` 4/4 — pure repair + heal +
  idempotency.
- Push-safe: `_syncWorkoutLogs` selects by `wlog_` key-prefix + projects explicit
  columns (ignores `type`); cloud `workout_logs` has no `type` column.

## See also
- lib/core/services/workout_write_service.dart (`markCompleted`, `wlogKey`)
- lib/core/services/wlog_type_backfill_migrator.dart
- lib/core/services/sync/sync_workout.dart (`_restoreWorkoutLogs`, `_syncWorkoutLogs`)
- docs/sot_registry.yaml (`hive_field_name_wlog`)
