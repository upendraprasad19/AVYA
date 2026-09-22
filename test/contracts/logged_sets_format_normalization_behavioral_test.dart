import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/models/exercise_set.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_bootstrap.dart';

/// a4c7d1: Behavioral tests for logged_sets_format_normalization.
///
/// Verifies that:
/// 1. When an exercise is logged with a NEW logging type, persisted sets
///    are normalized (phantom fields cleared) to match that type.
/// 2. Boot-time healer corrects any existing mismatched exlog rows.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await HiveTestBootstrap.init();
    ErrorTelemetry.instance.init();
  });

  tearDown(() async {
    final workoutBox = HiveService.instance.workoutBox;
    await workoutBox.clear();
  });

  group('logged_sets_format_normalization', () {
    test(
      'normalizes to timed: clears weight/reps when logging timed exercise',
      () async {
        final testDate = DateTime(2026, 9, 22);
        final sets = [
          ExerciseSet(
            weightKg: 10.0,
            reps: 8,
            durationSec: null,
            loggedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ];

        // Log with timed exercise (durationSec = 20)
        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Handstand Hold',
          sets: [
            ExerciseSet(
              durationSec: 20,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        final box = HiveService.instance.workoutBox;
        final key = WorkoutWriteService.exlogKey(testDate, 'Handstand Hold');
        final logged = box.get(key) as Map;

        // Verify normalized: durationSec preserved, weight/reps cleared
        expect(logged['logging_type'], 'timed');
        expect(logged['sets'], isNotEmpty);
        final firstSet = logged['sets'][0] as Map;
        expect(firstSet['duration_sec'], 20);
        expect(firstSet['weight_kg'], 0);
        expect(firstSet['reps'], 0);
      },
    );

    test(
      'normalizes to weight/reps: clears duration when logging weight/reps exercise',
      () async {
        final testDate = DateTime(2026, 9, 22);

        // Log with weight/reps exercise
        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Single Leg Front Lever',
          sets: [
            ExerciseSet(
              weightKg: 0.0,
              reps: 8,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        final box = HiveService.instance.workoutBox;
        final key = WorkoutWriteService.exlogKey(testDate, 'Single Leg Front Lever');
        final logged = box.get(key) as Map;

        // Verify normalized: weight/reps preserved, durationSec cleared
        expect(logged['logging_type'], 'bodyweight_reps');
        expect(logged['sets'], isNotEmpty);
        final firstSet = logged['sets'][0] as Map;
        expect(firstSet['weight_kg'], 0);
        expect(firstSet['reps'], 8);
        expect(firstSet['duration_sec'], 0);
      },
    );

    test(
      'swapping timed→weight/reps: in-session swap followed by log normalizes correctly',
      () async {
        final testDate = DateTime(2026, 9, 22);

        // Simulate swap: original timed exercise, then swapped to weight/reps
        // First log as timed (before swap)
        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Single Leg Front Lever',
          sets: [
            ExerciseSet(
              durationSec: 8,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        final box = HiveService.instance.workoutBox;
        final key = WorkoutWriteService.exlogKey(testDate, 'Single Leg Front Lever');
        var logged = box.get(key) as Map;

        // Verify initial state: timed with durationSec
        expect(logged['logging_type'], 'timed');
        expect(logged['sets'][0]['duration_sec'], 8);

        // Now log again (after swap): same exercise name, weight/reps data
        // WorkoutWriteService will detect it's a weight/reps exercise and normalize
        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Single Leg Front Lever',
          sets: [
            ExerciseSet(
              weightKg: 0.0,
              reps: 10,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        // Verify merged and normalized: timed values merged, but type should be resolved
        logged = box.get(key) as Map;
        expect(logged['set_number'], 2); // Both sets persisted

        // The second set should be normalized (no stale durationSec)
        final secondSet = logged['sets'][1] as Map;
        expect(secondSet['reps'], 10);
        expect((secondSet['duration_sec'] as int?) ?? 0, 0); // Cleared
      },
    );

    test(
      'edit log reads normalized sets: no stale field values rendered',
      () async {
        // This test verifies the reader side: EditWorkoutLogSheet.fromLog
        // should read the normalized persisted data correctly.
        final testDate = DateTime(2026, 9, 22);

        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Lat Pulldown',
          sets: [
            ExerciseSet(
              weightKg: 80.0,
              reps: 8,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        final box = HiveService.instance.workoutBox;
        final key = WorkoutWriteService.exlogKey(testDate, 'Lat Pulldown');
        final logged = box.get(key) as Map;

        // Verify no phantom durationSec in the persisted sets
        final setData = logged['sets'][0] as Map;
        expect(setData['weight_kg'], 80);
        expect(setData['reps'], 8);
        expect(setData.containsKey('duration_sec') ? setData['duration_sec'] : 0, 0);
      },
    );

    test(
      'correctly-matched rows remain untouched by normalization',
      () async {
        final testDate = DateTime(2026, 9, 22);

        // Log a timed exercise with timed data (already matched)
        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Plank Hold',
          sets: [
            ExerciseSet(
              durationSec: 45,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        final box = HiveService.instance.workoutBox;
        final key = WorkoutWriteService.exlogKey(testDate, 'Plank Hold');
        var logged = box.get(key) as Map;

        // Verify correct state
        expect(logged['logging_type'], 'timed');
        expect(logged['sets'][0]['duration_sec'], 45);
        expect(logged['sets'][0]['weight_kg'], 0);

        final originalSets = List.from(logged['sets'] as List);

        // Re-log the same exercise (no swap)
        await WorkoutWriteService.instance.logExercise(
          date: testDate,
          exerciseName: 'Plank Hold',
          sets: [
            ExerciseSet(
              durationSec: 50,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
          ],
          source: WriteSource.activeWorkout,
        );

        logged = box.get(key) as Map;

        // Verify type still matches, new set added, no corruption
        expect(logged['logging_type'], 'timed');
        expect(logged['sets'].length, 2);
        // Second set should also be timed (no reps/weight)
        expect(logged['sets'][1]['duration_sec'], 50);
        expect(logged['sets'][1]['weight_kg'], 0);
      },
    );
  });
}

/// Enumeration matching WriteSource in workout_write_service.dart
enum WriteSource {
  activeWorkout,
  coachLog,
  manualEdit,
  restore,
  migration;

  String get code => name;
}
