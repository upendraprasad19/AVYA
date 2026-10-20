---
branch: log-exercise-batch2
date: 2026-10-20
blast_radius: account
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: pending  # B-pass ran 2026-10-20 (docs/reviews/800af61c829a-review.md): 1 P0, 3 P2, all fixed; verdict awaits founder triage
---

# Plan-review record: Active Workout one-LOG-per-exercise, batch 2 (OI-356)

Plan: [`docs/plans/log-exercise-batch2.md`](../plans/log-exercise-batch2.md). Execution mode: inline (plan §2).

## Round 1 (context-blind reviewer, revision 1): not converged, 4 P1, 13 P2, 0 P0
Every finding was checked against the code by the coordinator before acting (L17). Confirmed true by the reviewer:
the SnackBar queue/close claims (`scaffold.dart:341,348`), the in-tree toast design, `SetInputRow.onChanged` fires on
user input only (`set_input_row.dart:209`), the `_onFieldChanged` return order, UNDO leaving `setInputValues` is safe
(every reader filters on checked keys), flag-OFF identity, no test pins the FINISH literal.
P1: (1) the mirror breaks `log_exercise_card_test.dart:68-98` (types set 1, expects sets 2-3 blank), not listed;
(2) the toast identity check `data.exercises[i]` has no bounds check → RangeError in `build` after a removal;
(3) UNDO during the un-awaited `completeWorkout()` (`finish_dialog.dart:161-163`; `isSaved` only at
`train_provider.dart:2134`) silently drops the last exercise from the save; (4) §3 "no diagnose doc owed"
contradicts OI-356's "full diagnose template".
P2: stale toast resurfacing after swap-back/remove-re-add/`-`; toast vs floating SnackBars overlap; row-level
`onChanged` cannot tell which field changed (re-mirror into a cleared field; clear propagation unstated); shrink and
`+` mirror rules untested; tests 7/9 fixtures cannot catch the identity mutation; screen wiring presence-only where
pure seams are cheap, `(bool allLogged)` invalid record type; UNDO re-focus without scroll; no UNDO input guard;
Timer should clear by generation; §4 facts (`addSet` not a `checkedSets` writer, missing readers, `:368`) and SoT
ranges; §7 limits inaccurate (State recreation, coach snapshot is new); duplicate exercise names already crash the
screen (shared GlobalKey) and nothing tracks it; existing pins (`swap_undo_snackbar_dismisses_test.dart:282-284`,
`active_workout_set_logging_behavioral_test.dart:296-325`) not listed.
Response: revision 2 (plan §0 maps each finding): `visibleUndoRecord` with bounds + all-checked gate,
`_completing` notifier flag + FINISH clears the toast, full-template diagnose doc `c7d2a9`, top-of-list overlay
placement, 400 ms UNDO guard and 44 px target, per-field `_lastSourceText`, `+`/shrink rules, three-exercise
fixtures, pure `undoRecordFor`/`allExercisesLogged`, `_focusExercise`, generation-checked Timer, §4/SoT corrections,
coach snapshot cleared on UNDO, OI-358 minted (duplicate-name GlobalKey crash), pins listed in §6.

## Round 2 (context-blind reviewer, revision 2): not converged, 1 P1, 13 P2, 0 P0
Confirmed by the reviewer: every §4/§5 citation; the SnackBar claims; nothing awaits before `logExercise :2014` /
`markCompleted :2035` in `completeWorkout`; Riverpod 3.3 recreates notifiers on rebuild and every session starts in
`startWorkout`; the new `Stack` leaves OFF layout, `_scrollToExercise` and the GlobalKeys unchanged
(`stack.dart:598`, `viewport.dart:1531-1533`); all listed source pins hold; FINISH variant unpinned; the Stopwatch
gate cannot flash back; OI-358 reserved.
P1: test 11's premise was false (no test in the repo drives `completeWorkout`; this file opens Hive only for
`swapExercise`, `:147-150`), and its pure fallback would leave `_completing` unprotected (rule 21).
P2: mirror source re-baseline when a warm-up moves the source; `_lastSourceText` must be set after the restore loop;
`+` follower rule wrong for returning users; tests 12-18 need the new-user fixture (harness default 60 × 8) or
13 fails and 17 cannot redden; FINISH cleared the toast before the dialog (CONTINUE loses UNDO; needs `setState`);
"the session cannot resume" was false when `completeWorkout` throws (dead LOG); the overlay wins hit tests and can
cover content; SoT readers and the unfiltered `_initControllers` restore; `set_add_append_test.dart:16-55` pin;
`unawaited_futures` on `clearState()`; toast file/fonts; the U1a `-`-on-DONE loose end; toast text stale after a
warm-up re-flag, and the screen-level proof for `c7d2a9`.
Response: revision 3 (plan §0.1): test 11 is an explicit never-flushed `fakeAsync` test on the real `completeWorkout`
and the FIRST implementation step (spike gate), fallback removed; the guard is on `unlogSets` only and the toast is
cleared in the COMPLETE path via a new `onComplete` callback; every P2 folded into §5.1, §5.2, §6, §8.

## Spike (test 11 feasibility, run 2026-10-20 during round 3, before any product code)
A throwaway test (deleted after the run) seeded exercise A fully checked with captured values, called the REAL
`completeWorkout()` un-awaited inside `fakeAsync((_) { … })` after `setUpHiveForTests()` outside it, and read the
state: `isSaved == false`, sets still checked; a second test in the same file ran afterwards; no hang, 2/2 passed
(`flutter test`, `TZ=Asia/Kolkata`). Test 11 is therefore written as specified; no fallback.

## Round 3 (context-blind reviewer, revision 3): not converged, 2 P1, 8 P2, 0 P0
Confirmed by the reviewer: every §4 citation; `completeWorkout` has one caller (`finish_dialog.dart:163`);
`isSaved`/`isComplete` written only at `train_provider.dart:1816,2134`; test 11 is feasible (the abandoned lock is
keyed per exercise and date and blocks nothing else in the file) and mutations (a)/(b) redden it; one notifier per
session (not autoDispose); all source pins hold; the mirror cannot write logged sets, warm-ups or typed fields.
P1: (1) clearing the coach snapshot on UNDO makes `ai_snapshot_builder.dart:209` and `:1274-1275` read "no live
session" (A7 clears it only when a session ends; OFF rewrites it on uncheck); (2) nothing tested the `_completing`
reset, so a broken reset would silently disable UNDO for every later workout.
P2: test 13's mutation could not redden; test 20 could not prove pass-through; `_mirrored` initial state and
"follower" ambiguous; no API for the seed index; first keystroke after a source move unstated; a dead UNDO during
a save; UNDO over a header chip; nits (`finish_dialog.dart:162`, `screen.dart:190`, `unawaited` reason, `undo`
reserved glossary term).
Response: revision 4 (plan §0.2): UNDO leaves the coach snapshot untouched; one reset point (`startWorkout`) proven by
test 11b; `isCompleting` suppresses the record during a save (D5); every P2 folded in.

## Round 4 (context-blind reviewer, revision 4): CONVERGED, 0 P0, 0 P1, 9 P2
Verified against the code: every session starts in `startWorkout` (`state = ActiveWorkoutData(` only in `build`
`:1415`, `startWorkout :1448`, `cancelWorkout :2165`; two callers, `readiness_sheet.dart:58,66`; no restore after a
restart), so `_completing` cannot go stale; `isSaved`/`isComplete` writers `:1497,1816,2134`; test 11b feasible
(everything `startWorkout` reads is synchronous; its `Timer.periodic` never fires in the fake zone); every listed
mutation reddens its test (tests 12-18b traced on the harness, test 20's `IgnorePointer` mutation included); UNDO
leaving the coach snapshot misleads no reader; all source pins hold; `seedForAddedSet` can delegate.
P2 (folded into plan §0.3, revision 5): the parity gate fails on out-of-range names (re-baseline incl.
`workout_templates`); test 19 needs the new-user fixture to catch an OFF leak; five more `checkedSets` readers;
test-20 host hit-testing and long-name layout; `logToastText` bounds + shared `formatKg`; FINISH in review mode;
record suppression during a save moved into pure `undoRecordFor`; two wording fixes; 18b fixture and seed-index null.
Verdict: converged after four rounds (review #2..#4 each ran on the post-previous-round plan, §4.12.1).

## B-pass (`/code-review`, fresh read-only Sonnet reviewer, staged diff `8812992b4995`): 1 P0, 3 P2, all fixed (founder triage pending)
P0: the list host swapped between a bare `ListView` and a `Stack`, rebuilding the list on every toast show and
clear (scroll reset, typed values lost in disposed cards). Round 2 had confirmed the plan's always-present Stack;
the built code did not match it and no test mounted the screen. P2: the first keystroke after a warm-up move only
re-baselined; the one-set `+` follower branch was untested; OI-358 cited pre-batch lines. Fixes in plan §0.4,
each mutation-proven (ledger rows BP1-BP4). The reviewer's 4 behavioural mutants were also run: all red.

