---
bug_id: 7c3e91
date: 2026-11-21
batch: start-prefill-fixes
status: fixed
blast_radius: feature
tier: M
symptom: |
  Founder, web app, account Upendra, 2026-11-21 (three observations).
  (1) Home weekly calendar -> tap today -> the day sheet's START WORKOUT does
  nothing (the sheet closes, no workout starts).
  (2) In Active Workout the reps are prefilled with absurd numbers: Barbell Back
  Squat 35 reps at 101.75 kg (the LAST line reads 110.0 KG x 35 REPS), Push Up to
  Side Plank 50 reps, against plans of 8.
  (3) Cloud rows dated 25 Oct showed "60 reps at 110 kg", which the founder did not log.
concept: active_workout_prefill_and_home_start
sot_registry_entry: |
  Not a new registry concept. The writer/reader pair is the existing
  `exercise_logs_read_path` (writer `WorkoutWriteService.logExercise`, reader
  `WorkoutReadService.logsForExercise`); only the READER's name rule changed.
writers:
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method_or_widget: "_buildStartButton onTap (was Navigator.pop() only, since ef878afb 2026-03-24)", line: 493 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "_startTodayWorkout (the ONE Home start path, now shared by the Today card and the day sheet)", line: 945 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "logExercise (writes the exlog rows the prefill reads; unchanged)", line: 265 }
readers:
  - { file: lib/core/services/workout_read_service.dart, method_or_widget: "logsForExercise (fuzzy contains-match took Push Up's history for Push Up to Side Plank)", line: 452 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "_getLastPerformance (first set of the latest row) + exerciseHistoryProvider", line: 77 }
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "_ExerciseCardState._initControllers (reps prefill, now through prefillReps)", line: 294 }
hive_key_prefix: exlog_
hive_key_formula: "WorkoutWriteService.exlogKey(date, exerciseName)"
sync_methods: []
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns: [exercise_name, set_number, reps, weight_kg, workout_log_id, completed_at, deleted_at]
contract_test_path: test/contracts/prefill_exact_name_and_reps_ceiling_test.dart
ist_handling:
  - "Not applicable - no date keys or counters are written by this fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  Unchanged. The prefill reads the user-scoped workoutBox through
  HiveService.instance.workoutBox; the day sheet adds no box access.
forbidden_patterns_checked:
  - { pattern: "a START/RESUME button whose only action is Navigator.pop()", absent: true }
  - { pattern: "logsForExercise(...) in the prefill/history providers without exactNameOnly: true", absent: true }
  - { pattern: "reps prefill taken straight from lastPerf.lastReps with no ceiling", absent: true }
related_bugs: [b7f30a, e8f4a1, a8f1c2, b9e4d7, f3d2a7, a9d3f6]
recurrence: >
  Recurrence of b7f30a (2026-07-20, "Home START dead-end", same symptom class: a
  START that does not start). b7f30a swept callers of `startWorkout`
  (readiness_sheet.dart:30/:38) and wrote "exactly two callsites"; this button never
  called it, so it could not appear in that list. e8f4a1 (2026-09-15, resume guard)
  listed three START buttons, again by caller, and also missed it. The fix here
  sweeps by LABEL (test/contracts/start_button_inventory_test.dart). The prefill half
  is a sibling of a8f1c2 (reader took an aggregate instead of the first set).
proposed_fix: |
  1. day_detail_sheet.dart: take an `onStart` callback; START closes the sheet, then
     calls it; with no `onStart` the button is DISABLED, never a button that only
     closes the sheet. home_screen.dart: extract `_startTodayWorkout` (build today's
     day with `workoutDayForDate`, `beginWorkoutWithReadiness`, then the screen) and
     hand it to BOTH the Today card and the day sheet.
  2. workout_read_service.dart: `logsForExercise(name, {exactNameOnly})`; the prefill
     (`_getLastPerformance`) and the sparkline (`exerciseHistoryProvider`) pass true.
     The default stays fuzzy for any other caller.
  3. log_exercise_logic.dart `prefillReps`: a last value above twice the plan's top
     reps is not carried forward (the plan's value is used); no ceiling for a plan
     with no number or a type that does not count reps. exercise_card.dart uses it.
  4. exercise_last_try_lines.dart (found in plan-review round 1): the TRY line printed
     the raw last reps (`TRY: 112.5KG x 35`). It now uses `triedRepsText`, the same rule,
     and takes the exercise's `loggingType` (three call sites). The LAST line stays the
     real history on purpose.
regression_test_planned:
  - test/contracts/day_detail_sheet_start_behavioral_test.dart
  - test/contracts/prefill_exact_name_and_reps_ceiling_test.dart
  - test/features/train/log_exercise/prefill_reps_ceiling_card_test.dart
  - test/contracts/start_button_inventory_test.dart
mutation_results: |
  Each applied (cmp against the backup) and run, then restored byte-identical.
  M1 delete `onStart?.call()` in the sheet: 1 red (the START test).
  M2 drop `exactNameOnly: true` in `_getLastPerformance`: 2 red (borrowed history, mirror).
  M3 `2 * top` -> `20 * top` in `prefillReps`: 4 red (ceiling table + card test).
  M4 card passes `planReps: 'AMRAP'` (no ceiling): 1 red (card test).
  M5 a new lib file spelling 'START WORKOUT': 1 red (inventory).
  M6 `beginWorkoutWithReadiness` renamed in hero_cards.dart: 1 red (inventory).
  M7 TRY line back to `lastPerf.lastReps ?? fallbackReps`: 1 red (card TRY test).
  An earlier M4 attempt broke the syntax (a compile error); it was NOT counted and
  was redone with valid syntax.
impact_analysis: |
  (1) Live for every user since the first commit, on the Home calendar. The same
  button on the Today card and Train worked, so it read as intermittent.
  (2) Reads only. The prefill value is editable and the LAST line still shows the
  stored history, so no log was corrupted by the prefill itself. The exact-name rule
  also changes the weight sparkline of an exercise whose name contains another
  exercise's name. No other caller of `logsForExercise` exists (grepped).
  (3) DATA, not code. Cloud `workout_log_exercises` rows are SUMMARY rows
  (`set_number` = sets, `reps` = total reps, `weight_kg` = max): "set 4, 60 reps,
  110 kg" is four sets 110x35, 70x10, 90x10, 110x5. They were first written on
  2026-05-04 (a test session: Jump Rope 900, Handstand Hold 110, Single Leg Front
  Lever 6 sets, Planche Hollow Press 30 kg) and copied again on 2026-10-25
  03:57-04:01 UTC, which is the founder's private-window launch of that day
  (09:02 IST, diagnose b9e4d7: a restored device re-sent its history). Every
  25 Oct row in that window had an earlier identical row. All older rows also carry
  completed_at = 2026-10-25 (`latestWriteIso` = max(date, updated_at_ms) after the
  migrator re-stamped them); readers take the DAY from workout_log_id, so restore is
  unaffected. A second, smaller copy burst of 25 rows under the 25 Oct
  workout_log_id was created on 2026-11-03 06:38 UTC, AFTER b9e4d7's fix landed.
data_cleanup: |
  Founder approved in chat. 26 rows of `workout_log_exercises` soft-deleted
  (deleted_at set, nothing removed) for user d7a67a37: the 6 rows of the 2026-05-04
  test session, the 17 live 25 Oct burst rows (each had an earlier identical row),
  and 3 copies of that test session from 2026-11-03 (Jump Rope 900, Leg Curl 46@70,
  Leg Extension 46@60). Undo SQL in the session scratchpad
  (testdata_cleanup_undo.sql). `workout_log_sets` has no deleted_at column and was
  not touched. The browser keeps its own local copy: sign out and back in on the web
  app to reload from the cloud (local-only unsynced data would be lost).
  NOT deleted: 22 other 2026-11-03 06:38 rows, each an exact copy of an older live
  row under the 25 Oct workout_log_id. Left for the founder's call.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "sheet START, exact-name prefill and reps ceiling; analyze clean; new tests green; 6 mutations red" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "read-only change; the prefill reads exlog_* rows through WorkoutReadService; the web browser's local copy still holds the old rows until the user signs out and in" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "information_schema: workout_log_exercises has deleted_at; workout_log_sets has none; no schema change" }
  - { tier: 4, name: postgres_data, status: fixed_in_this_batch, evidence: "26 test-data rows soft-deleted by exact id after each was checked for an earlier identical row; undo file saved" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "client only" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron surface" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret surface" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "workout_log_id for 2026-05-04 is c08ae89d (computed with SyncService.workoutLogIdForDate and matched the cloud rows), so restore resolves those rows to their true day" }
---

# The day sheet's START did nothing, and the prefill believed a test log

## Root cause 1 - the day sheet's button was never wired

```dart
onTap: enabled ? () => Navigator.of(context).pop() : null,   // since 2026-03-24
```

It closed the sheet and called nothing. The only start path is
`beginWorkoutWithReadiness` -> `startWorkout`. The 2026-07-20 fix (b7f30a) made the
Today card use it and counted callers of `startWorkout`; the sheet's button was not
a caller, so it was not in the list and no test covered `DayDetailSheet`.

## Root cause 2 - two readers trusted too much stored history

- `logsForExercise` matched any name of six or more characters that CONTAINS the
  asked name. "Push Up to Side Plank" took the rows of "Push Up" (50 reps, 6 and 7
  May) as its own history.
- `_initControllers` prefilled the stored first-set reps unconditionally, so one
  stray log (110 kg x 35, a test entry from 4 May and its 25 Oct copy) was
  prefilled into every later session.

## Data findings (not code)

See `impact_analysis` and `data_cleanup`. The 25 Oct "session" is a re-upload of
older rows during the b9e4d7 incident, not a workout. Whether the 2026-11-03 06:38
copy burst is the same mechanism is NOT established: it happened after the b9e4d7
fix landed, and which window or build produced it needs the founder (see the
closure ledger, entry O3b).

## Fix

See `proposed_fix`. The sheet now fails visibly (disabled) when its host gives it
no start path.

## What was not checked

- The fixes are proven in widget and provider tests, not on the web app: the
  founder's device check is owed (tap a calendar day's START on today; open
  Active Workout on a squat and on Push Up to Side Plank).
- Exact-name matching is a deliberate trade-off. The writer's identity is
  `exerciseNameKey` (lower-case, trimmed; `exlogKey` hashes it), so "Bench Press" and
  "Barbell Bench Press" are different exercises to the app, and a renamed or swapped
  exercise no longer lends history to the new name. Inner double spaces also count as a
  different name, as they already do for the writer.
- The calendar day sheet enables START by the date it was opened for, while
  `_startTodayWorkout` reads today's row when tapped: a sheet left open across midnight
  would start the new day. The Today card has the same property.
- The 2-times ceiling can hide a legitimate high-rep value (a plan of 8 push-ups
  after a log of 20). The LAST line still shows the real number and the box is
  editable.
