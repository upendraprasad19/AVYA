---
bug_id: 39ead9
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  `train_provider._getLastPerformance` (line 43) and
  `exerciseHistoryProvider` (line 131) iterated `hive.workoutBox.values`
  inline and filtered `if (log['type'] != 'exercise_log')` — depended
  on the writer stamping that string field. OI-02 closure earlier
  today shipped WorkoutReadService with `exerciseLogsForIstDate` /
  `bestPerSetReps` / `bestPerSetWeight` but train_provider was not
  migrated. Drift class same as OI-36.
concept: train_provider_workout_read_service_delegation
sot_registry_entry: workout_read_service
writers:
  - { file: lib/core/services/workout_read_service.dart, method: logsForExercise (new cross-date scan), line: 184 }
  - { file: lib/features/train/providers/train_provider.dart, method: _getLastPerformance delegates, line: 43 }
  - { file: lib/features/train/providers/train_provider.dart, method: exerciseHistoryProvider delegates, line: 105 }
readers:
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-39 group (3 cases), line: 138 }
hive_key_prefix: "exlog_"
hive_key_formula: "WorkoutWriteService.exlogKey"
sync_methods: [_syncExerciseLogs]
restore_methods: [_restoreExerciseLogs]
cloud_table: workout_log_exercises
cloud_columns: [exercise_id, date, weight_kg, reps, set_number]
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling:
  - { file: lib/core/services/workout_read_service.dart, line: 152, fn: exerciseLogsForIstDate }
provider_invalidations: [lastPerformanceProvider, exerciseHistoryProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "workoutBox is user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "_getLastPerformance iterates hive.workoutBox.values inline", absent: true }
  - { pattern: "exerciseHistoryProvider iterates hive.workoutBox.values inline", absent: true }
proposed_fix: |
  Added `WorkoutReadService.logsForExercise(name)` — cross-date `exlog_*`
  scan with case-insensitive exact + ≥6-char fuzzy contains matching.
  Returns chronologically sorted logs. Both train_provider readers now
  delegate; inline iteration removed. The per-set extraction logic
  (a8f1c2 Bug-1 fix) preserved verbatim in `_getLastPerformance`.

  Lens L1 (writer/reader drift) + L26 (architecture-gap mirror to
  OI-02 closure).
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug 39ead9 — train_provider scans workoutBox directly

closes-oi: OI-39

WorkoutReadService gained `logsForExercise(name)`. train_provider's 2 inline scans now delegate. A third callsite (if added) would inherit the same semantic.
