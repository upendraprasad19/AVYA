// In-workout MOVE (docs/plans/active-workout-swap-move.md Task 1): pure
// eligibility and slide math. The one writer is
// `ActiveWorkoutNotifier.applyExerciseMove`; this file never touches state.
//
// A move SLIDES one exercise: it is removed at `from` and inserted at `to`, so
// it ends at index `to` and everything between shifts by one. Every
// index-keyed field ('<ex>-<set>' and '<ex>-<set>-<field>') is remapped by the
// same permutation, so logged sets, warm-ups, typed and app-filled values stay
// with their exercise. Index-based on purpose: names can repeat (OI-358).
import '../providers/train_provider.dart';

/// A card's part in move mode.
enum MoveRole { none, source, target }

/// [i] is in range and not done: done exercises are locked in place.
bool canMoveExercise(ActiveWorkoutData d, int i) =>
    i >= 0 && i < d.exercises.length && !d.isExerciseDone(i);

/// At least two exercises can move, so a move has somewhere to go.
bool hasMoveCandidates(ActiveWorkoutData d) {
  var n = 0;
  for (var i = 0; i < d.exercises.length; i++) {
    if (canMoveExercise(d, i) && ++n >= 2) return true;
  }
  return false;
}

/// Every index [from] may be placed at, ascending; empty if it cannot move.
List<int> moveTargets(ActiveWorkoutData d, int from) {
  if (!canMoveExercise(d, from)) return const [];
  return [
    for (var i = 0; i < d.exercises.length; i++)
      if (i != from && canMoveExercise(d, i)) i,
  ];
}

/// [i]'s role while [sourceIndex] is moving (null: not in move mode). A stale
/// source (out of range or no longer movable) gives `none` everywhere.
MoveRole moveRoleFor(ActiveWorkoutData d, int? sourceIndex, int i) {
  if (sourceIndex == null || !canMoveExercise(d, sourceIndex)) {
    return MoveRole.none;
  }
  if (i == sourceIndex) return MoveRole.source;
  return canMoveExercise(d, i) ? MoveRole.target : MoveRole.none;
}

/// Slide the exercise at [from] to [to]. Null when `from == to`, an index is
/// out of range, or (with [requireMovable]) either exercise is done.
/// `requireMovable: false` exists ONLY for the UNDO inverse: the exercise a
/// move displaced into the vacated slot may be done by then.
ExerciseMoveResult? moveExerciseInSession(
  ActiveWorkoutData d, {
  required int from,
  required int to,
  bool requireMovable = true,
}) {
  final n = d.exercises.length;
  if (from == to || from < 0 || from >= n || to < 0 || to >= n) return null;
  if (requireMovable && (!canMoveExercise(d, from) || !canMoveExercise(d, to))) {
    return null;
  }

  int remap(int i) {
    if (i == from) return to;
    if (from < to && i > from && i <= to) return i - 1;
    if (from > to && i >= to && i < from) return i + 1;
    return i;
  }

  /// '<ex>-<rest>' with <ex> remapped; null for a key that does not parse.
  String? remapKey(String key) {
    final dash = key.indexOf('-');
    if (dash <= 0) return null;
    final ex = int.tryParse(key.substring(0, dash));
    if (ex == null) return null;
    return '${remap(ex)}${key.substring(dash)}';
  }

  Map<String, V> remapMap<V>(Map<String, V> m) => {
        for (final e in m.entries) ?remapKey(e.key): e.value,
      };

  final exercises = List<ExerciseData>.from(d.exercises);
  exercises.insert(to, exercises.removeAt(from));

  return ExerciseMoveResult(
    basedOn: d,
    exercises: exercises,
    checkedSets: remapMap(d.checkedSets),
    warmUpSets: remapMap(d.warmUpSets),
    setInputValues: remapMap(d.setInputValues),
    // Three-part keys only, as `removeExercise` keeps them.
    suggestedInputs: {
      for (final k in d.suggestedInputs)
        if (k.split('-').length == 3) ?remapKey(k),
    },
  );
}

/// The move that put [exerciseName] at [movedTo] can still be undone: it is
/// still there (nothing else was moved into its slot) and not done since.
bool moveUndoApplicable(ActiveWorkoutData d,
    {required String exerciseName, required int movedTo}) {
  if (movedTo < 0 || movedTo >= d.exercises.length) return false;
  return d.exercises[movedTo].name == exerciseName &&
      !d.isExerciseDone(movedTo);
}
