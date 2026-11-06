// Move mode for the Active Workout screen (docs/plans/active-workout-swap-move.md
// Task 4): which exercise is moving, placing it, its UNDO, and the first-use
// hint's show/retire decisions. Plain Dart owned by the screen (like
// LogExerciseController), so every decision is unit-tested; the screen only
// wires taps and state to it. Tap routing per card role lives in the card.
import '../providers/train_provider.dart';
import 'exercise_move_logic.dart';
import 'swap_move_hint.dart';

/// A completed move, kept by the screen for its UNDO.
class MovePlacement {
  final ExerciseMoveResult result;
  final String exerciseName;
  final int from;
  final int to;

  const MovePlacement({
    required this.result,
    required this.exerciseName,
    required this.from,
    required this.to,
  });
}

class MoveModeController {
  MoveModeController({required bool hintSeen}) : _hintSeen = hintSeen;

  int? _source;
  bool _hintSeen;
  bool _hintDismissed = false;
  bool _hintWasShown = false;

  int? get sourceIndex => _source;
  bool get active => _source != null;

  /// Start moving [index]; on the exercise already moving, stop instead.
  /// False when move mode is (now) off: [index] cannot move, nothing else
  /// can, or superset-grouping mode is on.
  bool enter(ActiveWorkoutData d, int index) {
    if (_source == index) {
      _source = null;
      return false;
    }
    if (d.isSupersetGroupMode ||
        !hasMoveCandidates(d) ||
        !canMoveExercise(d, index)) {
      return false;
    }
    _source = index;
    return true;
  }

  void cancel() => _source = null;

  /// Place the moving exercise at [target]. Move mode ends either way; null
  /// when not moving or the move is not allowed.
  MovePlacement? place(ActiveWorkoutData d, int target) {
    final from = _source;
    _source = null;
    if (from == null) return null;
    final r = moveExerciseInSession(d, from: from, to: target);
    if (r == null) return null;
    return MovePlacement(
      result: r,
      exerciseName: d.exercises[from].name,
      from: from,
      to: target,
    );
  }

  /// The inverse of [p] on the current [d], or null when it no longer applies
  /// (the mover was completed, or another exercise now sits in its slot).
  /// Skips target eligibility: the slot it returns to may hold a done
  /// exercise the move displaced.
  ExerciseMoveResult? undo(ActiveWorkoutData d, MovePlacement p) {
    if (!moveUndoApplicable(d, exerciseName: p.exerciseName, movedTo: p.to)) {
      return null;
    }
    return moveExerciseInSession(d,
        from: p.to, to: p.from, requireMovable: false);
  }

  /// Show the first-use hint now. Remembers that it was shown, so a later
  /// checked set may retire it.
  bool showHint(ActiveWorkoutData d) {
    final show = !active &&
        shouldShowSwapMoveHint(
            seen: _hintSeen, dismissedThisSession: _hintDismissed, data: d);
    if (show) _hintWasShown = true;
    return show;
  }

  /// Retire the hint. True only the first time on an account that had not
  /// seen it: the caller then persists `markSwapMoveHintSeen()`.
  bool dismissHint() {
    if (_hintSeen || _hintDismissed) return false;
    _hintSeen = true;
    _hintDismissed = true;
    return true;
  }

  /// A set was checked after the hint was on screen: retire it. Never for a
  /// hint the user did not see (a one-exercise day).
  bool shouldDismissHintOnData(ActiveWorkoutData d) =>
      !_hintSeen && !_hintDismissed && _hintWasShown && d.checkedSets.isNotEmpty;
}
