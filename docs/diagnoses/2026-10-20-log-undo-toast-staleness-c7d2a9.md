---
bug_id: c7d2a9
date: 2026-10-20
batch: log-exercise-batch2 (OI-356)
status: fixed
blast_radius: account
tier: full
symptom: |
  Prevention record, not a field report. OI-356 asked for an UNDO toast after
  the one-LOG-per-exercise LOG and assigned it to the snackbar staleness class
  (b4e7f1: the swap-undo SnackBar outlived completion / cancel / back; s1n4c0:
  a SnackBar shown from under a still-mounted modal never dismissed). Built
  naively, a LOG toast would (1) queue behind or ahead of other SnackBars and
  show late, (2) outlive the session, (3) after a removal or swap point its
  UNDO at the wrong exercise, or throw in build, and (4) let UNDO run during
  the un-awaited completeWorkout() and drop the last exercise from the save.
concept: active_workout_set_logging
sot_registry_entry: active_workout_set_logging
related_bugs: [b4e7f1, s1n4c0]
recurrence: |
  Same UI-lifecycle class as b4e7f1 and s1n4c0 (a toast/SnackBar whose life is
  not tied to the screen and session it describes). Not a recurrence of either
  defect: no SnackBar is used. The class is prevented by design: the toast is
  a child of the active-workout screen's own tree, so it cannot outlive it.
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: ActiveWorkoutNotifier.unlogSets, line: 1546 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutNotifier.completeWorkout (_completing = true)", line: 1851 }
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: _ActiveWorkoutScreenState._showLogUndo, line: 124 }
readers:
  - { file: lib/features/train/services/log_exercise_logic.dart, method_or_widget: visibleUndoRecord, line: 436 }
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: _ActiveWorkoutScreenState._withLogUndoToast, line: 165 }
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: _ActiveWorkoutScreenState._onLogUndo, line: 149 }
hive_key_prefix: "n/a: the UNDO record is session-only screen state (never an undo_<logKey> Hive key)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/contracts/active_workout_set_logging_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a: session-only state; the notifier rebuilds on authUserIdTokenProvider (train_provider.dart build), and every session starts in startWorkout, which resets _completing"
forbidden_patterns_checked:
  - { pattern: "showSnackBar in the LOG/UNDO path (screen.dart _onLogExercise/_showLogUndo/_onLogUndo)", absent: true }
  - { pattern: "nowWall\\( in the toast timing (log_exercise_logic.dart UNDO helpers)", absent: true }
  - { pattern: "ActiveWorkoutPersistence in _onLogUndo", absent: true }
proposed_fix: |
  In-tree toast (LogUndoToast) over the top of the exercise list, driven by
  screen State: a LogUndoRecord (exercise index + name + exactly the sets the
  LOG checked + shownAt on the monotonic LOG clock + generation). Pure gates:
  undoRecordFor (null while a save runs), visibleUndoRecord (5 s window,
  saved, index bounds, name identity, every record set still checked),
  shouldIgnoreUndo (400 ms). The host (LogUndoToastHost) keeps one tree
  shape in LOG mode, so the toast coming and going never rebuilds the list
  (B-pass finding 1). New writer unlogSets (identity + range checked,
  no-op while _completing / saved / complete). FINISH's COMPLETE path clears
  the toast (onComplete), the completion ref.listen and dispose() cancel the
  Timer, and the Timer clears only its own generation.
regression_test_planned:
  - test/contracts/active_workout_set_logging_behavioral_test.dart
  - test/features/train/log_exercise/log_exercise_logic_test.dart
  - test/features/train/log_exercise/log_undo_toast_test.dart
impact_analysis: |
  Flag OFF (enable_log_exercise_button default OFF): unchanged by construction
  (the toast is built only when logMode; FINISH keeps its primary variant;
  unlogSets and _completing have no OFF caller that changes behaviour, since
  _completing is read only by unlogSets). Flag ON: LOG shows the toast; UNDO
  unchecks exactly the logged sets. The coach snapshot is deliberately left as
  the LOG wrote it (clearing it would tell ai_snapshot_builder the session is
  over). Duplicate exercise names already crash the screen (OI-358); the name
  identity check assumes unique names.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/: no error or warning, no issue in any touched file (59 pre-existing infos elsewhere); behavioural, pure, widget and source tests listed below all green" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "no new Hive key; ActiveWorkoutPersistence active_session untouched by UNDO (source pin)" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "session-only client state" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "session-only client state" }
  - { tier: 12, name: "Client to server contract", status: verified, evidence: "completeWorkout still the only persister; test 11 proves UNDO cannot remove sets while it runs" }
mutation_proven:
  mutated: |
    N1 delete `_completing = true;`; N2 drop the `_completing` check from
    unlogSets; N3 remove the reset in startWorkout; N4 drop the name identity
    check; N5 unlogSets removes every set; P1 visibleUndoRecord without the
    bounds check; P2 without the sets-still-checked loop; P3 undoRecordFor
    ignores completing; P4 shouldIgnoreUndo `<=`; P7 window `>`; P8 ignores
    isSaved; W1/W2 IgnorePointer(ignoring: false); W4 UNDO not wired; S1 the
    screen no longer creates the record. After the B-pass: F1 the host returns
    the bare list when no toast shows (the shipped tree-shape swap); F1b the
    host builds a Stack with the flag OFF. Each applied with a single-match
    replacement, confirmed applied (count == 1), reverted after the run.
  result: |
    Every one RED: N1 2 tests, N2-N4 1 each, N5 3; P1-P8 1 each; W1, W2, W4 1
    each; S1 1 (source pin, presence only); F1 1 (scroll offset and row
    State identity), F1b 1. W1/W2 were first tried with a
    non-compiling edit; that run was discarded as proof and redone with
    `ignoring: false`.
  confirmed_applied: "scratch mutate script refuses unless the old text occurs exactly once; diff restored from a backup after each run"
---

## Summary

The UNDO toast after a LOG is built so the snackbar staleness class cannot
happen to it: it is a widget in the active-workout screen's own tree, its
visibility is a pure function of current state, and UNDO is a checked writer
that refuses to run while the save is in flight.

## Root cause (of the class, applied here)

A SnackBar lives in the `ScaffoldMessenger`, not in the screen that showed
it. SnackBars queue (`scaffold.dart` `showSnackBar` `addLast`) and a
controller's `close()` asserts it is the current one, so rapid LOGs would show
late toasts that cannot be closed; and nothing ties a SnackBar to the session.

## Fix

See `proposed_fix`. Placement is the top of the exercise list (the screen's
floating SnackBars are at the bottom); the toast body is `IgnorePointer`, only
UNDO takes touches.

## Verification

- Pure: `visibleUndoRecord`, `undoRecordFor`, `shouldIgnoreUndo`,
  `logToastText`, `allExercisesLogged` (`log_exercise_logic_test.dart`).
- Notifier (real): `unlogSets` identity with three exercises, round trip,
  and the completion race in `fakeAsync` with the REAL un-awaited
  `completeWorkout` (tests 11, 11b).
- Widget: `log_undo_toast_test.dart` (UNDO only; body passes taps through;
  long name, no overflow; the host keeps the list's scroll offset and row
  State when the toast comes and goes, and is a bare list with the flag OFF).

## B-pass (review `8812992b4995`)

A fresh reviewer found that the first build of the screen wiring returned the
bare `ListView` with no toast and a `Stack` with one. The element type at that
slot changed on every show and clear, so the list was rebuilt: the scroll
jumped to the top and cards outside the cache extent were disposed, losing
typed but unlogged values. The plan described an always-present Stack; the
source pins could not see the difference. Fixed with `LogUndoToastHost` and a
widget test that fails on the old shape.
- Screen wiring: source pins, presence only (the screen is a private
  `part of` State over many providers; the behaviour is proven on the units
  above, and "cannot outlive the screen" holds by construction).
