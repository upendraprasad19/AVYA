import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bug F — getExerciseLogsForDate must inject the Hive
/// key as `id` on every returned map.
///
/// Pre-fix: EditWorkoutLogSheet showed "No exercise logs for this day"
/// after a completed workout. Cloud had 5 rows for the founder's user_id
/// on the same date. The local Hive ALSO had exlogs at correct keys —
/// but `getExerciseLogsForDate` returned the value maps without the
/// Hive key, and EditWorkoutLogSheet's `_loadRows` filtered
/// `where(log['id'] is String)` which stripped EVERYTHING.
///
/// Root cause — writer↔reader contract drift: Test #6 WriteService
/// rewrite never wrote an `'id'` value field on the entry map (the id
/// IS the Hive key). Pre-Test-#6 readers iterated `box.toMap()` and saw
/// the key directly; the indexed-path reader introduced afterward lost
/// that visibility.
///
/// Fix — in `WorkoutRepository.getExerciseLogsForDate`, inject the Hive
/// key as `id` on every returned map. Both the indexed-path branch AND
/// the legacy fallback branch. Also drop the `type == 'exercise_log'`
/// filter in the fallback — the WriteService doesn't write that field.
///
/// closes-diagnose: 2026-05-12-edit-log-id-injection-f4c9e1
void main() {
  late String repoSrc;

  setUpAll(() {
    repoSrc =
        File('lib/features/train/repositories/workout_repository.dart')
            .readAsStringSync();
  });

  group('getExerciseLogsForDate id injection', () {
    test('indexed-path branch injects Hive key as id', () {
      // The indexed-path branch (post-fix) does: m['id'] = id; logs.add(m);
      expect(
        repoSrc.contains("m['id'] = id;"),
        isTrue,
        reason:
            'getExerciseLogsForDate indexed-path must inject the Hive key '
            '(id from index list) as the m[\'id\'] field on each returned '
            'map. closes-diagnose: 2026-05-12-edit-log-id-injection-f4c9e1',
      );
    });

    test('legacy fallback branch injects Hive key as id', () {
      // The fallback branch (post-fix) does: map['id'] = key; logs.add(map);
      expect(
        repoSrc.contains("map['id'] = key;"),
        isTrue,
        reason:
            'getExerciseLogsForDate legacy fallback must inject the Hive '
            'key as map[\'id\'] so the returned shape matches the '
            'indexed-path shape.',
      );
    });

    test('forbidden: type filter inside getExerciseLogsForDate body', () {
      // The pre-fix line was: `if (map['type'] != 'exercise_log') continue;`
      // INSIDE getExerciseLogsForDate. Other methods (e.g. _rescanPrFor)
      // legitimately filter by type; scope the check to just this method.
      final marker = 'List<Map<String, dynamic>> getExerciseLogsForDate(';
      final start = repoSrc.indexOf(marker);
      expect(start, greaterThan(0));
      // Find end-of-method (next top-level method declaration).
      final end = repoSrc.indexOf("\n  ${'/' * 3}", start + 1);
      final body = end > start
          ? repoSrc.substring(start, end)
          : repoSrc.substring(start, (start + 2500).clamp(0, repoSrc.length));
      expect(
        body.contains("map['type'] != 'exercise_log'"),
        isFalse,
        reason:
            'forbidden — getExerciseLogsForDate must NOT filter by '
            'map[\'type\'] != \'exercise_log\'. The WriteService stopped '
            'writing type; this filter dropped every row. Use '
            'exercise_name presence as discriminator.',
      );
    });

    test('fallback uses exercise_name as discriminator', () {
      expect(
        repoSrc.contains("map['exercise_name'] == null"),
        isTrue,
        reason:
            'Legacy fallback must use exercise_name == null as the skip '
            'condition (since WriteService always writes exercise_name).',
      );
    });
  });
}
