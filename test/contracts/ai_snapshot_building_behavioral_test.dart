// test/contracts/ai_snapshot_building_behavioral_test.dart
//
// Behavioral contract: ai_snapshot_building
// Writer: lib/features/ai_coach/services/ai_snapshot_builder.dart
//         (_getMealsToday reads nlog_* rows from nutritionBox)
// Reader: AiSnapshotBuilder.buildAiContext() → 'meals_today' key
//         (consumed by ai-proxy Edge Function request body)
//
// Assert: log meals to Hive (past/today dates), then call
// AiSnapshotBuilder.instance.buildAiContext() and verify:
//   - 'meals_today' key is present in the returned map
//   - meals for TODAY are included with correct calorie totals
//   - meals for a past date are NOT included
//   - the 'meals_today' key is never trimmed by trimSnapshotToBudget
//
// This test FAILS if _getMealsToday drifts to read a different Hive key
// or aggregates totals incorrectly.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  String todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  test(
      'buildAiContext() meals_today includes today nlog_ rows with correct calorie total',
      () {
    final box = HiveService.instance.nutritionBox;
    final today = todayStr();

    // Write two breakfast entries for today.
    box.put('nlog_breakfast_1', {
      'id': 'nlog_breakfast_1',
      'date': today,
      'meal_type': 'breakfast',
      'food_name': 'Oats',
      'total_calories': 150,
      'total_protein': 5,
      'total_carbs': 27,
      'total_fat': 3,
    });
    box.put('nlog_breakfast_2', {
      'id': 'nlog_breakfast_2',
      'date': today,
      'meal_type': 'breakfast',
      'food_name': 'Banana',
      'total_calories': 90,
      'total_protein': 1,
      'total_carbs': 23,
      'total_fat': 0,
    });
    // Write one lunch entry for today.
    box.put('nlog_lunch_1', {
      'id': 'nlog_lunch_1',
      'date': today,
      'meal_type': 'lunch',
      'food_name': 'Chicken Breast',
      'total_calories': 165,
      'total_protein': 31,
      'total_carbs': 0,
      'total_fat': 4,
    });

    final context = AiSnapshotBuilder.instance.buildAiContext();

    // The 'meals_today' key must be present (it's in the keep set so it
    // survives trimSnapshotToBudget even on large snapshots).
    expect(context.containsKey('meals_today'), isTrue,
        reason: "'meals_today' key must exist in buildAiContext() output");

    final meals = context['meals_today'] as List;
    expect(meals, isNotEmpty, reason: 'meals_today must not be empty');

    // Breakfast slot: two items, total 240 kcal.
    final breakfast = meals.firstWhere(
      (m) => (m as Map)['slot'] == 'breakfast',
      orElse: () => <String, dynamic>{},
    ) as Map;
    expect(breakfast.isNotEmpty, isTrue, reason: 'breakfast slot must exist');
    expect(breakfast['total_kcal'], equals(240),
        reason: 'breakfast total_kcal should sum 150 + 90 = 240');
    expect(breakfast['total_protein_g'], equals(6),
        reason: 'breakfast total_protein_g should sum 5 + 1 = 6');
    final items = breakfast['items'] as List;
    expect(items.length, equals(2),
        reason: 'breakfast should have 2 items');
    final names = items.map((i) => (i as Map)['name'] as String).toList();
    expect(names, containsAll(['Oats', 'Banana']));

    // Lunch slot: one item, 165 kcal.
    final lunch = meals.firstWhere(
      (m) => (m as Map)['slot'] == 'lunch',
      orElse: () => <String, dynamic>{},
    ) as Map;
    expect(lunch.isNotEmpty, isTrue, reason: 'lunch slot must exist');
    expect(lunch['total_kcal'], equals(165));
    expect(lunch['total_protein_g'], equals(31));
  });

  test('buildAiContext() meals_today excludes nlog_ rows from past dates', () {
    final box = HiveService.instance.nutritionBox;

    // Write a log for a past date — must NOT appear in meals_today.
    box.put('nlog_old', {
      'id': 'nlog_old',
      'date': '2020-01-01',
      'meal_type': 'dinner',
      'food_name': 'Old food',
      'total_calories': 500,
      'total_protein': 20,
      'total_carbs': 60,
      'total_fat': 10,
    });

    final context = AiSnapshotBuilder.instance.buildAiContext();
    final meals = context['meals_today'] as List;
    expect(meals, isEmpty,
        reason: 'meals_today must be empty when only past-date rows exist');
  });

  test('meals_today key is in the trimSnapshotToBudget keep set', () {
    // Build a snapshot that is already under budget with meals_today present,
    // then run trimSnapshotToBudget and confirm meals_today survives.
    final snapshot = <String, dynamic>{
      'meals_today': [
        {'slot': 'breakfast', 'total_kcal': 300, 'items': []}
      ],
      'droppable_field': List.generate(
          500, (i) => 'x' * 20), // large field to trigger trimming
    };

    final trimmed =
        AiSnapshotBuilder.trimSnapshotToBudget(snapshot, budget: 100);
    expect(trimmed.containsKey('meals_today'), isTrue,
        reason: "'meals_today' must survive trimSnapshotToBudget (in keep set)");
  });
}
