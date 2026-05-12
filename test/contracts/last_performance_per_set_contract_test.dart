// test/contracts/last_performance_per_set_contract_test.dart
//
// Contract: last_performance_per_set
// Writer: WorkoutWriteService.logExercise — stores aggregates AND per-set array.
//   - log['reps_completed'] = SUM of per-set reps (workout_write_service.dart:134,172)
//   - log['weight_kg']      = MAX across per-set weights (workout_write_service.dart:135-136,173)
//   - log['sets']           = [{weight_kg, reps, ...}, ...] per-set array (line 170)
// Reader: train_provider._getLastPerformance — must read FIRST SET values
//   from log['sets'][0], NOT the top-level aggregates. Top-level fields are
//   workout aggregates and would mis-pre-fill the active workout UI.
//
// Bug a8f1c2 (APK Test #15.3): reader was treating `reps_completed` (sum)
// as a per-set value. For a 7-set Hanging Leg Raise session [10,15,10,15,10,10,15],
// reps_completed=85 pre-filled into every set of the next session.
//
// This contract pins the SEMANTICS (per-set vs aggregate), filling the
// gap CLAUDE.md §15 left when it pinned only field PRESENCE.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('lastPerformanceProvider — per-set semantics contract', () {
    test(
        'modern exlog with sets[] returns FIRST SET reps/weight, '
        'not summed reps_completed / max weight_kg', () async {
      // Arrange: write a 7-set Hanging Leg Raise log shaped like the
      // founder's 2026-05-07 session that triggered bug a8f1c2.
      // Per-set reps: [10, 15, 10, 15, 10, 10, 15] → sum 85.
      // Per-set weight: all 0 (bodyweight).
      const exerciseName = 'Hanging Leg Raise';
      const dateStr = '2026-05-07';
      final perSetReps = [10, 15, 10, 15, 10, 10, 15];
      final sumReps = perSetReps.reduce((a, b) => a + b); // 85
      final sets = perSetReps
          .map((r) => <String, dynamic>{
                'weight_kg': 0.0,
                'reps': r,
                'logged_at_ms': DateTime.now().millisecondsSinceEpoch,
              })
          .toList();

      final exlogKey = 'exlog_${dateStr}_hanging_leg_raise';
      await HiveService.instance.workoutBox.put(exlogKey, {
        'type': 'exercise_log',
        'exercise_name': exerciseName,
        'date': dateStr,
        'sets': sets,
        'set_number': perSetReps.length,
        'reps_completed': sumReps, // 85 — SUM (writer's intended aggregate)
        'weight_kg': 0.0, // MAX across sets
        'volume_kg': 0.0,
        'logging_type': 'bodyweight_reps',
        'is_pr': false,
        'source': 'test',
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
      await HiveService.instance.workoutBox.put(
        'exercise_log_index_$dateStr',
        [exlogKey],
      );

      // Act
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final lastPerf =
          container.read(lastPerformanceProvider(exerciseName));

      // Assert: pre-fill should be 10 (first set's reps), not 85 (sum).
      expect(
        lastPerf.lastReps,
        equals(10),
        reason:
            'Reader must extract first-set reps from log[\'sets\'][0], '
            'not the top-level reps_completed (which is the SUM across sets). '
            'Pre-bug a8f1c2 fix this returned 85 — the sum — and the active '
            'workout UI pre-filled 85 into every set of the next session.',
      );
      expect(
        lastPerf.lastWeight,
        equals(0.0),
        reason:
            'Reader must extract first-set weight_kg from log[\'sets\'][0], '
            'not the top-level weight_kg (which is the MAX across sets).',
      );
    });

    test(
        'legacy exlog WITHOUT sets[] array falls back to null '
        '(no pre-fill from stale aggregates)', () async {
      // Arrange: pre-Test-#6 schema — flat aggregates only, no per-set
      // array. This is what existing user devices look like for any
      // exlog row written before the WorkoutWriteService rewrite shipped.
      const exerciseName = 'Push Up';
      const dateStr = '2026-04-15';
      final exlogKey = 'exlog_${dateStr}_push_up';
      await HiveService.instance.workoutBox.put(exlogKey, {
        'type': 'exercise_log',
        'exercise_name': exerciseName,
        'date': dateStr,
        // NB: no 'sets' key
        'reps_completed': 40, // legacy: this WAS per-set ... but we cannot
                              // tell without the per-set array, so reader
                              // must conservatively return null.
        'weight_kg': 0.0,
        'logging_type': 'bodyweight_reps',
      });

      // Act
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final lastPerf =
          container.read(lastPerformanceProvider(exerciseName));

      // Assert: null fall-through is safer than pre-filling an
      // ambiguous value. The UI will show empty input boxes
      // (or fall through to the prescribed rep range midpoint).
      expect(
        lastPerf.lastReps,
        isNull,
        reason:
            'Legacy rows lack sets[] — the top-level reps_completed could '
            'be either per-set (pre-Test-#6) or summed (post-Test-#6). '
            'Reader must return null to avoid surfacing the wrong number.',
      );
      expect(
        lastPerf.lastWeight,
        isNull,
        reason:
            'Same as reps: top-level weight_kg ambiguity in legacy rows '
            'forces a null fallback.',
      );
    });
  });
}
