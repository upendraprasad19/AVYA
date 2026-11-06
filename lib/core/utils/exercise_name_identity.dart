/// One exercise name per workout day (OI-358).
///
/// The Active Workout screen keys each card by exercise name (a reorder keeps
/// its card that way), and `WorkoutWriteService.exlogKey` saves one log row per
/// name per date, so two entries with one name cannot work: the screen throws
/// and the logs collapse. These helpers are the one definition of "the same
/// name" for every writer that can add a name to a day.
library;

/// The identity of an exercise name. Keep this equal to the normalisation
/// `WorkoutWriteService.exlogKey` hashes: two names that share a key here save
/// to one log row. Pinned by `exercise_name_unique_in_day_behavioral_test.dart`.
String exerciseNameKey(String name) => name.toLowerCase().trim();

/// The name on a stored row. Both shapes exist: `exercise_name` on schedule
/// rows and `createTemplate` rows, `name` on library rows and in the template
/// builder, both on restored templates. Null when the row has neither, which
/// includes the empty map a malformed slot parses to.
String? exerciseRowName(Map row) {
  for (final key in const ['exercise_name', 'name']) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

/// The keys of [names], skipping any without a name. The set is growable: a
/// planner adds each name it hands out.
Set<String> exerciseNameKeysOf(Iterable<String?> names) => {
      for (final name in names)
        if (name != null && name.trim().isNotEmpty) exerciseNameKey(name),
    };

/// [rows] with only the first of each name, in order. A row without a name is
/// not an exercise identity and is always kept.
List<T> firstPerExerciseName<T>(
  Iterable<T> rows,
  String? Function(T row) nameOf,
) {
  final seen = <String>{};
  final kept = <T>[];
  for (final row in rows) {
    final name = nameOf(row);
    if (name == null || name.trim().isEmpty || seen.add(exerciseNameKey(name))) {
      kept.add(row);
    }
  }
  return kept;
}
