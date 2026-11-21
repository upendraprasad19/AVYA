// CONTRACT TEST — AI snapshot cardio fields (OI-389 D4, diagnose e7240a).
//
// The coach's `today_workout` / `yesterday_workout.exercises[]` rows gain, for a
// cardio or distance row, `duration_min` (one decimal: 750 s → 12.5, as the
// screen shows) and `distance_km`, plus `top_set_weight_kg` for distance; each
// omitted when 0. Values come from WorkoutReadService.aggregateDurationSeconds /
// aggregateDistanceKm, so a restore-shaped row (top-level totals only) counts.
// Kill switch `disable_snapshot_cardio_fields` (configBox) → the pre-D4 map,
// byte-identical.
//
// T17: switch ON → old map exactly; one decimal; 0 omitted.
// T27: switch unset (default) → fields present, end to end through buildAiContext.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';

import '../helpers/hive_test_setup.dart';

const _flag = 'disable_snapshot_cardio_fields';

Map<String, dynamic> _cardio() => {
      'exercise_name': 'Treadmill Run',
      'logging_type': 'cardio',
      'is_pr': false,
      'sets': [
        {'duration_sec': 450, 'distance_km': 1.2, 'logged_at_ms': 1},
        {'duration_sec': 300, 'distance_km': 0.8, 'logged_at_ms': 2},
      ],
    };

Map<String, dynamic> _distance() => {
      'exercise_name': 'Farmers Carry',
      'logging_type': 'distance',
      'is_pr': false,
      'sets': [
        {'distance_km': 0.04, 'weight_kg': 40.0, 'logged_at_ms': 1},
      ],
    };

Map<String, dynamic> _row(Map<String, dynamic> log, {required bool on}) =>
    AiSnapshotBuilder.snapshotLoggedExercise(log, cardioFields: on);

void main() {
  group('T17 snapshotLoggedExercise (pure)', () {
    test('switch ON (cardioFields false) returns the pre-D4 map byte-identically',
        () {
      expect(_row(_cardio(), on: false), equals({
        'name': 'Treadmill Run',
        'sets': 2,
        'reps_total': 0,
        'logging_type': 'cardio',
        'is_pr': false,
      }));
      expect(_row(_distance(), on: false), equals({
        'name': 'Farmers Carry',
        'sets': 1,
        'reps_total': 0,
        'logging_type': 'distance',
        'is_pr': false,
      }));
    });

    test('cardio: 750 s → duration_min 12.5 (one decimal), km summed', () {
      final r = _row(_cardio(), on: true);
      expect(r['duration_min'], 12.5);
      expect(r['distance_km'], 2.0);
      expect(r.containsKey('top_set_weight_kg'), isFalse);
    });

    test('20 s → duration_min 0.3 (not rounded to whole minutes)', () {
      final r = _row({
        'exercise_name': 'Jump Rope',
        'logging_type': 'cardio',
        'sets': [
          {'duration_sec': 20},
        ],
      }, on: true);
      expect(r['duration_min'], 0.3);
      expect(r.containsKey('distance_km'), isFalse);
    });

    test('a cardio row with no duration and no km omits both (no zeros)', () {
      final r = _row({
        'exercise_name': 'Bike',
        'logging_type': 'cardio',
        'sets': [
          {'duration_sec': 0},
        ],
      }, on: true);
      expect(r.containsKey('duration_min'), isFalse);
      expect(r.containsKey('distance_km'), isFalse);
    });

    test('distance: km and top_set_weight_kg present', () {
      final r = _row(_distance(), on: true);
      expect(r['distance_km'], 0.04);
      expect(r['top_set_weight_kg'], 40.0);
      expect(r.containsKey('duration_min'), isFalse);
    });

    test('restore-shaped row (top-level totals only) reads through the reader',
        () {
      final r = _row({
        'exercise_name': 'Treadmill Run',
        'logging_type': 'cardio',
        'duration_seconds': 600,
        'distance_km': 3.0,
        'sets': [<String, dynamic>{}],
      }, on: true);
      expect(r['duration_min'], 10.0);
      expect(r['distance_km'], 3.0);
    });

    test('a legacy sets_detail-only distance row: sets, km and weight agree',
        () {
      final r = _row({
        'exercise_name': 'Farmers Carry',
        'logging_type': 'distance',
        'sets': <dynamic>[],
        'sets_detail': [
          {'distance_km': 0.04, 'weight_kg': 40.0},
          {'distance_km': 0.04, 'weight_kg': 45.0},
        ],
      }, on: true);
      expect(r['sets'], 2);
      expect(r['distance_km'], 0.08);
      expect(r['top_set_weight_kg'], 45.0);
    });

    test('the switch reads only a literal true (a string leaves fields on)',
        () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final box = HiveService.instance.workoutBox;
      final today = istDateStr(DateTime.now());
      await box.put('schedule_$today', {'type': 'CARDIO', 'status': 'pending'});
      await box.put('exercise_log_index_$today', ['exlog_run_today']);
      await box.put('exlog_run_today', {..._cardio(), 'date': today});
      await HiveService.instance.configBox.put(_flag, 'true');
      final tw = AiCoachRepository.instance.buildAiContext()['today_workout'];
      final ex = ((tw as Map)['exercises'] as List).first as Map;
      expect(ex['duration_min'], 12.5);
    });

    test('weight_reps rows are unchanged by the switch', () {
      final log = {
        'exercise_name': 'Bench Press',
        'logging_type': 'weight_reps',
        'is_pr': true,
        'sets': [
          {'reps': 8, 'weight_kg': 60.0},
          {'reps': 6, 'weight_kg': 65.0},
        ],
      };
      expect(_row(log, on: true), equals(_row(log, on: false)));
      expect(_row(log, on: true)['top_set_weight_kg'], 65.0);
    });
  });

  group('buildAiContext (end to end through configBox)', () {
    late Directory tempDir;
    String today() => istDateStr(DateTime.now());

    setUp(() async {
      tempDir = await setUpHiveForTests();
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_${today()}', {
        'type': 'CARDIO',
        'status': 'pending',
        'exercises': [
          {'name': 'Treadmill Run'},
        ],
      });
      await box.put('exercise_log_index_${today()}', ['exlog_run_today']);
      await box.put('exlog_run_today', {..._cardio(), 'date': today()});
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    Map firstExercise() {
      final tw = AiCoachRepository.instance.buildAiContext()['today_workout'];
      return ((tw as Map)['exercises'] as List).first as Map;
    }

    test('T27 switch unset (default) → duration_min and distance_km present',
        () {
      final ex = firstExercise();
      expect(ex['duration_min'], 12.5);
      expect(ex['distance_km'], 2.0);
    });

    test('T17 switch true → the coach sees the pre-D4 row', () async {
      await HiveService.instance.configBox.put(_flag, true);
      final ex = firstExercise();
      expect(ex.containsKey('duration_min'), isFalse);
      expect(ex.containsKey('distance_km'), isFalse);
      expect(ex['reps_total'], 0);
    });
  });
}
