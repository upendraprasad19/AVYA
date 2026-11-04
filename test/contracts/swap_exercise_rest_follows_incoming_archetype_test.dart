// OI-456 piece A (docs/plans/2026-11-04-oi456-a-rest-by-type.md, 3.3b).
//
// Before OI-456 every exercise of a day carried the same stamped rest, so a swapped-in
// exercise inheriting the OUTGOING slot's rest (`swap_service.dart`, the `rest_seconds`
// field of the replacement) was consistent. The rest now follows the exercise's
// archetype (H 150, M 120, I 75, B 60), so a swap across archetypes would keep the
// wrong type's rest and the day's time estimate would drift from what was planned.
//
// Writer: SwapService.swapExerciseInDay (the replacement map). Reader: the schedule
// row in workoutBox, then SessionBudget.estimateDaySecondsFromPlanDay (Train / Home).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';

import '../helpers/hive_test_setup.dart';

const date = '2099-01-06';

Map<String, dynamic> lib(String id, String type, String reps, {String logging = 'weight_reps'}) => {
      'id': id,
      'name': id,
      'exercise_type': [type],
      'rep_range': reps,
      'logging_type': logging,
      'primary_muscles': ['Chest'],
    };

Map<String, dynamic> planned(String id, int rest) => {
      'exercise_id': id,
      'exercise_name': id,
      'sets': 3,
      'reps': '8',
      'rest_seconds': rest,
      'logging_type': 'weight_reps',
    };

// ignore: deprecated_member_use
SwapService get engine => SwapService.instance;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await setUpHiveForTests();
    SwapService.debugOnPlanPushForTests = () {};
    final ex = HiveService.instance.exerciseBox;
    await ex.put('heavy', lib('heavy', 'compound', '5-8')); // H -> 150
    await ex.put('mid', lib('mid', 'compound', '8-12')); // M -> 120
    await ex.put('iso', lib('iso', 'isolation', '10-15')); // I -> 75
    await ex.put('plank', lib('plank', 'isolation', '30-60', logging: 'timed')); // timed
  });

  tearDown(() async {
    SwapService.debugOnPlanPushForTests = null;
    await tearDownHiveForTests(dir);
  });

  Future<Map<String, dynamic>> swap(String from, String to, List<Map<String, dynamic>> day) async {
    await HiveService.instance.workoutBox.put('schedule_$date', {
      'date': date,
      'type': 'workout',
      'workout_name': 'D',
      'status': 'planned',
      'exercises': day,
    });
    await engine.swapExerciseInDay(date: date, fromExerciseId: from, toExerciseId: to);
    final stored = Map<String, dynamic>.from(HiveService.instance.workoutBox.get('schedule_$date') as Map);
    return Map<String, dynamic>.from((stored['exercises'] as List).first as Map);
  }

  double seconds(Map<String, dynamic> e) =>
      SessionBudget.estimateDaySecondsFromPlanDay({'exercises': [e]}, const {});

  test('a heavy compound swapped for an isolation takes the isolation rest, and back', () async {
    final toIso = await swap('heavy', 'iso', [planned('heavy', 150)]);
    expect(toIso['rest_seconds'], 75, reason: 'not the outgoing slot\'s 150');
    expect(SessionBudget.archetypeOfPlanDayExercise(toIso, const {}), 'I');
    expect(seconds(toIso),
        SessionBudget.exerciseSeconds(archetype: 'I', sets: 3, restSeconds: 75));

    final toHeavy = await swap('iso', 'heavy', [planned('iso', 75)]);
    expect(toHeavy['rest_seconds'], 150, reason: 'not the outgoing slot\'s 75');
    expect(SessionBudget.archetypeOfPlanDayExercise(toHeavy, const {}), 'H');
    expect(toHeavy['rep_range'], '5-8', reason: 'carried, so the estimate derives the same archetype');
    expect(seconds(toHeavy),
        SessionBudget.exerciseSeconds(archetype: 'H', sets: 3, restSeconds: 150));
  });

  test('a compound swapped for another compound takes the incoming compound\'s rest', () async {
    final out = await swap('heavy', 'mid', [planned('heavy', 150)]);
    expect(out['rest_seconds'], 120);
  });

  test('a custom target (exercise_type as a String and as a List) is classified from its own fields', () async {
    final box = HiveService.instance.customBox;
    await box.put('custom_exercise_a', {
      'id': 'custom_a',
      'name': 'Custom A',
      'exercise_type': 'compound', // a String
      'rep_range': '4-6',
      'logging_type': 'weight_reps',
    });
    await box.put('custom_exercise_b', {
      'id': 'custom_b',
      'name': 'Custom B',
      'exercise_type': ['isolation'], // a List
      'rep_range': '12-15',
      'logging_type': 'weight_reps',
    });
    final a = await swap('iso', 'custom_a', [planned('iso', 75)]);
    expect(a['rest_seconds'], 150);
    expect(SessionBudget.archetypeOfPlanDayExercise(a, const {}), 'H',
        reason: 'the stored rep_range keeps a heavy custom heavy in the estimate');
    final b = await swap('heavy', 'custom_b', [planned('heavy', 150)]);
    expect(b['rest_seconds'], 75);
  });

  test('a timed incoming row keeps the inherited rest (only rep-based rows follow the type table)', () async {
    final out = await swap('heavy', 'plank', [planned('heavy', 150)]);
    expect(out['logging_type'], 'timed');
    expect(out['rest_seconds'], 150);
  });
}
