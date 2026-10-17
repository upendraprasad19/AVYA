import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('60s dedup: same (weight, reps) twice within 60s → 1 entry in sets[]',
      () async {
    final date = DateTime(2026, 5, 1, 10);
    final now = date.millisecondsSinceEpoch;

    final r1 = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r1.success, isTrue);

    // Same (weight, reps) 30s later — should be deduped.
    final r2 = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [
        ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now + 30000),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r2.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Lat Pulldown');
    final entry = (box.get(key) as Map?)!.cast<String, dynamic>();
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 1, reason: 'duplicate inside 60s window must be dropped');
  });

  test('60s dedup: same (weight, reps) AFTER 60s → 2 entries in sets[]',
      () async {
    final date = DateTime(2026, 5, 1, 10);
    final now = date.millisecondsSinceEpoch;

    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now)],
      source: WriteSource.aiCoach,
    );

    // Same set 90s later — different rest interval, treat as a new
    // legitimate set.
    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: now + 90000)],
      source: WriteSource.aiCoach,
    );

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Lat Pulldown');
    final entry = (box.get(key) as Map?)!.cast<String, dynamic>();
    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.length, 2);
  });
}
