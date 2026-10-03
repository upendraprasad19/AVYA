import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('appends sets across calls: 4 calls → 1 row, sets[].length=4', () async {
    final date = DateTime(2026, 5, 1);
    final progression = [
      ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: date.millisecondsSinceEpoch),
      ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: date.millisecondsSinceEpoch + 90_000),
      ExerciseSet(weightKg: 80, reps: 10, loggedAtMs: date.millisecondsSinceEpoch + 180_000),
      ExerciseSet(weightKg: 100, reps: 7, loggedAtMs: date.millisecondsSinceEpoch + 270_000),
    ];

    for (final s in progression) {
      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Lat Pulldown',
        sets: [s],
        source: WriteSource.aiCoach,
      );
      expect(r.success, isTrue);
    }

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1, reason: 'exactly ONE row across 4 calls');

    final entry =
        (box.get(exlogKeys.first) as Map?)!.cast<String, dynamic>();
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 4);

    // Aggregates
    expect(entry['set_number'], 4);
    expect(entry['reps_completed'], 37);
    expect(entry['weight_kg'], 100);
    expect((entry['volume_kg'] as num).toInt(), 40 * 10 + 60 * 10 + 80 * 10 + 100 * 7);
  });

  test('multiple sets in single call: one logExercise(sets: [4 sets]) → 1 row, sets[].length=4',
      () async {
    final date = DateTime(2026, 5, 1);
    final base = date.millisecondsSinceEpoch;

    final r = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: base),
        ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: base + 90_000),
        ExerciseSet(weightKg: 80, reps: 10, loggedAtMs: base + 180_000),
        ExerciseSet(weightKg: 100, reps: 7, loggedAtMs: base + 270_000),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1);
    final entry = (box.get(exlogKeys.first) as Map?)!.cast<String, dynamic>();
    expect((entry['sets'] as List).length, 4);
  });
}
