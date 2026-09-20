// test/contracts/today_workout_reads_logged_contract_test.dart
//
// Contract test for Bug a13a01.
//
// today_workout.exercises and yesterday_workout.exercises in the AI snapshot
// MUST reflect what was actually LOGGED (exlog_* rows), NOT the planned
// schedule_<date> entry. The planned entry's exercises[] is the prescribed
// list at schedule-generation time and stays the full N regardless of how
// many exercises the user actually completes.
//
// Founder direction 2026-05-12 (locked): Option A — logged only, no plan
// fallback. No "you skipped X" coaching for now.
//
// Writers covered:
//   - WorkoutScheduleService writes schedule_<date> with full planned list
//   - WorkoutWriteService.logExercise writes exlog_* + maintains
//     exercise_log_index_<date>
//
// Reader being pinned:
//   - AiCoachRepository._getTodayWorkout / _getYesterdayWorkout, surfaced
//     via the public buildAiContext() snapshot under keys today_workout +
//     yesterday_workout.
//
// Hive setup uses setUpHiveForTests (test/helpers/hive_test_setup.dart) which
// opens BOTH shared boxes (configBox needed by _getSubscriptionState) AND
// the user-scoped workoutBox. wws_test_setup.dart only opens the user-scoped
// boxes and breaks buildAiContext on the configBox read.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('today_workout reads LOGGED, not planned (Bug a13a01)', () {
    test('partial completion — 4 logged of 8 planned → exercises reflects 4',
        () async {
      final today = istDateStr(DateTime.now());
      final box = HiveService.instance.workoutBox;

      // Planned: 8 exercises (the bug — coach was reporting all 8 back even
      // though only 4 were completed).
      await box.put('schedule_$today', {
        'workout_name': 'Pull A',
        'type': 'PULL_A',
        'status': 'completed',
        'exercises': [
          {'name': 'Lat Pulldown'},
          {'name': 'Dumbbell Row'},
          {'name': 'Chin Up'},
          {'name': 'Barbell Bent Over Row'},
          {'name': 'Hanging Leg Raise'},
          {'name': 'Face Pull'},
          {'name': 'Barbell Curl'},
          {'name': 'Dumbbell Curl'},
        ],
      });

      // Logged: only 4 exercises via exlog_* rows + exercise_log_index_*.
      await box.put('exercise_log_index_$today',
          ['exlog_1', 'exlog_2', 'exlog_3', 'exlog_4']);

      await box.put('exlog_1', {
        'exercise_name': 'Lat Pulldown',
        'date': today,
        'sets': [
          {'reps': 10, 'weight_kg': 70.0, 'logged_at_ms': 1},
          {'reps': 10, 'weight_kg': 70.0, 'logged_at_ms': 2},
          {'reps': 8, 'weight_kg': 70.0, 'logged_at_ms': 3},
        ],
        'set_number': 3,
        'reps_completed': 28,
        'weight_kg': 70.0,
        'volume_kg': 1960.0,
        'is_pr': false,
        'logging_type': 'weight_reps',
      });
      await box.put('exlog_2', {
        'exercise_name': 'Dumbbell Row',
        'date': today,
        'sets': [
          {'reps': 10, 'weight_kg': 30.0, 'logged_at_ms': 4},
          {'reps': 10, 'weight_kg': 30.0, 'logged_at_ms': 5},
        ],
        'set_number': 2,
        'reps_completed': 20,
        'weight_kg': 30.0,
        'volume_kg': 600.0,
        'is_pr': false,
        'logging_type': 'weight_reps',
      });
      await box.put('exlog_3', {
        'exercise_name': 'Hanging Leg Raise',
        'date': today,
        'sets': [
          {'reps': 10, 'weight_kg': 0.0, 'logged_at_ms': 6},
        ],
        'set_number': 1,
        'reps_completed': 10,
        'weight_kg': 0.0,
        'volume_kg': 0.0,
        'is_pr': false,
        'logging_type': 'bodyweight_reps',
      });
      await box.put('exlog_4', {
        'exercise_name': 'Concentration Curl',
        'date': today,
        'sets': [
          {'reps': 9, 'weight_kg': 15.0, 'logged_at_ms': 7},
          {'reps': 8, 'weight_kg': 15.0, 'logged_at_ms': 8},
        ],
        'set_number': 2,
        'reps_completed': 17,
        'weight_kg': 15.0,
        'volume_kg': 255.0,
        'is_pr': true,
        'logging_type': 'weight_reps',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final todayWorkout = ctx['today_workout'] as Map?;
      expect(todayWorkout, isNotNull,
          reason: 'buildAiContext must populate today_workout when a '
              'schedule_<today> entry exists');

      final exercises =
          ((todayWorkout!['exercises'] as List?) ?? const []).cast<Map>();

      expect(exercises.length, 4,
          reason:
              'today_workout.exercises must reflect 4 LOGGED exercises, '
              'not 8 planned (Bug a13a01).');
      expect(
        exercises.map((e) => e['name']).toList(),
        ['Lat Pulldown', 'Dumbbell Row', 'Hanging Leg Raise',
         'Concentration Curl'],
        reason: 'names come from exlog rows in index order',
      );

      // type + status still preserved from schedule_<today>.
      expect(todayWorkout['type'], 'PULL_A');
      expect(todayWorkout['status'], 'completed');

      // is_pr from exlog must propagate into the snapshot so the coach
      // can call it out ("PR on Concentration Curl today!").
      final concurl =
          exercises.firstWhere((e) => e['name'] == 'Concentration Curl');
      expect(concurl['is_pr'], true,
          reason: 'PR flag from exlog must propagate to snapshot');
      expect(concurl['sets'], 2,
          reason: 'sets count from logged data, not planned');

      // top_set_weight_kg is OMITTED for non-weighted logging types
      // (bodyweight_reps, timed, cardio) so Gemini doesn't describe a
      // misleading "0 kg top set" on a Hanging Leg Raise.
      final hlr =
          exercises.firstWhere((e) => e['name'] == 'Hanging Leg Raise');
      expect(hlr['logging_type'], 'bodyweight_reps');
      expect(hlr.containsKey('top_set_weight_kg'), isFalse,
          reason: 'omit top_set_weight_kg for non-weighted logging types');

      // ... but present for weighted exercises.
      expect(concurl['logging_type'], 'weight_reps');
      expect(concurl['top_set_weight_kg'], 15.0,
          reason: 'weighted exercise reports max weight across sets');
    });

    test('no logs (rest day / pre-workout) — exercises is empty, no fallback',
        () async {
      final today = istDateStr(DateTime.now());
      final box = HiveService.instance.workoutBox;

      // Schedule exists, but user has not started yet.
      await box.put('schedule_$today', {
        'workout_name': 'Pull A',
        'type': 'PULL_A',
        'status': 'scheduled',
        'exercises': [
          {'name': 'Lat Pulldown'},
          {'name': 'Dumbbell Row'},
        ],
      });
      // No exercise_log_index_<today>. No exlog_* rows.

      final ctx = AiCoachRepository.instance.buildAiContext();
      final todayWorkout = ctx['today_workout'] as Map?;
      expect(todayWorkout, isNotNull,
          reason: 'snapshot still surfaces type+status even when no exercises '
              'logged yet');

      final exercises =
          ((todayWorkout!['exercises'] as List?) ?? const []).cast<Map>();

      expect(exercises, isEmpty,
          reason:
              'no logs = empty exercises list (do NOT fall back to plan); '
              'Option A locked with founder 2026-05-12.');
      expect(todayWorkout['status'], 'scheduled',
          reason: 'status from schedule_<today> still preserved');
    });

    test('yesterday_workout reads LOGGED exercises symmetrically', () async {
      final yesterday =
          istDateStr(DateTime.now().subtract(const Duration(days: 1)));
      final box = HiveService.instance.workoutBox;

      // Yesterday planned 5, logged 2.
      await box.put('schedule_$yesterday', {
        'workout_name': 'Push A',
        'type': 'PUSH_A',
        'status': 'completed',
        'exercises': [
          {'name': 'Bench Press'},
          {'name': 'Overhead Press'},
          {'name': 'Incline DB'},
          {'name': 'Tricep Pushdown'},
          {'name': 'Lateral Raise'},
        ],
      });
      await box.put('exercise_log_index_$yesterday',
          ['exlog_y1', 'exlog_y2']);
      await box.put('exlog_y1', {
        'exercise_name': 'Bench Press',
        'date': yesterday,
        'sets': [
          {'reps': 8, 'weight_kg': 60.0, 'logged_at_ms': 1},
        ],
        'set_number': 1,
        'reps_completed': 8,
        'weight_kg': 60.0,
        'volume_kg': 480.0,
        'is_pr': false,
        'logging_type': 'weight_reps',
      });
      await box.put('exlog_y2', {
        'exercise_name': 'Overhead Press',
        'date': yesterday,
        'sets': [
          {'reps': 6, 'weight_kg': 40.0, 'logged_at_ms': 2},
        ],
        'set_number': 1,
        'reps_completed': 6,
        'weight_kg': 40.0,
        'volume_kg': 240.0,
        'is_pr': false,
        'logging_type': 'weight_reps',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final yesterdayWorkout = ctx['yesterday_workout'] as Map?;
      expect(yesterdayWorkout, isNotNull,
          reason:
              'yesterday_workout must populate when a schedule + logs exist');
      final exs = ((yesterdayWorkout!['exercises'] as List?) ?? const [])
          .cast<Map>();
      expect(exs.length, 2,
          reason: 'yesterday_workout must also be LOGGED-only (symmetric)');
      expect(
        exs.map((e) => e['name']).toList(),
        ['Bench Press', 'Overhead Press'],
        reason: 'in logged order, not planned order',
      );
      expect(yesterdayWorkout['type'], 'PUSH_A');
      expect(yesterdayWorkout['status'], 'completed');
    });
  });
}
