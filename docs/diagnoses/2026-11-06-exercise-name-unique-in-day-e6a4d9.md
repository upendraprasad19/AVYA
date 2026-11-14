---
bug_id: e6a4d9
date: 2026-11-06
batch: oi358-unique-exercise-names
status: fixed
blast_radius: account
tier: m_fix
symptom: |
  Active Workout raises `Multiple widgets used the same GlobalKey` when two cards carry one exercise name. Reproduced
  2026-11-06 in a test build on the real screen: Add with a name already in the session, Swap into a name held by another
  slot, and a session started from a stored day holding a name twice. Control with two names: clean. Release-build
  behaviour is NOT measured. The user's expected behaviour: picking an exercise already in the workout should say it is
  already there and let them pick another.
concept: exercise_name_unique_in_day
sot_registry_entry: exercise_name_unique_in_day
related_bugs: [b3c8d2]
recurrence: |
  NOT a recurrence. `Multiple widgets used the same GlobalKey` and `_exerciseKeys` appear in no diagnose-doc, not in
  common-pitfalls.md and not in the debugging skill. `a1d7c3` is about two chat cards; `c7d2a9` only cites OI-358.
  RELATED: `b3c8d2` (2026-05-12), templates with 14-15 rows and 4-5 distinct names on a real account. A different root
  cause (cloud `template_exercises` tail rows after a shrink), fixed by the tail vacuum still live at
  sync_workout.dart:1954. It is the evidence that duplicate names have reached a real account through RESTORE, a path no
  picker controls, which is why the guard at `startWorkout` exists.
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "addExercise (Train Add); refuses a session name, returns SessionExerciseChange", line: 1780 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "swapExercise (Train Swap, create-and-swap, UNDO); refuses another slot's name, same slot allowed", line: 1707 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "startWorkout (the last line for stored days): keeps the first of each name, logs a count", line: 1504 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "swapExerciseInDay (coach swapExercise tool, CoachSwapSheet, injury swaps): throws exercise_already_in_workout, nothing written", line: 506 }
  - { file: lib/features/ai_coach/services/injury_swap_planner.dart, method_or_widget: "plan / _findSubstitute: per-date takenNames so two exercises never get one substitute", line: 71 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "createTemplate (coach createCustomTemplate): pre-pass before the first box.put throws duplicate_exercise", line: 1797 }
  - { file: lib/core/services/template_service.dart, method_or_widget: "assignTemplateToDate (3 routes): keeps the first per name on the RAW rows, nameless rows survive", line: 147 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: "_showExerciseSearch onSelect: writer guard on a list held in State", line: 334 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: "initState: keeps the first per name on load, so a duplicate restored into a template is not saved back", line: 54 }
readers:
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: "_exerciseKeys.putIfAbsent(exercise.name, ...) then key: _exerciseKeys[exercise.name]; name-keyed on purpose so a key follows a reorder", line: 623 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "exlogKey hashes exerciseName.toLowerCase().trim(), so two same-name cards would save to one log row", line: 1695 }
  - { file: lib/features/train/screens/active_workout/exercise_picker_sheet.dart, method_or_widget: "takenNames: a taken row is shown greyed and cannot be tapped", line: 268 }
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: "_isTaken: both tap targets dead, the tag replaces SELECT", line: 115 }
  - { file: lib/features/ai_coach/widgets/swap_exercise_coach_sheet.dart, method_or_widget: "_substitutesFor / _tile: taken options labelled, no onTap", line: 126 }
hive_key_prefix: "schedule_<date>.exercises[] and templates in workoutBox (read and guarded); ActiveWorkoutData.exercises (session state)"
hive_key_formula: "exerciseNameKey(name) = name.toLowerCase().trim(), the same normalisation exlogKey hashes"
sync_methods:
  - "none changed: sync_workout.dart is not edited"
restore_methods:
  - "restore hydration (sync_workout.dart:2720-2735, :2849) deliberately NOT edited; a restored duplicate is made safe by the startWorkout guard"
cloud_table: none
cloud_columns: []
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "swap_sheets.dart: todayWorkoutProvider, currentPlanProvider, calendarWeekProvider now run only when the swap applied (and after an applied UNDO); a refusal changes nothing, so nothing is invalidated"
telemetry_op_types:
  success: []
  failure:
    - active_workout_duplicate_name_dropped
cross_account_guard: "unchanged: every guard reads or writes through the existing repositories and services (wrapUserScopedBox)."
forbidden_patterns_checked:
  - { pattern: "an exercise name in the active_workout_duplicate_name_dropped payload (message carries dropped=<count> only)", absent: true }
  - { pattern: "a new .getAll() or getCustomExercises( line in a picker file (check_exercise_seams.dart counts them)", absent: true }
  - { pattern: "a column-0 } inside _showSwapSheet or _openCreateAndAutoSwap (source regexes read them non-greedily)", absent: true }
  - { pattern: "plan_generator.dart or sync_workout.dart in the diff", absent: true }
proposed_fix: |
  THE RULE: within one workout day no two entries share exerciseNameKey(name) = name.toLowerCase().trim(). Declared
  exception: nameless rows are never dropped from a stored row. Source of truth lib/core/utils/exercise_name_identity.dart.

  The card key stays name-based (the comment at screen.dart:75-77 says why, a key must follow a reorder, and exlogKey needs
  unique names anyway), so the fix closes every door instead of changing the key. Seven doors: Train Add, Train Swap,
  template builder, coach swapExercise tool, coach Swap quick action (CoachSwapSheet), coach injury swap
  (InjurySwapPlanner), coach createCustomTemplate. Two carriers hold rows that were already duplicated:
  assignTemplateToDate (template_service.dart, 3 routes: keep-first) and cloud restore (covered by the startWorkout guard).
  There is no add-exercise coach tool. The coach's logSet and log card merge on exlogKey, so they cannot create a duplicate
  card. A template card offers only EDIT, SCHEDULE and delete; it cannot start a session directly.

  addExercise and swapExercise return `enum SessionExerciseChange { applied, nameTaken, invalidSlot }`: a bool would have
  shown a false "already in this workout" on a bad index. Every call site branches on it. A taken row is GREYED, not hidden
  (founder default, not objected to), findable by search, tag ALREADY IN WORKOUT (builder ALREADY IN TEMPLATE). Keep-first
  in the template guard: refusing would leave a saved template impossible to schedule.

  SEPARATE DEFECT 1, UNDO INDEX (found in plan review, same closure): the swap UNDO captured exerciseIndex. A removal on
  another card during the 5 s window shifts later indexes without hiding the snackbar (a move hides it, screen.dart:146-149),
  so UNDO overwrote a neighbour and wiped its checked sets. It now finds the slot holding newName at tap time; no such slot
  does nothing; nameTaken shows the message.

  SEPARATE DEFECT 2, BUILDER DISPLAY (found in this batch): ExerciseCard in the template builder read only `name` and
  `prescribed_*` / `default_*`, but createTemplate rows carry `exercise_name`, `sets`, `reps`, so a coach-made template
  opened in EDIT as Unknown, 3 x 10. It now reads exerciseRowName and tolerant `_rowSets` / `_rowReps`. A String `sets` is a
  real shape (diagnose a2f9e1), so the parse is tolerant, never `as int?`.

  STATED, NOT CHANGED: stored rows and saved templates are not healed in bulk; `startWorkout`, `assignTemplateToDate` and the
  builder's load make them safe to read, and a Save from the builder writes the distinct rows. A create-custom refusal keeps the new custom row (a library item the user asked for), only the swap is off.
contract_test_path: test/contracts/exercise_name_unique_in_day_behavioral_test.dart
regression_test_planned: |
  52 tests in 4 new files, each widget file's fonts-first test included (all pass): test/contracts/exercise_name_unique_in_day_behavioral_test.dart (24: the rule, each
  writer through real Hive, createTemplate zero rows on a day-2 duplicate, keep-first order, nameless rows, planner per-date
  reset, exlogKey parity), test/features/train/exercise_name_unique_screen_test.dart (14: real screen via pumpScreen, cases
  A, B, C raise no exception and render one card per name; both pickers greyed; create-and-swap refusal; UNDO after re-add
  and after a removal), test/features/train/template_builder_unique_names_test.dart (9: a new harness; greyed row, writer
  guard, rows of both shapes, String sets, a template already holding a name twice opens distinct and saves distinct), test/ai_coach/coach_unique_exercise_names_test.dart (5: CoachSwapSheet, dead
  tiles, coach error wording). Each widget file starts with `renderFontsFirst` (the path_provider pitfall).
  test/contracts/active_workout_superset_persist_behavioral_test.dart and test/train/swap_logging_type_test.dart: source
  regexes REPOINTED to the new return type, never loosened. The second was not in the plan's list and went red in the
  full suite: the old literal should have been grepped across test/ first (CLAUDE.md 4.9).

  MUTATION PROOF (rule 21): 49 mutants on the final code, one at a time, each confirmed applied, a compile error not
  counted, the tree compared byte for byte after the run. 49 killed, reddening 1 to 9 tests each. Covered: exerciseNameKey no trim, no lowercase; exerciseRowName field
  order; firstPerExerciseName keep-last and dropping nameless rows; both swap writers' other-slot exclusion; each writer's
  guard off; startWorkout guard off, event carrying a name, event on a clean day; injury planner per-date reset; createTemplate
  check moved into the write loop, skip rule dropped; dedupe after _normalizeExercises; each call site's branch on the
  result; invalidSlot read as nameTaken; UNDO by captured index; each picker's dead row; the builder's display fallbacks; the builder's load (keeps duplicates, reads only `name`, drops
  nameless rows).

  THREE RESULTS WERE NOT PROOFS THE FIRST TIME, all caught by reading the table. M18 (custom swap row not marked taken)
  SURVIVED: the test's finder matched the sheet HEADER, which prints the outgoing name in the same text, while the custom
  row sat below the fold of a lazy list and was never built. The test now searches to bring the row in, asserts both matches,
  the taken tag, no SELECT, and taps the row itself; M18 is red. M24 (builder writer guard gone) was a COMPILE ERROR, not a
  kill: the mutant dropped a null check. Rewritten to compile; red. M49 (builder load drops nameless rows) SURVIVED: the fixture
  held one nameless row, so dropping all but the first changed nothing. It now holds two; red.

  A RACE IN THIS BATCH'S OWN TESTS, found by the warn-only contract sweep on the first push (377 files, one failure): "finds
  its slot after a removal" went red at its first assertion, the swap not yet applied. `tapWithRealIo` waits a fixed 100 ms
  for real disk I/O, and under the sweep's load the save took longer; the save then finished after the test ended (the
  disposed-container StateError in that log is the same event). It passed alone every time, and in the full-suite run.
  Not a product defect. Fixed by waiting on what the work does (`pumpUntilRealIoDone`: the sheet closed, or the row written
  and SAVE live again), not by a longer delay. PROOF: with the 100 ms floor REMOVED the fixed files stay green (23 of 23)
  and the old screen test goes red (5). Under load (8 CPU burners on 4 cores) 3 of 3 runs that were left to finish passed 23 of
  23, the slowest in 351 s; two runs my own 280 s limit killed had failed nothing. All 49 mutants re-run after this edit:
  49 killed. The other users of `tapWithRealIo` are unchanged; none failed in the sweep.

  KNOWN UNPINNED, stated: `_showSwapSheet`'s nameTaken message is unreachable through the UI today, because a taken row
  cannot be tapped; it remains the writer's answer if a row list goes stale. "No provider invalidation on a refusal" is not
  asserted; an extra invalidate only re-reads.
impact_analysis: |
  GENERATOR: 580 of 12,960 combinations sampled (shuffled, time-boxed; the full matrix did not finish in 9 minutes), 9,892
  workout days, 0 within-day duplicates, 0 failures. A sample, not the whole matrix; the repeat-phase pin path was read, not
  measured. The hotel planner uses the same generator. So a stored duplicate is expected only from restore or a template.
  Value semantics (4.1.5.3): no stored value changes meaning; nothing in supabase/functions/ reads a day's names for identity.
  No migration, no Edge Function, no prompt or tool-description change. CLAUDE.md 4.6 does not apply (plan section 5).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "seven doors and two carriers; 52 new tests; 49 of 49 mutants killed. Whole-project analyze clean. Full suite run once locally: 13,208 passed, 14 skipped, 3 failed, all three this batch's (two source pins, one skill-index row), fixed and re-run targeted; CI is the full-suite gate after those fixes." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "real-Hive behavioral tests: swapExerciseInDay leaves the stored row byte-identical on refusal; createTemplate writes zero rows on a duplicate; assignTemplateToDate lands one row per name." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no column, migration or Edge Function touched." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "stored rows are not healed and no audit query was needed: every account is a testing account (CLAUDE.md section 1), and the read guards make a stored duplicate safe." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the tools' zod schemas are unchanged; the client refusal is the guard and the coach shows the mapped message (tool_dispatcher.dart:1893). Traced in the coach tests." }
---

# Two cards with one exercise name crashed Active Workout (OI-358)

## What the founder expected
Picking Barbell Bench Press on a day that already holds it should say it is already in the plan and let the user pick
another. Instead the screen keyed two cards by one name and Flutter raised a GlobalKey error.

## Cause (writers and readers by file:line)
See `writers:` and `readers:`. One sentence: the screen and the log key both treat the name as the identity within a day,
but no writer enforced that.

## What was proven and what was not
- Proven: the crash reproduced in a test build on the real screen for add, swap and a stored duplicate; every door closed;
  46 mutants killed.
- Not measured: release-build behaviour of the old crash (asserts do not run there, so the outcome is unknown, not "no
  crash"). OI-348 row A16 is the founder's device walk.
- Not changed: stored rows and saved templates, which stay as they are and are safe to read.

## B-pass
`docs/reviews/e141930e4739-review.md`: 3 findings, 2 fixed, 1 false alarm. Registry ranges that carried older staleness
were re-anchored on their declarations; the builder's load now keeps the first per name.

## Process
Plan `docs/plans/oi358-unique-exercise-names.md`, record `docs/plan-reviews/oi358-unique-exercise-names.md`. The first
bug-history search ran on an index absent from a fresh worktree with errors silenced, so the plan first said "no related
bug"; the index was built and `b3c8d2` found.
