// test/ai_coach/nutrition_trend_7d_snapshot_test.dart
//
// Validates the new _getNutritionTrend7d snapshot helper. Writes nlog_*
// rows spanning 7 days (with one empty day in the middle) and asserts
// the helper returns 7 entries newest-first with zero-fill on the empty
// day.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

import '../helpers/hive_test_setup.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('_getNutritionTrend7d returns 7 entries newest-first', () async {
    final box = HiveService.instance.nutritionBox;
    final now = DateTime.now();

    // Day 0 (today): two rows
    await box.put('nlog_today_1', {
      'id': 'nlog_today_1',
      'date': _ymd(now),
      'meal_type': 'breakfast',
      'total_calories': 300,
      'total_protein': 12,
      'total_carbs': 50,
      'total_fat': 10,
      'total_fiber': 5,
    });
    await box.put('nlog_today_2', {
      'id': 'nlog_today_2',
      'date': _ymd(now),
      'meal_type': 'lunch',
      'total_calories': 600,
      'total_protein': 35,
      'total_carbs': 70,
      'total_fat': 15,
      'total_fiber': 8,
    });

    // Day 1 (yesterday): one row
    await box.put('nlog_yest', {
      'id': 'nlog_yest',
      'date': _ymd(now.subtract(const Duration(days: 1))),
      'meal_type': 'dinner',
      'total_calories': 800,
      'total_protein': 40,
      'total_carbs': 90,
      'total_fat': 20,
      'total_fiber': 10,
    });

    // Day 3: nothing (gap)
    // Day 6 (oldest in window): one row
    await box.put('nlog_old', {
      'id': 'nlog_old',
      'date': _ymd(now.subtract(const Duration(days: 6))),
      'meal_type': 'lunch',
      'total_calories': 500,
      'total_protein': 25,
      'total_carbs': 60,
      'total_fat': 12,
      'total_fiber': 7,
    });

    final trend = AiCoachRepository.instance.nutritionTrend7dForTest();

    expect(trend.length, equals(7), reason: 'must return 7 days');
    // Newest first: trend[0].date == today
    expect(trend[0]['date'], equals(_ymd(now)));
    expect(trend[0]['calories'], equals(900));
    expect(trend[0]['protein_g'], equals(47));

    // Day 1 sums correctly
    expect(trend[1]['date'], equals(_ymd(now.subtract(const Duration(days: 1)))));
    expect(trend[1]['calories'], equals(800));

    // Gap day (index 3) zero-filled
    expect(trend[3]['calories'], equals(0));
    expect(trend[3]['protein_g'], equals(0));

    // Oldest entry
    expect(trend[6]['date'], equals(_ymd(now.subtract(const Duration(days: 6)))));
    expect(trend[6]['calories'], equals(500));
  });
}
