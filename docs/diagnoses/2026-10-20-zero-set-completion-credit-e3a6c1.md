---
bug_id: e3a6c1
date: 2026-10-20
batch: log-exercise-flip (OI-361 folded in as unit U-E)
status: fixed
blast_radius: account
tier: full
symptom: |
  Founder (2026-10-20, OI-361): "zero sets logged should not be allowed".
  Tapping COMPLETE in the Active Workout FINISH dialog with no saveable set
  still ran WorkoutWriteService.markCompleted (the schedule day flips to
  completed and a wlog_<date> row is written), total_workouts_done + 1, the
  daily and weekly streaks and BadgeService.checkAll, then showed
  "Workout Complete!" / "0 SETS LOGGED". Both flag paths (per-set and LOG).
  Plan review round 7 (R7-02) found the same class on the coach chat path:
  submitWorkoutDraft skipped exercises with no sets and then called
  markCompleted unconditionally, so a chat draft with no sets flipped the day
  to completed and wrote wlog_* (no total_workouts_done bump there).
concept: workout_completion_status
sot_registry_entry: workout_completion_status
related_bugs: []
recurrence: |
  Not a recurrence: docs/diagnoses/INDEX.md has no prior zero-set completion
  record (grep for zero set / 0 sets / no sets / completion credit /
  markCompleted). b7e3a1 and f1c8e4 concern what markCompleted writes and how
  a logged row is counted, not whether completion may run with nothing saved.
  Class: a completion writer that does not check it has anything to complete.
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutNotifier.completeWorkout (OI-361 guard, first line)", line: 1969 }
  - { file: lib/features/train/screens/active_workout/finish_dialog.dart, method_or_widget: "_showFinishDialog COMPLETE onPressed (blocked; live re-check)", line: 173 }
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: "submitWorkoutDraft (guard before any write)", line: 296 }
  - { file: lib/features/ai_coach/widgets/workout_log_confirm_card.dart, method_or_widget: "WorkoutLogConfirmCard CONFIRM (canLog)", line: 47 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutData.hasSaveableSet / saveableSetIndexes / wouldSaveSet (the ONE save predicate)", line: 1380 }
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: "draftHasLoggableSet / draftExerciseSets", line: 263 }
  - { file: lib/features/train/screens/active_workout/completion_sheet.dart, method_or_widget: "completion screen (SETS LOGGED)", line: 40 }
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: "ref.listen isComplete (completion transition)", line: 294 }
hive_key_prefix: "wlog_ / exlog_ / schedule_ (written only when something saves; no new key)"
hive_key_formula: "unchanged: WorkoutWriteService.wlogKey(date), exlogKey(date, name)"
sync_methods: [WorkoutWriteService.markCompleted, WorkoutWriteService.logExercise, SyncService.syncProgressNow]
restore_methods: [_restoreWorkoutLogs]
cloud_table: "workout_logs / scheduled_workouts (unchanged; nothing reaches them when the guard refuses)"
cloud_columns: []
contract_test_path: test/contracts/log_exercise_flip_behavioral_test.dart
ist_handling:
  - { file: lib/features/train/providers/train_provider.dart, line: 2107, fn: resolveSessionDate }
provider_invalidations: [currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a: session-only predicate over the in-memory ActiveWorkoutData / WorkoutDraft; both notifiers rebuild on authUserIdTokenProvider"
forbidden_patterns_checked:
  - { pattern: "markCompleted reachable from completeWorkout with hasSaveableSet false (U-E1 behavioural)", absent: true }
  - { pattern: "markCompleted reachable from submitWorkoutDraft with draftHasLoggableSet false (U-E5 behavioural)", absent: true }
  - { pattern: "completeWorkout() in integration_test/ with zero sets", absent: true }
proposed_fix: |
  One predicate per path, shared by the UI and the writer.
  Active Workout: ActiveWorkoutData.hasSaveableSet = any exercise with a
  non-empty saveableSetIndexes (the exact set completeWorkout iterates:
  checked, not a warm-up, values captured, the template count extended by
  checked keys beyond it). completeWorkout returns on its first line when
  !isSaved && !hasSaveableSet (before the timer cancel, so the session is left
  as it was; review mode keeps its path). The FINISH dialog, both flag
  modes, disables COMPLETE on the same predicate and says "No working sets
  logged (warm-ups don't count). Log one to complete, or cancel the workout.";
  it scrolls while blocked (R7-01) and keeps the re-opened / typed lines under
  the block (R7-04). The COMPLETE closure re-reads the live state before any
  side effect (R7-05).
  Coach chat: draftExerciseSets (the loop's own set builder, extracted; it
  keeps only sets carrying weight, reps or a duration above 0, and cardio only
  with a duration or a distance, so an all-blank set is never a 0x0 set; B-pass
  finding 1) and draftHasLoggableSet; submitWorkoutDraft returns before any write and keeps
  the draft; WorkoutLogConfirmCard disables CONFIRM and says "No sets to log.
  Tell the coach your sets, or discard." The other two coach completion paths
  (tool_dispatcher._maybeCompleteScheduledDay, the tap card) only run after a
  coach logSet, so they always have a set (verified by reading, R7-02).
regression_test_planned:
  - test/contracts/log_exercise_flip_behavioral_test.dart
  - test/contracts/zero_set_completion_behavioral_test.dart
  - test/features/train/log_exercise/log_exercise_finish_dialog_test.dart
  - test/features/train/log_exercise/log_exercise_logic_test.dart
impact_analysis: |
  Every user who taps FINISH with nothing saveable now sees COMPLETE disabled
  and the reason; CONTINUE, the barrier and ✕ CANCEL (screen.dart) stay, so
  no one is trapped. A real OFF-mode checker always has captured values before
  a check (exercise_card.dart check handler + init pre-seed), so no OFF user
  with real sets is blocked. Chat users with a no-set draft can add sets in
  chat or DISCARD. Review mode is unchanged (FINISH is already disabled there).
  Pre-launch: testing accounts only (CLAUDE.md §1).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze: no error or warning; the behavioural, pure and widget tests listed below green" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "U-E1: a real awaited completeWorkout through setUpHiveForTests writes no wlog_/exlog_ key and leaves total_workouts_done unchanged for zero sets, warm-up-only and checked-without-values; one saveable set writes exlog_ and +1. U-E5: submitWorkoutDraft on a no-set draft writes no wlog_/exlog_" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "pre-launch testing accounts only; the fix only refuses a write" }
  - { tier: 12, name: "Client to server contract", status: verified, evidence: "nothing reaches workout_logs / scheduled_workouts when the guard refuses: the cloud push is downstream of markCompleted, which never runs" }
mutation_proven:
  mutated: |
    U-E1a guard removed; U-E1b guard moved below `_timer?.cancel()`; U-E1c guard
    without `!state.isSaved`; U-E1d `hasSaveableSet` constant false; U-E3
    `hasSaveableSet` scans only exercise 0; U-D1 `wouldSaveSet` without the
    warm-up clause; U-D1b `saveableSetIndexes` without the maxSetLog extension;
    U-E2 block line gated on logMode; U-E2 `scrollable: logMode`; U-E2b closure
    re-check dropped; U-E2c return right after the block line; U-D4a lists shown
    when blocked; U-D4b COMPLETE enabled; U-E4 `draftHasLoggableSet` => true;
    U-E5a submit guard removed; U-E5b card CONFIRM ignores canLog;
    after the B-pass, BF1a blank lift sets written and BF1b blank cardio written.
  result: |
    Every one RED: U-E1a 4 tests, U-E1b 1 (the periodicTimerCount check),
    U-E1c 1 (review mode), U-E1d 5, U-E3 1, U-D1 2, U-D1b 2, U-E2 (logMode) 2,
    U-E2 (scrollable) 1, U-E2b 1, U-E2c 1, U-D4a 2, U-D4b 3, U-E4 2, U-E5a 1,
    U-E5b 1. U-E5b was first GREEN (the submit's own guard hid the enabled
    CONFIRM); the test now also asserts the card's onTap is null, and re-run it
    reddened.
  confirmed_applied: "scratch driver (flipmut.py) refuses unless each old text occurs exactly once; files restored after each run"
---

## Summary

A workout with nothing to save can no longer be completed, on either Active
Workout flag path or from the coach chat card. The UI and the writer read the
same predicate, so they cannot drift.

## Root cause

`completeWorkout` saved per set with three `continue`s (unchecked, warm-up, no
values) and then completed the day unconditionally, so "nothing saved" was
indistinguishable from "something saved" for `markCompleted`, the counters and
the streaks. `submitWorkoutDraft` had the same shape: `if (sets.isEmpty)
continue;` per exercise, then `markCompleted`.

## Fix

See `proposed_fix`. The three `continue`s became `wouldSaveSet` /
`saveableSetIndexes` (the flip batch's U-D1 predicate), and `hasSaveableSet`
reads them; `completeWorkout` iterates the same helper, which a behavioural
parity test (U-D1b) runs against the real save.

## Tests

- U-E1 (`log_exercise_flip_behavioral_test.dart`): the real awaited
  `completeWorkout` for zero / warm-up-only / no-values sessions, the
  one-saveable control, review mode, and the timer check
  (`fa.periodicTimerCount` 1 before and after a refused call; 0 after an
  allowed one).
- U-E2/U-E2b/U-E2c/U-D4 (`log_exercise_finish_dialog_test.dart`): the dialog
  through the real screen, both modes.
- U-E3 (`log_exercise_logic_test.dart`): the `hasSaveableSet` truth table.
- U-E4/U-E5 (`zero_set_completion_behavioral_test.dart`): the chat predicate
  and the real `submitWorkoutDraft` with a real `WidgetRef`.
