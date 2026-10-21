// lib/core/services/auto_appended_custom.dart
//
// d4b8e1 Batch 0b (plan docs/plans/2026-10-21-l2-custom-repair.md). The
// removed plan-generator lever L2 appended a user's custom exercises to
// generated days on its own. 0a stopped NEW generations; this file is the ONE
// definition of "a custom L2 put there", shared by the one-time repair of
// existing day rows (L2CustomAppendRepairMigrator) and the repeat-pin read
// (WorkoutScheduleReadService._buildRepeatPins), so the two can never disagree.
//
// Every exercise-level key read lives here (Hive field drift gate, Gate 19):
// this file holds no day-row key prefix literal.
//
// Pure: no Hive, no clock. Never mutates its input — day rows read back from
// Hive share their `exercises` list with Hive's in-memory cache.

/// True when [exercise] is a custom exercise the generator added on its own:
///  - it carries no provenance stamp: `swapped_via` (a coach swap) or
///    `custom_origin` (a repeat pin, buildPinnedDays) marks a deliberate
///    choice, which stays;
///  - its trimmed, lower-cased `exercise_name` is one of [customNamesLower];
///  - the library has no exercise of that name ([libraryHas]); on a collision
///    the library wins and the exercise stays.
bool isAutoAppendedCustom(
  Map exercise, {
  required Set<String> customNamesLower,
  required bool Function(String name) libraryHas,
}) {
  if (exercise.containsKey('swapped_via') ||
      exercise.containsKey('custom_origin')) {
    return false;
  }
  final name = exercise['exercise_name'];
  if (name is! String) return false;
  final norm = name.trim().toLowerCase();
  if (norm.isEmpty || !customNamesLower.contains(norm)) return false;
  return !libraryHas(name);
}

/// The `libraryHas` row test both callers use, applied to every exerciseBox
/// row of a name (`ExerciseRepository.hasExactNameWhere`, which does not stop
/// at the first row: a community row can share a bundled row's name): a real
/// library row, not a community-approved custom (`source: 'community'`,
/// written by the community pull). Community rows have no `movement_pattern`,
/// so the generator never picks one; a community name in a generated row came
/// from L2.
bool isLibraryRow(Map row) => row['source'] != 'community';

/// A NEW list: [exercises] without the auto-appended customs, order kept.
/// Elements that are not maps are kept as they are.
List<dynamic> stripAutoAppendedCustoms(
  List exercises, {
  required Set<String> customNamesLower,
  required bool Function(String name) libraryHas,
}) =>
    [
      for (final e in exercises)
        if (e is! Map ||
            !isAutoAppendedCustom(e,
                customNamesLower: customNamesLower, libraryHas: libraryHas))
          e,
    ];

/// A NEW map: [row] with its `exercises` list stripped. A row whose
/// `exercises` is not a list is copied unchanged.
Map<String, dynamic> stripRow(
  Map row, {
  required Set<String> customNamesLower,
  required bool Function(String name) libraryHas,
}) {
  final copy = Map<String, dynamic>.from(row);
  final exercises = row['exercises'];
  if (exercises is List) {
    copy['exercises'] = stripAutoAppendedCustoms(exercises,
        customNamesLower: customNamesLower, libraryHas: libraryHas);
  }
  return copy;
}
