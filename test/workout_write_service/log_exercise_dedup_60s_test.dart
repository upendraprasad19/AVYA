import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  test('SCAFFOLD: logExercise throws UnimplementedError until Task A-4', () async {
    expect(
      () => WorkoutWriteService.instance.logExercise(
        date: DateTime(2026, 5, 1),
        exerciseName: 'Bench Press',
        sets: const [ExerciseSet(weightKg: 60, reps: 8)],
        source: WriteSource.activeWorkout,
      ),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
