import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('editLog: lowering an old PR reassigns is_pr to a later log', () async {
    final apr1 = DateTime(2026, 4, 1);
    final apr8 = DateTime(2026, 4, 8);
    final apr15 = DateTime(2026, 4, 15);

    // Seed three logs in chronological order
    await WorkoutWriteService.instance.logExercise(
      date: apr1,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(
            weightKg: 80, reps: 5, loggedAtMs: apr1.millisecondsSinceEpoch),
      ],
      source: WriteSource.activeWorkout,
    );
    await WorkoutWriteService.instance.logExercise(
      date: apr8,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(
            weightKg: 100, reps: 5, loggedAtMs: apr8.millisecondsSinceEpoch),
      ],
      source: WriteSource.activeWorkout,
    );
    await WorkoutWriteService.instance.logExercise(
      date: apr15,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(
            weightKg: 90, reps: 5, loggedAtMs: apr15.millisecondsSinceEpoch),
      ],
      source: WriteSource.activeWorkout,
    );

    final box = HiveService.instance.workoutBox;
    final apr8Key = WorkoutWriteService.exlogKey(apr8, 'Bench Press');
    final apr8Before = (box.get(apr8Key) as Map).cast<String, dynamic>();
    expect(apr8Before['is_pr'], isTrue);

    // Edit the apr8 log down to 70 kg — apr1's 80 should now hold the PR
    final r = await WorkoutWriteService.instance.editLog(
      logKey: apr8Key,
      updates: {
        'sets': [
          {'weight_kg': 70, 'reps': 5, 'logged_at_ms': apr8.millisecondsSinceEpoch}
        ],
      },
      source: WriteSource.editSheet,
    );
    expect(r.success, isTrue);

    final apr1Key = WorkoutWriteService.exlogKey(apr1, 'Bench Press');
    final apr1After = (box.get(apr1Key) as Map).cast<String, dynamic>();
    final apr8After = (box.get(apr8Key) as Map).cast<String, dynamic>();
    expect(apr1After['is_pr'], isTrue,
        reason: 'apr1 80kg now has the PR (apr8 lowered to 70)');
    expect(apr8After['is_pr'], isFalse);
  });
}
