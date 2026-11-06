@Timeout(Duration(minutes: 3))
library;

// OI-389 Batch 1a T5 / T28 / T28c: the active workout's save
// (ActiveWorkoutNotifier.completeWorkout → exerciseSetFromInput →
// WorkoutWriteService.logExercise with the slot's loggingTypeHint) stores a
// cardio set's minutes as seconds and its km. Real Hive; the boxes hold
// seconds already (converted at capture, D2), as the card hands them over.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';

class _SeededNotifier extends ActiveWorkoutNotifier {
  _SeededNotifier(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

ExerciseData _ex(String name, String type) =>
    ExerciseData(name: name, sets: '1', loggingType: type);

final _date = DateTime(2026, 10, 21);

Future<Map<String, dynamic>> _save(ExerciseData ex, SetInputValues v) async {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    activeWorkoutProvider.overrideWith(() => _SeededNotifier(ActiveWorkoutData(
          workoutDay: WorkoutDayData(
              dayNumber: 1, name: 'Cardio', date: _date, exercises: [ex]),
          exercises: [ex],
          checkedSets: const {'0-0': true},
          setInputValues: {'0-0': v},
        ))),
  ]);
  addTearDown(c.dispose);
  await c
      .read(activeWorkoutProvider.notifier)
      .completeWorkout()
      .timeout(const Duration(minutes: 1));
  // The session date is resolved by resolveSessionDate (today for a past
  // scheduled day), so find the row by name.
  final box = HiveService.instance.workoutBox;
  return Map<String, dynamic>.from(box.keys
      .where((k) => k.toString().startsWith('exlog_'))
      .map((k) => box.get(k) as Map)
      .singleWhere((m) => m['exercise_name'] == ex.name));
}

void main() {
  setUp(() async {
    final dir = await setUpHiveForTests();
    addTearDown(() => tearDownHiveForTests(dir));
    final exb = HiveService.instance.exerciseBox;
    await exb.put('lib_run', {'name': 'Running (Treadmill)', 'logging_type': 'cardio'});
    await exb.put('lib_plank', {'name': 'Plank', 'logging_type': 'timed'});
  });

  test('T5: Running (Treadmill) 30 MIN 4 KM → 1800 s, 4.0 km', () async {
    final row = await _save(_ex('Running (Treadmill)', 'cardio'),
        const SetInputValues(durationSeconds: 1800, distanceKm: 4));
    final set = (row['sets'] as List).single as Map;
    expect(row['logging_type'], 'cardio');
    expect(set['duration_sec'], 1800);
    expect(set['distance_km'], 4.0);
    expect(row['distance_km'], 4.0);
  });

  test('T28: a custom "Cardio" slot (not in the library) stays cardio',
      () async {
    final row = await _save(_ex('Cardio', 'cardio'),
        const SetInputValues(durationSeconds: 1800, distanceKm: 3));
    expect(row['logging_type'], 'cardio');
    expect(((row['sets'] as List).single as Map)['duration_sec'], 1800);
    expect(row['distance_km'], 3.0);
  });

  test('T28c: library Plank (timed) with a cardio slot hint stays timed',
      () async {
    final row = await _save(_ex('Plank', 'cardio'),
        const SetInputValues(durationSeconds: 60, distanceKm: 1));
    expect(row['logging_type'], 'timed');
    expect(row.containsKey('distance_km'), isFalse);
  });
}
