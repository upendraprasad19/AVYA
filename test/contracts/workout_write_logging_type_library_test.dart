// APK Test #12.5 / Class 5a — pin: WorkoutWriteService consults the
// exercise library for logging_type and strips phantom durationSec
// from per-set entries when the resolved type isn't 'timed'.
//
// Pre-fix `_inferLoggingType` was data-shape-only: a Push Up logged
// with stuffed `durationSec` (from controller bleed / swap-state
// retention) got stamped 'timed' → receipt rendered "× N reps" or
// "0s" depending on renderer. The library says Push Up is
// `bodyweight_reps`; we now trust the library and clean the data.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();

    // exerciseBox is a SHARED (not user-scoped) box; wwsTestSetup
    // doesn't open it because most tests don't need it. Open it
    // explicitly so the library lookup in WorkoutWriteService
    // returns hits instead of falling back to data inference.
    if (!Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.openBox(HiveService.exerciseBoxName);
    }

    // Seed exercise library entries needed for the test.
    final exb = HiveService.instance.exerciseBox;
    await exb.put('push_up', {
      'name': 'Push Up',
      'logging_type': 'bodyweight_reps',
    });
    await exb.put('handstand_hold', {
      'name': 'Handstand Hold',
      'logging_type': 'timed',
    });
    await exb.put('jump_rope', {
      'name': 'Jump Rope',
      'logging_type': 'timed',
    });
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('library-aware logging_type resolver', () {
    test(
        'Push Up + stuffed durationSec → resolved bodyweight_reps, '
        'per-set durationSec stripped', () async {
      final date = DateTime(2026, 5, 6);
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Push Up',
        // Simulating the controller-leak bug: durationSec stuffed onto
        // a bodyweight slot. Pre-fix this would write logging_type=timed.
        sets: const [
          ExerciseSet(weightKg: 0, reps: 18, durationSec: 18),
          ExerciseSet(weightKg: 0, reps: 18, durationSec: 18),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue);

      final box = HiveService.instance.workoutBox;
      // Exact key shape — istDateStr → exlog_<date>_<hash>
      final keys = box.keys
          .where((k) => k.toString().startsWith('exlog_'))
          .toList();
      expect(keys, hasLength(1));
      final row = box.get(keys.first) as Map;

      expect(row['logging_type'], 'bodyweight_reps',
          reason: 'library says bodyweight_reps — must override data shape');
      expect(row['set_number'], 2);
      expect(row['reps_completed'], 36);

      // Per-set entries: durationSec must be stripped.
      final sets = row['sets'] as List;
      expect(sets, hasLength(2));
      for (final s in sets) {
        final m = s as Map;
        expect(m['duration_sec'], isNull,
            reason: 'phantom durationSec must be stripped post-resolve');
        expect(m['reps'], 18);
      }
    });

    test('Handstand Hold + reps stuffed (no duration) → still timed (library)',
        () async {
      final date = DateTime(2026, 5, 6);
      // Inverse drift: a timed exercise with reps stuffed and no duration.
      // Old data-shape inference would say bodyweight_reps. Library wins.
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Handstand Hold',
        sets: const [
          ExerciseSet(weightKg: 0, reps: 30, durationSec: null),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final keys = box.keys
          .where((k) => k.toString().startsWith('exlog_'))
          .toList();
      expect(keys, hasLength(1));
      final row = box.get(keys.first) as Map;

      expect(row['logging_type'], 'timed',
          reason: 'library says timed — must override data shape');
      // Stripped per-set: weight + reps both cleared for timed.
      final sets = row['sets'] as List;
      expect(sets, hasLength(1));
      final s = sets.first as Map;
      expect(s['weight_kg'], 0.0);
      expect(s['reps'], 0,
          reason: 'reps stripped on timed-resolved write');
    });

    test('Jump Rope timed write — durationSec preserved on per-set', () async {
      final date = DateTime(2026, 5, 6);
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Jump Rope',
        sets: const [
          ExerciseSet(weightKg: 0, reps: 0, durationSec: 60),
          ExerciseSet(weightKg: 0, reps: 0, durationSec: 60),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final row = box.get(
              box.keys.firstWhere((k) => k.toString().startsWith('exlog_')))
          as Map;
      expect(row['logging_type'], 'timed');
      final sets = row['sets'] as List;
      expect((sets.first as Map)['duration_sec'], 60,
          reason: 'durationSec preserved for timed exercises');
    });

    test('Custom exercise (not in library) — falls back to data-shape inference',
        () async {
      final date = DateTime(2026, 5, 6);
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'My Weird Custom Exercise',
        sets: const [
          ExerciseSet(weightKg: 50, reps: 10),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final row = box.get(
              box.keys.firstWhere((k) => k.toString().startsWith('exlog_')))
          as Map;
      // Data-shape inference: weight>0 → weight_reps.
      expect(row['logging_type'], 'weight_reps');
    });
  });
}
