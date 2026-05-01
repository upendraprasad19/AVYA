import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('new day creates new entry; old day untouched', () async {
    final mon = DateTime(2026, 5, 4);
    final tue = DateTime(2026, 5, 5);

    await WorkoutWriteService.instance.logExercise(
      date: mon,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 40, reps: 10, loggedAtMs: mon.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );

    await WorkoutWriteService.instance.logExercise(
      date: tue,
      exerciseName: 'Lat Pulldown',
      sets: [ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: tue.millisecondsSinceEpoch)],
      source: WriteSource.activeWorkout,
    );

    final box = HiveService.instance.workoutBox;
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 2, reason: 'two distinct days → two distinct entries');

    final monKey = WorkoutWriteService.exlogKey(mon, 'Lat Pulldown');
    final tueKey = WorkoutWriteService.exlogKey(tue, 'Lat Pulldown');
    expect(monKey == tueKey, isFalse);
    expect(box.containsKey(monKey), isTrue);
    expect(box.containsKey(tueKey), isTrue);
  });
}
