---
bug_id: 270ea3
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Workout restore wrote Hive keys using cloud UUIDs instead of deterministic WriteService keys, causing exercise logs to be unreadable by receipt and calendar readers.
concept: hive_field_name_exlog
sot_registry_entry: hive_field_name_exlog
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreExerciseLogs, line: 1 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: getExerciseLogsForDate, line: 1 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exlog_${istDateStr(date)}_${exerciseName.hashCode.toUnsigned(32).toRadixString(16)}'"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreExerciseLogs]
cloud_table: workout_log_exercises
cloud_columns: [exercise_id, set_number, reps, weight_kg, volume_kg]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: _restoreExerciseLogs keys Hive by deterministic exlog_ prefix formula mirroring WorkoutWriteService.logExercise; _restoreWorkoutLogs similarly keyed.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 270ea33993642f8dee274e91ebe52dac9ff7c2d1
Subject: fix(workouts): consolidate writers + restore writes canonical field names (Test #11 D1+D2)
Files changed: lib/core/services/sync_service.dart, lib/core/services/write_result.dart, lib/features/train/repositories/workout_repository.dart, test/sync/restore_field_canonical_test.dart
