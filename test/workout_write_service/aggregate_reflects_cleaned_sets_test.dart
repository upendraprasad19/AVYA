// Regression test for bug e8f95e (2026-09-28): logExercise's top-level
// reps_completed/weight_kg/volume_kg aggregate fields must be computed
// from `cleanedSets` (post logging-type normalization), never from
// `mergedSets` (pre-normalization, raw controller input).
//
// Writer: WorkoutWriteService.logExercise (lib/core/services/
// workout_write_service.dart) — the aggregate computation block, moved
// below cleanedSets derivation as part of this fix.
// Reader: workout_log_exercises cloud table + every UI that renders
// entry['reps_completed'] (receipt card, week summary, PR calc).
//
// Test A reproduces the exact founder-reported shape: a CUSTOM exercise
// ("Single Leg Front Lever" — not in the seeded exerciseBox, so
// _resolveLoggingType falls through to data-shape inference) receiving a
// durationSec that leaked in from the UI bug this batch ALSO fixes
// (exercise_card.dart's _initControllers no longer seeds
// _durationControllers with repsValue — see docs/diagnoses/2026-09-28-
// duration-controller-seeding-leak-e8f95e.md). This test simulates the
// leak still reaching logExercise (as it would from any OTHER caller, or
// before that UI fix existed) and pins that the STORED aggregate always
// agrees with the STORED per-set data — never a stale pre-strip value.
//
// Test B is the golden path: the same exercise with NO leaked duration
// (durationSec omitted) resolves correctly end-to-end.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  final date = DateTime(2026, 9, 28);

  test(
      'a leaked durationSec that mis-resolves logging_type to "timed" must '
      'not leave reps_completed showing the pre-strip reps count', () async {
    final result = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Single Leg Front Lever',
      sets: [
        ExerciseSet(
          weightKg: 0,
          reps: 8,
          durationSec: 8, // the leak this batch's UI fix stops at the source
          loggedAtMs: date.millisecondsSinceEpoch,
        ),
      ],
      source: WriteSource.activeWorkout,
    );

    expect(result.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final key =
        WorkoutWriteService.exlogKey(date, 'Single Leg Front Lever');
    final entry = Map<String, dynamic>.from(box.get(key) as Map);

    // Precondition: confirms the mis-resolution this test is built around
    // actually happens in this harness (custom exercise, data-shape
    // fallback, hasDur=true && !hasWeight → 'timed'). If this ever stops
    // being true (e.g. the customBox-lookup gap tracked on the OI board
    // gets fixed and starts correctly resolving custom exercises some
    // other way), this test's premise needs re-deriving, not silently
    // passing for a different reason.
    expect(entry['logging_type'], 'timed',
        reason: 'precondition: data-shape inference must mis-resolve this '
            'input to "timed" for the assertion below to be testing '
            'anything');

    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.single['reps'], 0,
        reason: 'cleanedSets zeroes reps for a timed-resolved set');
    expect(sets.single['duration_sec'], 8,
        reason: 'cleanedSets preserves durationSec for a timed-resolved set');

    // THE regression assertion. Pre-fix this read 8 (mergedSets.reps,
    // computed BEFORE normalization) while sets[0].reps above already
    // correctly read 0 — the top-level field and the per-set array
    // disagreed about the same log entry.
    expect(entry['reps_completed'], 0,
        reason: 'reps_completed must equal cleanedSets reps (0), matching '
            "what's actually in sets[] — not mergedSets' pre-strip value");
    expect(entry['weight_kg'], 0.0);
    expect(entry['volume_kg'], 0.0);
  });

  test(
      'golden path: the same exercise with no leaked duration resolves to '
      'bodyweight_reps and reps_completed=8 end-to-end', () async {
    final result = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: 'Single Leg Front Lever',
      sets: [
        ExerciseSet(
          weightKg: 0,
          reps: 8,
          durationSec: null,
          loggedAtMs: date.millisecondsSinceEpoch,
        ),
      ],
      source: WriteSource.activeWorkout,
    );

    expect(result.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final key =
        WorkoutWriteService.exlogKey(date, 'Single Leg Front Lever');
    final entry = Map<String, dynamic>.from(box.get(key) as Map);

    expect(entry['logging_type'], 'bodyweight_reps');

    final sets = (entry['sets'] as List).cast<Map>();
    expect(sets.single['reps'], 8);
    expect(sets.single.containsKey('duration_sec'), isFalse,
        reason: 'duration_sec must be stripped for a bodyweight_reps set');

    expect(entry['reps_completed'], 8,
        reason: 'reps_completed must show the real reps count, matching '
            'sets[] and matching the UI (active workout screen showed '
            '"8 reps" correctly — the bug was ONLY in the edit log / '
            'week summary readers of the persisted sets[]/aggregate)');
  });
}
