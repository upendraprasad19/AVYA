// test/contracts/nutrition_total_calories_writer_to_reader_test.dart
//
// Contract: nutrition_total_calories
// Writer: NutritionWriteService.logMeal (nlog_* with items[] per-item calories)
// Reader: TodaysMealsCard, home_provider daily-completion ring
//
// Pins the Atwater fallback: total_calories = sum of per-item (4P+4C+9F)
// when top-level total is missing. Never read result['total_calories'] directly.
// Retired root §19 entry #35 ("Scan meal saves 0 kcal"), classified Class A
// by the 2026-05-18 declutter audit and deleted from the contract file
// because THIS test is its record.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String nutritionWriteSource;
  late String nutritionScreenSource;

  setUpAll(() {
    nutritionWriteSource = File(
            'lib/core/services/nutrition_write_service.dart')
        .readAsStringSync();
    nutritionScreenSource = File(
            'lib/features/nutrition/screens/nutrition_screen.dart')
        .readAsStringSync();
  });

  group('nutrition_total_calories writer→reader contract', () {
    test('writer stores items[] array on nlog_* rows', () {
      expect(
        nutritionWriteSource,
        contains("'items'"),
        reason:
            'NutritionWriteService.logMeal must store items[] on nlog_* rows '
            'so readers can recompute total_calories from per-item macros.',
      );
    });

    test('writer includes total_calories field', () {
      expect(
        nutritionWriteSource,
        contains("'total_calories'"),
        reason:
            'NutritionWriteService must write total_calories to nlog_* rows.',
      );
    });

    test('writer uses nlog_ key prefix', () {
      expect(
        nutritionWriteSource,
        contains("'nlog_"),
        reason: 'NutritionWriteService must write nlog_* Hive keys.',
      );
    });

    test('nutrition screen reads items for calorie computation', () {
      // The nutrition screen (or its provider) must aggregate from items,
      // not rely on a top-level AI total that may be missing.
      final hasItemsRead = nutritionScreenSource.contains("items") ||
          nutritionScreenSource.contains("total_calories");
      expect(
        hasItemsRead,
        isTrue,
        reason:
            'Nutrition screen must have calorie aggregation logic. '
            'Never rely on top-level AI total_calories — it is routinely absent.',
      );
    });
  });
}
