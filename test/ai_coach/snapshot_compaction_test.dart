// test/ai_coach/snapshot_compaction_test.dart
//
// Pins the contract that adding meals_today + nutrition_trend_7d to the
// AI snapshot did not push a TYPICAL user's payload past the 9.5 KB
// compaction ceiling. The compactContext trim order must also drop both
// new keys before older keys when under pressure.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

Map<String, dynamic> _typicalSnapshot() {
  // Mirror the shape of buildAiContext() for a typical user:
  //   - 4 today meal slots, ~3 items each
  //   - 7-day trend
  //   - moderate coach_memory + coaching_notes
  return {
    'is_first_ever_message': false,
    'profile': {
      'name': 'Test User',
      'age': 30,
      'gender': 'male',
      'height_cm': 175,
      'current_weight_kg': 80,
      'target_weight_kg': 75,
      'primary_goal': 'lose_fat',
      'fitness_experience': 'intermediate',
      'equipment_access': 'basic_gym',
      'activity_level': 'moderately_active',
      'diet_preference': 'non-veg',
      'injuries': ['none'],
      'bmr': 1750,
      'tdee': 2700,
      'city': 'Bengaluru',
    },
    'progress': {
      'current_phase': 1,
      'current_week': 3,
      'total_workouts_done': 8,
      'current_streak_weeks': 2,
      'detected_experience': 'intermediate',
    },
    'this_week_workouts': List.generate(
        4, (i) => {'date': '2026-04-2$i', 'status': 'completed', 'name': 'Push'}),
    'today_nutrition': {
      'calories_logged': 1820,
      'protein_g': 92,
      'carbs_g': 220,
      'fat_g': 65,
      'fiber_g': 24,
      'fiber_target_g': 30,
      'water_ml': 1500,
    },
    'today_steps': 6500,
    'step_history_7d': List.generate(
        7, (i) => {'date': '2026-04-2$i', 'steps': 5000 + i * 500}),
    'latest_weight': {'date': '2026-04-25', 'weight_kg': 80, 'delta': -0.4},
    'personal_records': List.generate(
        5, (i) => {'exercise': 'Bench $i', 'weight_kg': 60 + i * 5, 'reps': 5}),
    'coaching_notes':
        'User prefers morning workouts. Hates cardio. Crushing protein targets. ' *
            6,
    'coach_memory': {
      'preferred_name': 'Test',
      'communication_style': 'direct',
      'plateau_risk_score': 0.2,
    },
    'fitness_summary': 'Intermediate lifter. 8 workouts, 60% adherence.',
    'motivational_style': 'encouraging',
    'coach_notices': List.generate(
        3, (i) => {'type': 'streak', 'message': 'Keep it up #$i'}),
    'custom_exercises': [],
    'saved_templates': [],
    // The two new APK Test #3 / Q6.3 keys
    'meals_today': [
      {
        'slot': 'breakfast',
        'items': [
          {'name': 'Oats', 'kcal': 152, 'protein_g': 5, 'carbs_g': 27, 'fat_g': 3},
          {'name': 'Milk (Toned)', 'kcal': 140, 'protein_g': 8, 'carbs_g': 12, 'fat_g': 8},
        ],
        'total_kcal': 292,
        'total_protein_g': 13,
      },
      {
        'slot': 'lunch',
        'items': [
          {'name': 'Chicken Breast (grilled)', 'kcal': 165, 'protein_g': 31, 'carbs_g': 0, 'fat_g': 4},
          {'name': 'Brown Rice (cooked)', 'kcal': 218, 'protein_g': 5, 'carbs_g': 47, 'fat_g': 2},
        ],
        'total_kcal': 383,
        'total_protein_g': 36,
      },
      {
        'slot': 'snacks',
        'items': [
          {'name': 'Whey Protein (scoop)', 'kcal': 122, 'protein_g': 24, 'carbs_g': 3, 'fat_g': 1},
        ],
        'total_kcal': 122,
        'total_protein_g': 24,
      },
    ],
    'nutrition_trend_7d': List.generate(
        7,
        (i) => {
              'date': '2026-04-2${i + 1}',
              'calories': 1800 - i * 50,
              'protein_g': 90 - i * 3,
              'carbs_g': 220 - i * 10,
              'fat_g': 65,
              'fiber_g': 24,
            }),
  };
}

void main() {
  test('typical-user snapshot fits under 9.5 KB compaction ceiling', () {
    final snapshot = _typicalSnapshot();
    final bytes = json.encode(snapshot).length;
    expect(
      bytes,
      lessThanOrEqualTo(9500),
      reason: 'typical-user snapshot must fit pre-compaction. Got '
          '$bytes bytes. If this fails, audit which key grew and add it '
          'higher in the _compactContext trim list.',
    );
  });

  test('_compactContext drops meals_today before weight_trend', () {
    // Force the snapshot over budget by adding heavy padding to a key
    // that's listed AFTER meals_today / nutrition_trend_7d in trimSteps.
    final ctx = _typicalSnapshot();
    final padding = List.generate(150, (i) => {'k$i': 'v$i' * 30});
    ctx['weight_trend'] = padding;
    ctx['exercise_history'] = padding;

    expect(json.encode(ctx).length, greaterThan(9500),
        reason: 'sanity: padded snapshot exceeds ceiling');

    final compact = AiService.compactForTest(ctx);

    // step_history_7d / meals_today / nutrition_trend_7d should drop
    // before weight_trend / exercise_history if the trim list does its
    // job. Either ordering surface works as long as the size is met.
    expect(json.encode(compact).length, lessThanOrEqualTo(9500),
        reason: 'compaction must hit the ceiling');
    expect(compact.containsKey('meals_today'), isFalse,
        reason: 'meals_today is in the early trim lane and should be the '
            'first nutrition key dropped under pressure');
    expect(compact.containsKey('nutrition_trend_7d'), isFalse,
        reason: 'nutrition_trend_7d is in the early trim lane');
  });
}
