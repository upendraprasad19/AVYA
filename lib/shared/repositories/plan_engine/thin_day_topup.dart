import 'models.dart';

/// OI-401: pure rules for the thin-day top-up.
///
/// An injured user's generated day can come out with one or two exercises,
/// because the injury filter drops a slot when no safe candidate exists and
/// nothing refills the day afterwards. `ExerciseSelector.topUpDays` tops such a
/// day up (own pattern, then a neighbouring pattern, then core, then stops).
/// This file holds only the rules that need no library access, so they are
/// testable without Hive: the floor, the neighbour table, the trigger and the
/// anchor ordering. It must stay pure: no `queryV4`, no `getAll()`, no
/// `PlannedExercise(` (`scripts/check_exercise_seams.dart` counts the selector's
/// library reads; this file adds none).
class ThinDayTopUp {
  ThinDayTopUp._();

  /// A variant (A or B) with fewer exercises than this is topped up. The founder's
  /// rule is "fewer than 3" (OI-401, option b, 2026-10-23); one constant, so a
  /// fuller floor is a one-line change plus a sweep re-run.
  static const int floor = 3;

  /// Movement-pattern adjacency, closest first. The slot's OWN pattern is tried
  /// before these (the selector prepends it), `core` is never a neighbour (it is
  /// its own last stage), and a pattern never lists itself. A movement-pattern
  /// adjacency chosen for the top-up, not a founder ruling.
  static const Map<String, List<String>> neighbours = {
    'horizontal_push': ['vertical_push', 'elbow_extension', 'shoulder_isolation'],
    'vertical_push': ['horizontal_push', 'shoulder_isolation', 'elbow_extension'],
    'horizontal_pull': ['vertical_pull', 'shoulder_isolation', 'elbow_flexion'],
    'vertical_pull': ['horizontal_pull', 'elbow_flexion', 'shoulder_isolation'],
    'knee_dominant': ['hip_dominant', 'hip_isolation'],
    'hip_dominant': ['knee_dominant', 'hip_isolation'],
    'elbow_flexion': ['horizontal_pull', 'vertical_pull'],
    'elbow_extension': ['horizontal_push', 'vertical_push'],
    'shoulder_isolation': ['vertical_push', 'horizontal_pull'],
    'hip_isolation': ['hip_dominant', 'knee_dominant'],
  };

  /// True when a variant of [count] exercises is topped up: the user has an
  /// injury AND the variant is under [floor]. An uninjured user is never topped
  /// up (their plan stays byte-identical).
  static bool applies({required List<String> injuries, required int count}) =>
      injuries.isNotEmpty && count < floor;

  /// The day's own (muscle, pattern) pairs, in slot-priority order (ties by the
  /// slot's original index; `List.sort` is not documented stable, so the index is
  /// part of the key), core slots dropped, de-duplicated by (muscle, pattern).
  static List<({String muscle, String pattern})> anchors(
      List<MuscleSlot> slots) {
    final indexed = [for (var i = 0; i < slots.length; i++) (i, slots[i])]
      ..sort((x, y) {
        final c = x.$2.priority.compareTo(y.$2.priority);
        return c != 0 ? c : x.$1.compareTo(y.$1);
      });
    final seen = <String>{};
    final out = <({String muscle, String pattern})>[];
    for (final (_, s) in indexed) {
      if (s.movementPattern == 'core') continue;
      if (!seen.add('${s.targetMuscle}|${s.movementPattern}')) continue;
      out.add((muscle: s.targetMuscle, pattern: s.movementPattern));
    }
    return out;
  }
}
