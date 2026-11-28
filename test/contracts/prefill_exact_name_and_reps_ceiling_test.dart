// BEHAVIORAL CONTRACT TEST — diagnose 7c3e91 (prefill borrowed history / stray reps).
//
// Reader: train_provider `_getLastPerformance` (first set of the latest
// `exlog_*` row for the name) + `exerciseHistoryProvider`, both through
// `WorkoutReadService.logsForExercise`. Writer of the rows: `logExercise`.
//
// Bug 1: `logsForExercise` matched any name of 6+ characters that CONTAINS the
// asked name, so "Push Up to Side Plank" took the history of "Push Up" (50
// reps) as its own. The two providers now ask `exactNameOnly: true`.
// Bug 2: one stray stored value (a test log of 110 kg x 35) was prefilled into
// every later session. `prefillReps` ignores a value above twice the plan's
// top reps.
//
// MUTATIONS: drop `exactNameOnly: true` in `_getLastPerformance` -> the borrowed
// -history test fails; change `2 * top` to `20 * top` in `prefillReps` -> the
// ceiling table fails.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';

import '../helpers/hive_test_setup.dart';

Future<void> _putLog(String key, String name, String date, int reps,
    {double kg = 0, String type = 'bodyweight_reps'}) async {
  await HiveService.instance.workoutBox.put(key, {
    'exercise_name': name,
    'date': date,
    'sets': [
      {'weight_kg': kg, 'reps': reps, 'logged_at_ms': 1}
    ],
    'set_number': 1,
    'reps_completed': reps,
    'weight_kg': kg,
    'logging_type': type,
    'updated_at_ms': 1,
  });
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('exact-name prefill', () {
    test('"Push Up to Side Plank" does NOT borrow "Push Up" history', () async {
      await _putLog('exlog_2026-05-06_a', 'Push Up', '2026-05-06', 50);
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(c.read(lastPerformanceProvider('Push Up to Side Plank')).lastReps,
          isNull,
          reason: 'a different exercise whose name contains "Push Up"');
      // The mirror: the real exercise still finds its own log.
      expect(c.read(lastPerformanceProvider('Push Up')).lastReps, 50);
    });

    test('the mirror: Push Up does not borrow the longer name either', () async {
      await _putLog(
          'exlog_2026-05-06_b', 'Push Up to Side Plank', '2026-05-06', 12);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(lastPerformanceProvider('Push Up')).lastReps, isNull);
      expect(
          c.read(lastPerformanceProvider('Push Up to Side Plank')).lastReps, 12);
    });

    test('case and edge spaces still match the same exercise', () async {
      await _putLog('exlog_2026-05-06_c', 'Barbell Back Squat', '2026-05-06', 8,
          kg: 40, type: 'weight_reps');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
          c.read(lastPerformanceProvider(' barbell back squat ')).lastReps, 8);
    });

    test('the weight sparkline history is exact too', () async {
      await _putLog('exlog_2026-05-06_d', 'Dumbbell Curl', '2026-05-06', 10,
          kg: 12, type: 'weight_reps');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(exerciseHistoryProvider('Dumbbell Curl (Seated)')), isEmpty);
      expect(c.read(exerciseHistoryProvider('Dumbbell Curl')), [12.0]);
    });

    test('the default stays fuzzy for any other caller (unchanged behavior)',
        () async {
      await _putLog('exlog_2026-05-06_e', 'Push Up', '2026-05-06', 50);
      expect(
          WorkoutReadService.instance
              .logsForExercise('Push Up to Side Plank')
              .length,
          1);
      expect(
          WorkoutReadService.instance
              .logsForExercise('Push Up to Side Plank', exactNameOnly: true),
          isEmpty);
    });
  });

  group('triedRepsText (the TRY line follows the same ceiling)', () {
    String go(int? last, String plan, {String type = 'weight_reps'}) =>
        triedRepsText(lastReps: last, planReps: plan, loggingType: type);

    test('a stray 35 on a plan of 8-12 shows the plan text, not 35', () {
      expect(go(35, '8-12'), '8-12');
    });
    test('an ordinary last value is shown', () {
      expect(go(10, '8-12'), '10');
    });
    test('no history shows the plan text (unchanged)', () {
      expect(go(null, '8-12'), '8-12');
    });
    test('a plan with no number keeps the stored value', () {
      expect(go(35, 'AMRAP'), '35');
    });
  });

  group('prefillReps ceiling (twice the plan top)', () {
    int go(int? last, String plan, {String type = 'weight_reps'}) => prefillReps(
        lastReps: last, planReps: plan, loggingType: type, fallback: 8);

    test('a stray 35 on a plan of 8 is ignored; the plan value is used', () {
      expect(go(35, '8'), 8);
    });
    test('the boundary: exactly twice the top is kept, one more is not', () {
      expect(go(16, '8'), 16);
      expect(go(17, '8'), 8);
      expect(go(24, '8-12'), 24);
      expect(go(25, '8-12'), 8);
    });
    test('an ordinary last value is kept', () {
      expect(go(10, '8-12'), 10);
      expect(go(8, '8'), 8);
    });
    test('no history or zero uses the plan value', () {
      expect(go(null, '8'), 8);
      expect(go(0, '8'), 8);
    });
    test('a plan with no number has no ceiling (AMRAP, empty)', () {
      expect(go(35, 'AMRAP'), 35);
      expect(go(35, ''), 35);
    });
    test('types whose reps are not a rep count are never capped', () {
      expect(go(300, '8', type: 'timed'), 300);
      expect(go(300, '8', type: 'cardio'), 300);
    });
    test('bodyweight and weighted-bodyweight rows are capped the same way', () {
      expect(go(50, '8', type: 'bodyweight_reps'), 8);
      expect(go(50, '8', type: 'weighted_bodyweight'), 8);
    });
  });
}
