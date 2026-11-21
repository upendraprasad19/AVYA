---
bug_id: 7ad0c8
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `submitWorkoutDraft` (the chat-confirmation handler for AI-coach-detected workouts) wrote `exlog_<ts>_<hash>` and `wlog_<ts>` rows directly to Hive with the *legacy* field shape (`sets_completed`, no `sets[]`, no `set_number`, no IST-stable key, no per-set rows). Bypassed `WorkoutWriteService`. Result — receipts and AI snapshot readers (`_getThisWeekWorkouts` / `_getPersonalRecords` / `_getMealsToday`) silently dropped every chat-confirmed workout because they filter on the new field shape introduced by Test #8. AI coach gave advice based on a workout history that excluded every "I did 3x10 squats" message the user confirmed.
concept: chat_workout_draft_write_service
sot_registry_entry: workout_write_service
writers:
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: submitWorkoutDraft, line: 188 }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: WorkoutReceiptData.fromExerciseLogs, line: 1 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getThisWeekWorkouts, line: 1 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getPersonalRecords, line: 1 }
hive_key_prefix: "exlog_*, wlog_*"
hive_key_formula: "exlog_<istDate>_<exerciseNameHash> + wlog_<istDate> (deterministic, IST-stable)"
sync_methods: ["SyncService.syncWorkoutData()", "SyncService.pushSnapshot()"]
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns: [workout_log_id, exercise_id, set_number, reps, weight_kg, completed_at]
contract_test_path: test/contracts/conversational_log_handler_uses_write_service_test.dart
ist_handling: ["istDateStr(now) for date key + cloud date column"]
provider_invalidations: [calendarWeekProvider, streakProvider, todayWorkoutProvider]
telemetry_op_types:
  success: [workout_write_log_exercise, workout_write_mark_completed]
  failure: [workout_write_log_exercise_failed]
cross_account_guard: yes
forbidden_patterns_checked: ["submitWorkoutDraft_direct_workoutBox_put_exlog_or_wlog", "submitWorkoutDraft_uses_legacy_sets_completed_field"]
proposed_fix: Route every exercise in the draft through `WorkoutWriteService.logExercise(date, exerciseName, sets, source: WriteSource.aiCoach, ref)` and the schedule-status flip through `WorkoutWriteService.markCompleted(date, workoutName: 'Chat Workout', durationSec, ref)`. Convert `DraftSet` → `ExerciseSet` (weightKg / reps / durationSec) per set; cardio collapsed to a single synthetic set carrying total durationSec. WriteService handles deterministic key + IST date + sets[] + set_number + PR rescan + 3-tier cloud sync + provider invalidation.
regression_test_planned:
  - test/contracts/conversational_log_handler_uses_write_service_test.dart
  - Updated test/sync/sync_gap_test.dart (recognizes WriteService delegation)
  - Updated test/contracts/hive_key_contracts_test.dart (drops stale entry[type]=="workout" assertion in favor of markCompleted delegation)
---
# Audit C-8: chat-confirmed workouts bypassed WorkoutWriteService

## Bug

`conversational_log_handler.submitWorkoutDraft` is called by
`WorkoutLogConfirmCard` when the user confirms an AI-detected workout
(e.g. "did 3x10 squats then 4x8 bench"). Pre-fix it wrote:

```dart
final logId = 'wlog_${now.millisecondsSinceEpoch}';  // non-IST, non-deterministic key
await workoutBox.put(logId, {
  'sets_completed': totalSets,  // ← legacy field; Test #8 replaced this with set_number
  // no `sets[]` array
  // no IST date stamping
  // ...
});

final exId = 'exlog_${now.millisecondsSinceEpoch}_${exercise.name.hashCode}';
await workoutBox.put(exId, {
  'sets_completed': exercise.sets.length,  // ← legacy field
  // first set fields copied to top-level (weight_kg, reps_completed)
  // no `sets[]` per-set array
  // ...
});
```

Field shape mismatch is the silent killer: every downstream reader
introduced by Test #8 filters or aggregates on `set_number` / `sets[]`.
Chat-confirmed workouts had neither, so they were skipped:

- `WorkoutReceiptData.fromExerciseLogs` — receipt shows "0 sets".
- `_getThisWeekWorkouts` — AI coach context's workout list excludes
  chat-confirmed sessions.
- `_getPersonalRecords` — PR detection silently skips them.
- 3-tier cloud sync (`workout_logs` + `workout_log_exercises` +
  `workout_log_sets`) — per-set rows never written.

## Cause

`WorkoutWriteService` was introduced in APK Test #6 as the sole
writer for workout Hive mutations, with the explicit contract
documented in CLAUDE.md §15 ("Hive field-name contract"). 4+ other
call sites were migrated at the time; `submitWorkoutDraft` was missed
because the audit-discovery sweep didn't include
`features/ai_coach/services/`. The function predates the WriteService
and its legacy field shape survived intact.

## Fix

Refactored `submitWorkoutDraft`:

1. Iterate `draft.exercises`. For each: convert `DraftSet` →
   `ExerciseSet` (weightKg / reps / durationSec). Cardio collapses
   to a single synthetic set carrying `(durationMins ?? 0) * 60` as
   durationSec.
2. Call `WorkoutWriteService.instance.logExercise(date: now,
   exerciseName: exercise.name, sets: sets, source: WriteSource.aiCoach,
   ref: ref)`. WriteService handles:
   - Deterministic key (`exlog_<istDate>_<exerciseName>`)
   - IST date stamping
   - 60s per-set dedup window
   - `sets[]` per-set array + `set_number` aggregate
   - Library-aware `logging_type` resolution
   - PR rescan for the exercise
   - Provider invalidation via the `onInvalidate` hook
   - 3-tier cloud sync (workout_logs + workout_log_exercises +
     workout_log_sets)
3. Call `WorkoutWriteService.instance.markCompleted(date: now,
   workoutName: 'Chat Workout', durationSec: totalDurationSec,
   ref: ref)` once after the loop. Synthesises `wlog_<istDate>` + flips
   today's schedule to `status='completed'`.
4. Kept the immediate Home-surface invalidations (calendarWeek /
   streak / todayWorkout) so the chat → confirmation → home transition
   shows fresh state even when the optional onInvalidate hook isn't
   wired. Added a defensive `pushSnapshot()` for the same reason.

## Regression tests

- New: `test/contracts/conversational_log_handler_uses_write_service_test.dart`
  - imports the right modules
  - calls `logExercise` + `markCompleted`
  - does NOT write `exlog_*`/`wlog_*` keys directly
  - does NOT carry the legacy `'sets_completed'` field
- Updated `test/sync/sync_gap_test.dart` to recognize the WriteService
  delegation (sync fan-out happens inside WriteService now).
- Updated `test/contracts/hive_key_contracts_test.dart` to drop the
  stale `entry['type'] == 'workout'` assertion in favor of a
  `markCompleted` delegation assertion.

Suite: 1544 pass / 0 fail / 2 skip.

## Related

- Test #6 (introduced WorkoutWriteService)
- Test #8 (locked the field shape via contract tests for receipts)
- CLAUDE.md §15 (Hive field-name contract + Sync fan-out contract)
- 7ad0c9 (C-12 expanded scope — sibling fix for the 5 nutrition
  WriteService bypasses)
