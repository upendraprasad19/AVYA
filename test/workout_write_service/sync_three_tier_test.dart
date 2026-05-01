import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('logExercise writes Hive entry with all fields needed for 3-tier sync',
      () async {
    final date = DateTime(2026, 5, 1);
    final now = date.millisecondsSinceEpoch;

    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now),
        ExerciseSet(weightKg: 60, reps: 10, loggedAtMs: now + 90_000),
        ExerciseSet(weightKg: 80, reps: 10, loggedAtMs: now + 180_000),
        ExerciseSet(weightKg: 100, reps: 7, loggedAtMs: now + 270_000),
      ],
      source: WriteSource.aiCoach,
    );

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Lat Pulldown');
    final entry = (box.get(key) as Map?)!.cast<String, dynamic>();

    // Tier 1 fields (workout_logs)
    expect(entry['date'], '2026-05-01');

    // Tier 2 fields (workout_log_exercises)
    expect(entry['exercise_name'], 'Lat Pulldown');
    expect(entry['set_number'], 4);
    expect(entry['reps_completed'], 37);
    expect(entry['weight_kg'], 100);
    // Plan's expected 2300 was an arithmetic mistake.
    // 40*10 + 60*10 + 80*10 + 100*7 = 400 + 600 + 800 + 700 = 2500.
    expect((entry['volume_kg'] as num).toInt(), 2500);

    // Tier 3 fields (workout_log_sets) — one map per ExerciseSet
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 4);
    expect(sets[0]['weight_kg'], 40);
    expect(sets[3]['weight_kg'], 100);
    expect(sets.every((s) => s['logged_at_ms'] != null), isTrue);
  });
}
