# Plan — start-prefill-fixes (founder web observations, 2026-11-21)

Branch `start-prefill-fixes`, worktree `.claude/worktrees/start-prefill-fixes`. Tier M, measured blast radius
`account` (`scripts/blast_radius_from_diff.dart`). Execution mode: inline (one coordinator), decided at start.
Diagnose `docs/diagnoses/2026-11-21-day-sheet-start-and-prefill-reps-7c3e91.md`; ledger
`docs/audit/start-prefill-fixes.closure.yaml`.

## Observations and decisions

| # | Observation | Decision |
|---|---|---|
| O1 | Home calendar day sheet: START WORKOUT does nothing | Wire it to the Home start path; disable it when the host gives no path; add a by-label inventory so no START button hides again |
| O2 | Prefill shows 35 reps (squat) and 50 reps (Push Up to Side Plank) against plans of 8 | (a) stored test data soft-deleted in the cloud (done, founder approved); (b) prefill and sparkline read an exact exercise name only; (c) a last value above 2x the plan's top reps is not prefilled |
| O3 | 25 Oct rows looked wrong | Data, not code: copies of older rows from the b9e4d7 incident; no code change; a 3 Nov repeat burst is blocked on the founder |

## The change (4 source files, 1 new pure function, 2 CLAUDE.md rows)

1. `lib/features/home/widgets/day_detail_sheet.dart`: new `VoidCallback? onStart`; `show(..., onStart)`; the START
   button's `onTap` pops the sheet then calls `onStart`; `enabled: isToday && onStart != null`.
2. `lib/features/home/screens/home_screen.dart`: `_startTodayWorkout(context, ref)` = the body of the Today card's old
   inline `onStart` (day from `workoutDayForDate(DateTime.now())`, `beginWorkoutWithReadiness`, then
   `context.go('/train/active-workout')`); the Today card and `DayDetailSheet.show(onStart:)` both call it.
3. `lib/core/services/workout_read_service.dart`: `logsForExercise(name, {bool exactNameOnly = false})`; with it only
   `exerciseNameKey(logName) == exerciseNameKey(name)` matches; the default stays fuzzy.
4. `lib/features/train/providers/train_provider.dart`: `_getLastPerformance` and `exerciseHistoryProvider` pass
   `exactNameOnly: true` (the only two callers of `logsForExercise`).
5. `lib/features/train/services/log_exercise_logic.dart`: pure `prefillReps` + `planTopReps`; ceiling only for
   `weight_reps`, `bodyweight_reps`, `weighted_bodyweight`; no ceiling when the plan's reps are not a number.
6. `lib/features/train/screens/active_workout/exercise_card.dart` `_initControllers`: reps prefill goes through
   `prefillReps` (fallback = the card's own `_parseRepsMidpoint`).

7. (Round 1, P3 verified by the coordinator) `exercise_last_try_lines.dart`: the TRY line printed the raw last reps;
   it now uses `triedRepsText` (same rule as `prefillReps`) and takes `loggingType` (3 call sites: two in
   `exercise_card.dart`, one in `exercise_media_viewer.dart`).
8. (Round 1, P3) The inventory test also scans any literal containing `START WORKOUT` (the copy file's
   `trainStartWorkoutCta`, unused today, pinned unused).

Round 1 disposition: P2 (exact-name trade-off) accepted and documented, because the writer's identity is
`exerciseNameKey`; P3 TRY line fixed; P3 inventory reach fixed; P3 midnight accepted and documented.

## Claims a reviewer must verify against the code

- C1 The day sheet's START was `Navigator.pop()` only, unchanged since `ef878afb`.
- C2 `logsForExercise` has exactly two callers (`_getLastPerformance`, `exerciseHistoryProvider`) in `lib/`.
- C3 `exercise_card.dart` is a `part of 'screen.dart'`, and `screen.dart` imports `log_exercise_logic.dart`, so
  `prefillReps` resolves there.
- C4 The sheet's `context` is gone after `pop()`, which is why the host's `context` and `ref` are used (a host callback).
- C5 Ordering: `pop()` then `onStart` is safe: `beginWorkoutWithReadiness` shows its guard/readiness sheet from the
  HOST context, which stays mounted.
- C6 The prefill ceiling cannot change a plan without a numeric reps string, or a timed/cardio/distance row.
- C7 No other file spells a START/RESUME button label that is not in `test/contracts/start_button_inventory_test.dart`.
- C8 No existing test pins the fuzzy behavior of the two providers (`last_performance_per_set_contract_test.dart` must
  stay green).

## Tests (all written; mutation results in the diagnose-doc)

`day_detail_sheet_start_behavioral_test`, `prefill_exact_name_and_reps_ceiling_test`,
`test/features/train/log_exercise/prefill_reps_ceiling_card_test`, `start_button_inventory_test`.

## Out of scope on purpose (terminal states in the ledger)

- The 3 Nov copy burst mechanism (O3b), the 22 remaining copies (O3c), the browser's local copy (O3d), the web device
  check (V1): all `blocked_on_user`.

## Gates before each review round

`flutter analyze --no-fatal-infos` (whole project: 0 warnings, 0 errors), the four new tests plus
`last_performance_per_set_contract_test.dart` green, Gate 40 and the diagnose validator pass.
