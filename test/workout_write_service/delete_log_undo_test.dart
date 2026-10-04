import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('deleteLog removes entry + drops from index', () async {
    final date = DateTime(2026, 5, 1);

    await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(
            weightKg: 80, reps: 5, loggedAtMs: date.millisecondsSinceEpoch),
      ],
      source: WriteSource.activeWorkout,
    );

    final box = HiveService.instance.workoutBox;
    final key = WorkoutWriteService.exlogKey(date, 'Bench Press');
    expect(box.containsKey(key), isTrue);

    final r = await WorkoutWriteService.instance.deleteLog(
      logKey: key,
      source: WriteSource.editSheet,
    );
    expect(r.success, isTrue);
    expect(box.containsKey(key), isFalse);

    // Index should no longer contain the key
    final indexKey =
        'exercise_log_index_${WorkoutWriteService.istDateStr(date)}';
    final idx = (box.get(indexKey) as List?) ?? const [];
    expect(idx.contains(key), isFalse);
  });
}
