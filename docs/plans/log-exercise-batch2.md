# Plan: Active Workout one-LOG-per-exercise, batch 2 (OI-356): UNDO, mirror, last-exercise emphasis (revision 5, converged at round 4)

Branch `log-exercise-batch2`, worktree `.claude/worktrees/log-exercise-batch2`, base `main` `f34e32d`.
Predecessor: U1a (PR #128, `451b028`), plan `docs/plans/active-workout-log-exercise.md`.
Everything below stays behind `enable_log_exercise_button` (default OFF). This batch is the flip's HARD
precondition (`docs/ship_dark_pending_review.yaml`); it does NOT flip the flag.

## 0. Response to round 1 (4 P1, 13 P2; every item verified against the code before acting, L17)
- P1-1 (existing card test breaks): §6 "Existing tests", repoint spelled out; U1a mutation re-run on it.
- P1-2 (RangeError in the identity check): pure `visibleUndoRecord` with a bounds check (§5.1), unit-tested.
- P1-3 (UNDO during an un-awaited `completeWorkout`): `_completing` notifier flag + FINISH clears the toast (§5.1).
- P1-4 (OI-356 asks for the full diagnose template): a full-template diagnose doc is written (§3, §8).
- P2-1 resurfacing → visibility requires every record set still checked. P2-2 overlap with floating SnackBars and
  P2-8 mis-tap → toast at the TOP of the list area + 400 ms UNDO guard + 44 px target. P2-3 per-field change
  detection + clear rule. P2-4 shrink and `+` rules + tests. P2-5 test fixtures. P2-6 pure seams for record,
  visibility, FINISH; `bool` return. P2-7 `_focusExercise`. P2-9 Timer clears by generation. P2-10 §4 facts and
  SoT ranges/readers. P2-11 limits reworded; the coach snapshot is cleared on UNDO. P2-12 uniqueness assumption
  stated, OI-358 minted (duplicate-name GlobalKey crash). P2-13 pins listed in §6.

## 0.1 Response to round 2 (1 P1, 13 P2; verified, L17)
- P1-1 (test 11 had a false premise: no test drives `completeWorkout`; the pure fallback protected nothing): test 11
  is now an explicit `fakeAsync` test on the REAL `completeWorkout`, never flushed, and it is the FIRST
  implementation step (spike gate, §6); the fallback is removed; mutations listed.
- Design change while answering P2-5/P2-6: the completion guard is on `unlogSets` ONLY (LOG during a save is the
  existing U1a/OFF behaviour and stays), and the toast is cleared in the COMPLETE path, not before the dialog
  (CONTINUE keeps UNDO). A `completeWorkout` that throws therefore leaves LOG working; only UNDO stays off until the
  next session, and the toast was already cleared.
- P2-1/2/3 mirror source re-baseline, init after the restore loop, `+` follows only through a follower chain;
  P2-4 new-user fixtures + per-test mutation; P2-7 toast body `IgnorePointer`, only UNDO hit-tests, overlap stated
  (D4); P2-8 SoT readers + the unfiltered `_initControllers` restore stated; P2-9 `set_add_append_test` pin; P2-10
  `unawaited(...)`; P2-11 toast file + fonts; P2-12 `-` decision; P2-13 toast text computed at render.

## 0.2 Response to round 3 (2 P1, 8 P2; verified, L17)
- P1-1 (clearing the coach snapshot on UNDO tells `ai_snapshot_builder.dart:209` and `:1274-1275` the session is
  over): UNDO no longer touches `ActiveWorkoutPersistence`; the snapshot keeps describing the LOG until the next
  LOG writes it (stated; both readers named in §4). No new writer of `active_session`.
- P1-2 (nothing tests the `_completing` reset): ONE reset point, the top of `startWorkout` (every session starts
  there, `train_provider.dart:1448`; `cancelWorkout` needs none because the next session still starts in
  `startWorkout`); test 11b proves it and its mutation.
- P2: test 13 sequence (mirror first, then edit, then re-edit); test 20 hosts the toast over a `GestureDetector`;
  `_mirrored` starts EMPTY and "follower" is defined; new pure `seedIndexForAddedSet`; first keystroke after a
  source move mirrors nothing (pinned in 18b); `isCompleting` getter: no record is created while a save runs (D5);
  UNDO over a header chip added to D4; nits (`finish_dialog.dart:162` pop, `screen.dart:190`, the `unawaited`
  reason dropped, `undo` glossary note).

## 0.3 Round 4 P2s (converged; these are normative and override any conflicting text below)
1. The SoT parity gate FAILS when a method's name falls outside its cited `line_range`
   (`check_sot_registry_parity.dart:167-185`): re-baseline every `active_workout_set_logging` range AND every range
   the gate flags in the touched files (expected: `workout_templates` / `TemplatesNotifier.build` in
   `train_provider.dart`); the gate runs in the loop.
2. Test 19 (OFF) runs on the NEW-USER fixture with a `timed` exercise (blank duration) and a weight exercise;
   mutation: wire `onChanged` in OFF and drop `!_logMode` from `_onFieldChanged` → red.
3. Additional `checkedSets` readers for §4/§8 (all `ref.watch`, no change): `header.dart:56`, `progressPercent`
   (`screen.dart:254,269`), `_effectiveFocusedIndex`/`isActive` (`screen.dart:146,358`), `finish_dialog.dart:30`,
   `completion_sheet.dart:40`.
4. Test 20 host: `Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque))` under the toast; the
   toast text is `Expanded` with `maxLines: 1` + ellipsis; test 20 adds a long-name case at phone width (no overflow).
5. `logToastText(record, data)` returns `''` when the record's index is out of range (bounds-checked, unit-tested); a
   shared pure `formatKg(double)` is extracted and used by both `liftedSubline` and `logToastText`
   (`log_exercise_logic_test.dart:158-160` unchanged).
6. D3: review mode (`isSaved`) keeps FINISH (`✓ ALREADY SAVED`) `primary` and disabled, as today; outline applies
   only in LOG mode while not every exercise is logged and the session is not saved.
7. `undoRecordFor` takes `required bool completing` and returns null when true (test 6 case); the screen passes
   `notifier.isCompleting`, so record suppression during a save is behaviourally tested.
8. Wording: `_lastAdvanceAt` is stamped when the LOG made the exercise done (always so for a `setsToLog` LOG). Test
   4's "re-flagged warm-up" case is a pure-function case (the UI blocks long-press on a completed set).
9. Test 18b uses the new-user fixture. `seedIndexForAddedSet` returns null when every set is a warm-up;
   `seedForAddedSet` keeps its `existing.last` fallback (`log_exercise_logic_test.dart:189-192`).

## 0.4 B-pass on the built diff (review `8812992b4995`, 2026-10-20; normative like 0.3)

1. P0: the shipped `_withLogUndoToast` returned the bare `ListView` with no toast and a `Stack` with one, so
   the list was rebuilt on every show and clear (scroll reset, off-screen cards and their typed values
   disposed). §5.1's always-present Stack is now enforced by `LogUndoToastHost` (one Stack in LOG mode, the
   bare list with the flag OFF), with a host widget test (scroll offset + row State identity).
2. P2: the mirror source now re-baselines on the rebuild after a warm-up toggle (`_rebaselineIfSourceMoved`
   in `didUpdateWidget`), not on the next keystroke, so a one-digit entry in the new source mirrors (card
   test 18c). The keystroke-time re-baseline stays as a fallback.
3. P2: card test 18d covers `+` on a one-set exercise (the `from == source` follower branch).
4. P2: OI-358's line citations re-baselined to the built tree.

## 1. Scope (OI-356 as re-cut by the founder 2026-10-19)
1. **UNDO toast after LOG**: `{Exercise} logged · {n} sets · {kg} KG` with UNDO (copy approved 2026-10-18, U1a
   plan §9). UNDO reverts exactly the sets that LOG checked.
2. **Mirror**: set 1's typed value copies into blank, untouched fields of the same exercise, for weight, duration
   and distance (B-pass finding 5: duration/distance are blank for every user, weight for a new user). No fading.
3. **Last-exercise emphasis**: once every exercise is logged, `All exercises logged.` above a gold FINISH WORKOUT.

Dropped by the founder: "Save changes"/edit mode, a separate un-log button. In OI-357: auto-scroll, faded prefill,
per-set history, hints.

## 2. Execution mode (§4.12.7), tier, review
Inline, one worktree, decided now. Tier: diff touches `lib/core/copy/wardroom_copy.dart` (`account`) and
`lib/features/train/**` → M pipeline, reviewed as U1a was: ×2 plan review, full gate loop before any review with a
diff (§4.12.8), `/code-review` B-pass before merge, record `docs/plan-reviews/log-exercise-batch2.md`. Closure
ledger `docs/audit/log-exercise-batch2.closure.yaml` (≥4 units).

## 3. Bug-history lookup (§4.1.5)
`docs/diagnoses/INDEX.md`: `s1n4c0` (snackbar shown from under a still-mounted modal never dismissed), `b4e7f1`
(swap-undo snackbar had no dismissal hook; fix = messenger on the screen State, dismissed by a completion
`ref.listen` and `dispose()`), `e8f95e` (never seed a controller from an unrelated field). No prior bug on
mirroring or undoing set checks. OI-356 assigns the UNDO toast to the snackbar recurrence class with the FULL
diagnose template, so this batch writes `docs/diagnoses/2026-10-20-log-undo-toast-staleness-c7d2a9.md` (full
template, `related_bugs: [b4e7f1, s1n4c0]`, `recurrence:` stating the class is prevented by design, mutation
evidence), validated by `scripts/validate_diagnose_doc.dart`, cited by `closes-diagnose: c7d2a9`.

## 4. State, writers and readers (file:line on `f34e32d`)
- `checkedSets` (`train_provider.dart:1222`): writers `toggleSet :1500`, `logSets :1516`, `startWorkout :1418`
  (reset at `:1452`), `swapExercise :1557` (wipes the swapped index), `removeExercise :1616` (re-indexes),
  `removeLastSet :1674`, `cancelWorkout :2162`. (`addSet :1664` writes `exercises` only.) **NEW writer
  `unlogSets`.** Readers: `isSetChecked :1349`, `isExerciseDone :1357`, `completedSets :1327`,
  `liveVolumeKg :1380`, `completeWorkout` per-exercise loop (`:1977`), `workout_receipt_card.dart:211-220`,
  `exercise_card.dart` (`setsToLog`, `_buildLogRow :613`), `screen.dart` (`isDone` per card, `:351`),
  `LogExerciseController.log` (`log_exercise_logic.dart:276`).
- `setInputValues`: writer `recordSetValues :1534` via `_captureSetValues` (`exercise_card.dart:422`). UNDO does
  NOT touch it; the save/volume readers filter on checked keys (`:1977`, receipt `:220`, `liveVolumeKg
  :1382-1384`); `_initControllers` restores it unfiltered (`:148-164`), which after UNDO shows the logged values
  again (benign).
- Controller text (card-local): `_initControllers :99`, `didUpdateWidget :192`, `_seedAppendedSets :315`, typing.
  **NEW writer: the mirror** (card-local, never the provider).
- `ActiveWorkoutPersistence` (coach mid-workout snapshot, workoutBox key `active_session`,
  `services/active_workout_persistence.dart:6-7`): written by `_persistLoggedState :398` on LOG; read by
  `ai_snapshot_builder.dart:209` (`active_workout`) and `:1274-1275` (presence = a live session today, the coach's
  day-swap lookahead). **UNDO does NOT touch it** (round 3 P1-1): clearing would tell both readers the session is
  over; the snapshot keeps the LOG's count until the next LOG rewrites it (stated). Flag OFF rewrites it on an
  uncheck (`exercise_card.dart:983-987`); matching that on UNDO is not needed for correctness of either reader.

## 5. Design

### 5.1 UNDO (in-tree toast, not a SnackBar)
**Why not a SnackBar:** `ScaffoldMessenger` queues SnackBars (`scaffold.dart:348` `addLast`) and a controller's
`close()` asserts it is the current one (`:341`), so LOG, LOG within 5 s would delay the second toast and a queued
one cannot be closed; a toast outliving its context is the `b4e7f1`/`s1n4c0` class. The toast is a widget inside
the active-workout screen's own tree, so it cannot outlive it.
- **Placement**: the list area becomes `Expanded(child: Stack([ListView, Positioned(top: 8, left: 16, right: 16,
  child: LogUndoToast)]))`. Top of the list, not the bottom: the screen's floating SnackBars (warm-up hint
  `screen.dart:465-484`, swap-undo `swap_sheets.dart:196-224`) sit at the bottom, and the next card's LOG button is
  in the lower part of the expanded card. No layout shift (overlay).
- **Pure units (`services/log_exercise_logic.dart`):**
  - `LogUndoRecord { exerciseIndex, exerciseName, setIndexes, shownAt, generation }`.
  - `undoRecordFor({before, after, exerciseIndex, shownAt, generation})` → record or null: `setIndexes` = the keys
    of that exercise checked in `after` and not in `before` (exactly what this LOG added), null when empty.
  - `visibleUndoRecord(record, now, data)` → record or null: null when `record == null`, `now - shownAt >=
    kLogUndoWindow` (5 s), `exerciseIndex` out of `0..exercises.length-1`, the name differs, `data.isSaved`, or ANY
    of `setIndexes` is no longer checked (covers swap-back, remove/re-add, `-`; P2-1).
  - `shouldIgnoreUndo(now, shownAt)` → `now - shownAt < kLogInputGuard` (400 ms; P2-8).
  - `logToastText(record, data)`: `{Exercise} logged` + ` · {n} sets` (`1 set`; `n` = WORKING sets in the record, warm-ups
    excluded as in `completedSets`; segment omitted when 0) + ` · {kg} KG` (only `weight_reps` /
    `weighted_bodyweight`, from the STORED `setInputValues` of those working sets after capture,
    `sum(weight × reps)` as `liveVolumeKg`, `liftedSubline` rounding; omitted when 0).
  - `allExercisesLogged(data)` → `bool` (§5.3).
- **Screen State**: `LogUndoRecord? _logUndo; int _logUndoGeneration = 0; Timer? _logUndoTimer;` (`dart:async`).
  `_onLogExercise` (`screen.dart:91`), on `LogOutcomeKind.logged`, reads `before` (captured at the top, before the
  controller call) and `after`, builds the record, `setState`s it, and restarts the Timer; the Timer callback
  clears the record only if its generation still matches (P2-9). The existing body shape stays (pins in §6).
- **Render**: `final undo = logMode ? visibleUndoRecord(_logUndo, _logClock.elapsed, data) : null;` → the toast
  child only when non-null (OFF: never built). The text is computed AT RENDER by `logToastText(undo, data)` (current
  warm-up flags and stored values), so the record carries no text. The toast body is wrapped in `IgnorePointer`;
  only the UNDO target hit-tests, so drags and taps under the rest of the toast reach the list. **D4 (stated,
  founder-visible):** for up to 5 s the toast can visually cover the top of the list (the next card's header, or a
  superset partner revealed at `alignment: 0.1`, `screen.dart:190`), and the UNDO target at its right edge can lie
  over a header chip (`⇄ SWAP` / `✓ DONE`, `exercise_card.dart:839-855`), so a tap aimed at the chip between 0.4 s
  and 5 s undoes the LOG instead (recoverable: LOG again). Structure: the decorated background and text sit inside
  `IgnorePointer`; UNDO is a sibling outside it.
- **UNDO tap**: ignored while `shouldIgnoreUndo`; else take the record, clear it (`setState`), cancel the Timer,
  call `unlogSets(record.exerciseIndex, record.setIndexes, exerciseName: record.exerciseName)`; on `true`,
  `_focusExercise(record.exerciseIndex)` (focus AND scroll, `screen.dart:170-178`; P2-7).
  `_lastAdvanceAt` in the controller is NOT reset: it was stamped at the LOG, and UNDO is accepted only ≥400 ms
  after that, so a re-LOG is never inside the window (stated, P2-8).
- **Completion (P1-3, revised after round 2)**: `_showFinishDialog` (`finish_dialog.dart:5`, one call site
  `screen.dart:536`) gains an optional `VoidCallback? onComplete`, invoked in the COMPLETE handler right before
  `Navigator.of(ctx).pop()` (`finish_dialog.dart:162`); the screen passes one that `setState`s `_logUndo = null` and
  cancels the Timer. CONTINUE leaves the toast (the modal barrier blocks UNDO while the dialog is open). The
  notifier gets `bool _completing = false`, set `true` in `completeWorkout` right after the `isSaved` early return
  (`train_provider.dart:1815-1818`, i.e. before any `await`) and reset at the top of `startWorkout` (the ONLY
  session start, `:1448`; round 3 P1-2), exposed read-only as `bool get isCompleting`;
  ONLY `unlogSets` checks it (defence in depth for the un-awaited `completeWorkout()`, `finish_dialog.dart:163`;
  `isSaved` is set only at `:2134`). `logSets` is unchanged (LOG during a save is existing behaviour in both modes).
  `_onLogExercise` creates no record while `isCompleting` (no toast whose UNDO would do nothing).
  **D5 (stated):** if `completeWorkout` throws before `:2134`, LOG keeps working but shows no UNDO toast until the
  next session. The existing completion `ref.listen` (`screen.dart:204-208`) also clears the record/Timer, AFTER
  `_dismissSwapUndoSnackBar()`, with no `setState` and no `});` inside (pin in §6).
- **Unmount**: `dispose()` cancels the Timer (added after the existing `_dismissSwapUndoSnackBar()` line).
- **`unlogSets(int exerciseIndex, Set<int> setIndexes, {required String exerciseName}) → bool`** beside `logSets`:
  returns false and leaves `state` identical when `_completing || isSaved || isComplete`, the index is out of range,
  `exercises[exerciseIndex].name != exerciseName`, or nothing in range is checked; otherwise removes only the
  present, in-range keys in ONE state change; never touches `setInputValues` or `warmUpSets`. Never a toggle loop.
- **`-` and removals (U1a plan §5 left "`-` on a DONE card … revisited with UNDO")**: `-` on a logged card removes
  a set the record holds, so the toast hides (not every record set is checked) and that LOG can no longer be
  undone; `-` stays live on a DONE card as in U1a. Removing an exercise at a LOWER index shifts the record's index,
  so its UNDO is dropped even though the exercise still exists: conservative and intended (stated).
- **Uniqueness assumption (P2-12)**: the name identity check assumes unique names in a session; duplicates already
  crash the screen (shared GlobalKey, `screen.dart:366,409` before this batch, `:438,481` after it), tracked as OI-358.
- Style: Wardroom card (`AppColors.card`, sharp radius, accent border 0.3 alpha), parchment body text, `UNDO` as a
  ≥44 px tap target in Campaign Gold `AppTypography.monoXs`.

### 5.2 Mirror (card-local, flag-ON only)
- **Source**: the first NON-warm-up set (`mirrorSourceIndex(isWarmUp)`, null when all are warm-ups).
- **Fields per logging type** (`mirrorFieldsFor`, matching `SetInputRow._buildInputs`, `set_input_row.dart:140-185`;
  reps excluded, always prefilled): `weight_reps`, `weighted_bodyweight`, default → {weight}; `timed` → {duration};
  `cardio` → {duration, distance}; `distance` → {distance, weight}; `bodyweight_reps` → {}.
- **Per-field change detection (P2-3)**: `onChanged` is one callback per ROW (`set_input_row.dart:209`), so the card
  keeps `_lastSourceText[field]`; on a source-row change only fields whose source text differs from that record
  mirror, then the record updates. Editing set 1's reps never re-mirrors its weight.
- **Targets** (`mirrorTargets`): sets `t > source`, not a warm-up, not logged (`isSetChecked` false), whose field
  text is blank OR equals `_mirrored[field][t]` (the value the mirror last wrote). The targets FOLLOW the source,
  including a clear (source cleared → followers blank). A field the user edited to something else is never written
  again; a field the user clears is blank and follows again on the next source change (stated, tested).
- **Trigger**: `_onFieldChanged` (`exercise_card.dart:340`), wired ONLY in LOG mode (`:977`), fired by
  `TextField.onChanged` (user input only). The mirror runs after the `isSaved` return and before the
  "is this set logged" return; it writes controller text only, never the provider (the LOG capture records it).
- **State read**: the mirror reads warm-up and checked state from the fresh `ref.read(activeWorkoutProvider)` that
  `_onFieldChanged` already takes (`exercise_card.dart:342`), never from the build-time `widget.data` (OI-355 class).
- **Source moves (round 2 P2-1)**: the card keeps `_lastSourceIndex`; when `mirrorSourceIndex` differs from it (a
  warm-up toggled on set 1), `_lastSourceText` is re-baselined from the new source's CURRENT texts and NOTHING
  mirrors on that keystroke (the field just typed compares equal too); the next change of the new source mirrors
  (round 3 P2-5).
- **Follower** (round 3 P2-3): set `k`'s field is a follower when its text is blank OR equals `_mirrored[field][k]`.
- **Bookkeeping**: `_mirrored` starts EMPTY in `_initControllers`; `_lastSourceText` and `_lastSourceIndex` are set
  there AFTER the restore loop (`exercise_card.dart:148-164`) from the controllers' final text (round 2 P2-2). A
  returning user's prefilled values are therefore never followers. Shrink
  (`didUpdateWidget` shrink branch) trims `_mirrored` entries `>= n`. `+` (`_seedAppendedSets`): a seeded field is
  registered as a follower ONLY if the set it was copied from is the source or is itself a follower of that field
  (new pure `int? seedIndexForAddedSet(List<bool> isWarmUp, int count)`, which `seedForAddedSet` delegates to
  without changing its return type, so `log_exercise_logic_test.dart:164-193` stays as is), so a returning user's
  prefilled sets and their copies stay independent (round 2 P2-3). New `didUpdateWidget` lines stay OUT of the swap
  branch (pin `test/train/set_add_append_test.dart:16-55`, `[^}]*`). A card State recreated (re-entry, scrolled out
  of the ListView cache) starts fresh; unlogged texts are not captured, so they reset to prefill (§7).
- OFF: `_onFieldChanged` is never wired, so OFF is untouched by construction.

### 5.3 Last-exercise emphasis
`allExercisesLogged(data)` = `!data.isSaved && exercises.isNotEmpty && every isExerciseDone`. Screen
(`screen.dart:527-537`), reusing the build's single `logMode` variable: `final allLogged = logMode &&
allExercisesLogged(data);` → in LOG mode FINISH is `WardButtonVariant.outline` until `allLogged`, then the default
gold `primary` with a centred `All exercises logged.` line (`AppTypography.bodySm`, accent) above it. OFF: built
exactly as today. **Founder-visible decision D3:** outline-until-done is how the emphasis "turns gold"; FINISH stays
tappable in both states.

### 5.4 Copy (`WardroomCopy`)
`activeLogToastLoggedTemplate = '{exercise} logged'`, `activeLogToastSetsTemplate = '{n} sets'`,
`activeLogToastOneSet = '1 set'`, `activeLogToastKgTemplate = '{kg} KG'`, `activeLogToastSeparator = ' · '`,
`activeLogUndo = 'UNDO'`, `activeAllExercisesLogged = 'All exercises logged.'`. Checked against
`docs/naming_conventions.md` and appended there; `undo` is a reserved term (`undo_<logKey>` Hive keys,
`naming_conventions.md:88,277`), so the glossary row states the log-undo record is session-only, never a Hive key.

## 6. Tests (rule 21; each new protection mutated once, results in the closure ledger and diagnose doc)
**Spike gate (first implementation step):** test 11 is written and run FIRST. If it cannot run as specified, stop,
record why in the plan-review record, and re-plan the completion guard before writing any other code.
Pure (`log_exercise_logic_test.dart`): 1. `mirrorFieldsFor` table. 2. `mirrorSourceIndex`. 3. `mirrorTargets`
(blank in; last-mirrored in; edited out; logged out; warm-up out; `t <= source` out). 4. `logToastText` (plural,
singular, warm-ups only, a set re-flagged warm-up after LOG, no-load types, kg `142.5`/`1200`).
5. `allExercisesLogged` (all done; one undone; saved; empty). 6. `undoRecordFor` (only newly added keys; nothing
added → null). 7. `visibleUndoRecord` (fresh → shown; `>= 5 s` → null; index out of range after a removal → null,
no throw; name differs → null; one set unchecked → null; saved → null). 8. `shouldIgnoreUndo` (399 ms ignored,
400 ms accepted).
Notifier (`active_workout_set_logging_behavioral_test.dart`, REAL notifier): 9. `unlogSets` with THREE uniquely
named exercises: removes only the given keys; after `removeExercise(0)` the exercise now at the record's index has
the SAME set indexes checked and they STAY checked (identity check), state identical; saved/complete no-op; out of
range ignored; nothing to remove → identical; `setInputValues`/`warmUpSets` untouched. 10. LOG → UNDO round trip
(`completedSets`, `isExerciseDone`, `liveVolumeKg` restored). 10b. `seedIndexForAddedSet` (last non-warm-up;
all warm-up → null; empty → null) in the pure file.
11. **Completion race (spike gate):** `setUpHiveForTests()` OUTSIDE `fakeAsync`; seed exercise A (all sets checked,
values captured) and B (unchecked), unique names; inside `fakeAsync((_) { … })`: `n.completeWorkout()` NOT awaited,
then `unlogSets(0, {0,1,2}, exerciseName: 'A')` returns false and `state` is `identical` to before; never flush.
The abandoned `WorkoutWriteService` lock (`_acquireLock`, `workout_write_service.dart:126`) is never released: no
other test in this file calls `logExercise`. Mutations that must redden it: (a) delete `_completing = true;`;
(b) drop the `_completing` check from `unlogSets`. (`logSets` is deliberately unguarded.) `isCompleting` is true
inside the zone after the call.
11b. **Reset:** same setup; inside `fakeAsync`: `completeWorkout()` un-awaited, then `startWorkout(day)`, then
`logSets(0, {0,1,2})` and `unlogSets(0, {0,1,2}, exerciseName: …)` returns true; `isCompleting` false (mutation:
remove the reset from `startWorkout`).
Card (`log_exercise_card_test.dart`, U1a harness, `tapWithRealIo` for persisting taps, NEW-USER fixture
`lastPerf: const LastPerformanceData()` for 12-18 unless stated; harness default is 60 kg × 8,
`card_harness.dart:86-87`): 12. `60` in set 1 fills sets 2-3, LOG unblocked (mutation: mirror call removed).
13. set 1 → `60` (sets 2-3 become 60), set 3 → `70`, set 1 → `65`: set 2 = 65, set 3 = 70 (mutations: blank-only
targets, and no text check at all, each redden).
14. editing set 1's REPS does not re-fill a weight cleared in set 2 (mutation: drop per-field change detection).
15. clearing set 1 clears the followers (mutation: skip empty source). 16. `timed` and `cardio` mirror;
`bodyweight_reps` nothing (mutation: `mirrorFieldsFor` returns {weight} always). 17. new user: type set 1, LOG,
`+`, edit set 1: the LOGGED sets keep their text (mutation: drop the logged-set exclusion; reddens because the
logged sets were followers). 18. `-`, `+`, edit set 1 → a re-added set follows only through a follower chain;
returning user (default fixture): `+` then edit set 1 → set 4 does NOT follow (mutation: register every seed).
18b. source moves: set 1 = 60 mirrored, set 2 edited to 70, set 1 flagged warm-up, edit set 2's reps → set 3
unchanged, then the next edit of set 2's weight mirrors (mutation: no re-baseline). 19. OFF: typing in set 1 changes no other row.
Toast (`test/features/train/log_exercise/log_undo_toast_test.dart`, new, widget in
`lib/features/train/widgets/log_undo_toast.dart`): 20. `renderFontsFirst` first; text + UNDO render; the toast is
hosted in a `Stack` over a full-size `GestureDetector`: a tap on the toast BODY reaches the detector, a tap on UNDO
calls back once and does NOT reach it (mutation: remove `IgnorePointer`).
Screen wiring (source assertions, PRESENCE ONLY; behaviour is 5-11): 21. `_onLogExercise` builds the record via
`undoRecordFor`; render goes through `visibleUndoRecord` and `logToastText`; UNDO checks `shouldIgnoreUndo` and calls
`unlogSets` and `_focusExercise` (and never `ActiveWorkoutPersistence`); no record while `isCompleting`; `_showFinishDialog` is passed `onComplete`
and calls it before `completeWorkout()`; the completion listener and `dispose()` cancel the Timer; FINISH reads
`allExercisesLogged`. Why no screen harness: the screen is a private `part of` State over many providers; the
mechanism is proven on the pure units and the notifier (5-11), and "cannot outlive the screen" holds by
construction (the toast is a child of the screen's own tree) — recorded in diagnose `c7d2a9`.
**Existing tests (grep run, REPOINT never loosen):**
- `test/features/train/log_exercise/log_exercise_card_test.dart:68-98` (round 1 P1-1): type `50` in set 1 → mirror
  fills 2-3 → `LOG 3 SETS ✓`; clear set 2 → `Add weight`; tap → focus field 2; type `50` → `LOG 3 SETS ✓`; the
  `Fix reps` tail unchanged. The U1a mutation it proved (blocked tap focuses the failing field) is re-run on it.
- `test/contracts/active_workout_set_logging_behavioral_test.dart:296-315` pins `_onLogExercise` up to the FIRST
  `return outcome.kind;` (clear-focus regex, partner lines, no `nowWall(`): new lines go before that return in the
  existing order; `:319-325` requires ONE `final logMode = …` (FINISH reuses it).
- `test/features/train/swap_undo_snackbar_dismisses_test.dart:267-286`: listener regex ends at the first `});`, so
  the new listener lines come after `_dismissSwapUndoSnackBar()` with no `});`; `dispose()` keeps the dismiss call.
- `test/train/set_add_append_test.dart:16-55`: new `didUpdateWidget` lines stay out of the swap branch.

## 7. Stated limits (not deferrals)
- Unlogged typed or mirrored values are recorded on LOG, not per keystroke. A card whose State is recreated
  (leaving the screen, or scrolling out of the ListView cache) restores only captured keys (`exercise_card.dart:
  146-164`), so they reset to prefill: existing behaviour in both modes (OFF captures on check).
- No auto-scroll to FINISH (OI-357).

## 8. Process obligations
Diagnose doc `c7d2a9` (full template). SoT registry `active_workout_set_logging`: writer `unlogSets` (+ the
`_completing` rule), mirror note; readers `liveVolumeKg`, `completeWorkout :1977`, receipt, `undoRecordFor`,
`visibleUndoRecord`, `logToastText`, `allExercisesLogged`, `mirrorTargets`/`mirrorSourceIndex`; note that
`_initControllers` restores `setInputValues` WITHOUT a checked filter (after UNDO it restores the logged values:
benign, stated); re-baseline every `line_range` touched (the parity gate checks bounds only). Nested `lib/features/train/CLAUDE.md` row. `docs/ship_dark_pending_review.yaml` precondition 1.
OI-356 closed and archived to `closed_issues.md` (`closes-oi: OI-356`). Naming glossary rows. Full gate loop
(`flutter analyze lib/`, full `flutter test` with `TZ=Asia/Kolkata`, pre-commit) before review #2's code check
and the B-pass.
