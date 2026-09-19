---
bug_id: daffac
date: 2026-05-16
batch: audit-2026-05-16 reader-side / Obs 1+3+4 (post-+27 install observation)
status: fixed
symptom: |
  Three symptoms from the same fresh-install session — same writer/reader
  drift class manifesting in different readers:
  (1) Tapping "View Workout Card" on home calendar day detail did
      nothing — silent no-op when receiptData was null. No snackbar,
      no error indicator.
  (2) Train screen expanded view rendered cumulative reps for
      non-weighted exercises (Hanging Leg Raise "7 sets · 85 reps",
      Jump Rope "5m 30s") — surfacing top-level SUM as per-set best.
  (3) Train screen day-row showed "No exercise data logged" on
      Friday May 15 even though the schedule was marked DONE — exlog
      rows either absent or unreachable from the index lookup.
concept: workout_log_id_session_scoping
sot_registry_entry: workout_receipt_rendering
writers:
  - { file: lib/core/services/workout_write_service.dart, method: logExercise, line: 186 }
  - { file: lib/core/services/sync/sync_workout.dart, method: _restoreExerciseLogs, line: 553 }
readers:
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method: View Workout Card onTap, line: 371 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method: WorkoutReceiptData.fromExerciseLogs, line: 288 }
  - { file: lib/features/train/screens/train_screen.dart, method: _buildExpandedExercises, line: 830 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exlog_${istDateStr(date)}_${uuidV5(lowercase+trim(name))}'"
sync_methods: [_syncExerciseLogs]
restore_methods: [_restoreExerciseLogs]
cloud_table: workout_log_exercises
cloud_columns: [exercise_id, workout_log_id, set_number, reps, weight_kg, logging_type, is_pr, completed_at, duration_seconds]
contract_test_path: test/contracts/load_all_exercise_prs_per_set_semantic_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 801, fn: istDateStr }
provider_invalidations: [currentPlanProvider, calendarWeekProvider, todayWorkoutProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "workoutBox user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "if (receiptData != null) { show } (no else branch)", absent: true }
proposed_fix: |
  Three independent fixes for the same class:
  (1) day_detail_sheet.dart View Workout Card tap handler — adds an
      else branch when receiptData is null, showing a snackbar:
      "No exercise data for this day yet. If you just installed, give
      cloud restore a few seconds and try again." Previously a silent
      no-op.
  (2) train_screen.dart _buildExpandedExercises — derives per-set
      MAX via two new helpers `_bestPerSetReps(log)` and
      `_bestPerSetDuration(log)` that iterate `sets[]` for the max
      per-set value. Falls back to top-level only for legitimate
      single-set legacy rows (set_number <= 1). Multi-set legacy rows
      without sets[] return 0 rather than cumulative-as-per-set.
  (3) sync_workout.dart _restoreExerciseLogs — now projects cloud
      `workout_log_id` to Hive (falls back to canonical
      `wlog_<istDate>` via WorkoutWriteService.wlogKey when the cloud
      row has no explicit value). Restored exlog rows can now be
      filtered by session-scoped receipt callers.
regression_test_planned:
  - test/contracts/load_all_exercise_prs_per_set_semantic_test.dart
---
# Body

## Symptom

Three live symptoms on +27 fresh install — same drift class, different
readers.

### 1. View Card silent no-op

Home -> calendar day detail -> "VIEW WORKOUT CARD" button. User tap
produced no visible response. Code at
`day_detail_sheet.dart:371` was:

```dart
onTap: () {
  final receiptData = WorkoutReceiptData.fromExerciseLogs(date);
  if (receiptData != null) {
    WorkoutReceiptSheet.show(context, receiptData);
  }
  // <- no else branch
}
```

When restore hadn't populated the IST date's exlog index, or when the
restored rows lacked workout_log_id and session-scoped filtering
rejected them, `receiptData` was null. The tap was a UX black hole.

### 2. Train expanded view cumulative reps

`train_screen.dart:880-881` rendered:

```dart
detail = '$sets sets · $reps reps';   // reps = log['reps_completed'] = SUM
```

For Hanging Leg Raise across 5 sets of 17, this rendered "5 sets · 85
reps" — surfacing the cumulative as per-set count. Same writer/reader
drift class as the PR cumulative bug (`bug_id: cb1ab1`) — different
reader, same defective field semantic.

### 3. Train Friday DONE with "no exercise data"

`_buildExpandedExercises` called
`WorkoutRepository.instance.getExerciseLogsForDate(day.date)`. The
schedule was marked completed on the cloud `workout_schedule_completions`
table and restored to Hive `schedule_<istDate>` with status=completed.
But `exercise_log_index_<istDate>` was empty OR the legacy fallback
date-index didn't find rows. Root cause likely related to (3) above —
without `workout_log_id` on restored rows, downstream consumers that
filter by session ID return empty.

## Root cause

`_restoreExerciseLogs` at `sync_workout.dart:553-707` did NOT project
`workout_log_id` from cloud to Hive. The writer-side contract
(`workout_write_service.dart:169`) stamps `workout_log_id` on every
exlog row — the receipt scoping is based on that field. Restored rows
lacked it, so session-scoped receipt readers either rejected them
(workout_log_id mismatch) or fell back to legacy "all exercises for
date" semantics that don't match user expectation for multi-session
days.

## Fix

See `proposed_fix` in frontmatter. Three readers updated; one writer
(restore path) updated to project workout_log_id.

## Regression test

`test/contracts/load_all_exercise_prs_per_set_semantic_test.dart`
covers the per-set MAX semantic for non-weighted exercises (also
relied on by Train expanded view fix). The View Card no-op +
workout_log_id restore projection are pinned by source-grep in the
same test file.
