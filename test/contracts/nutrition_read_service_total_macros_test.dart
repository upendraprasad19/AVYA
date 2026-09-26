// Contract test for OI-02 (closes-diagnose: 2026-05-17-oi-02-read-services).
//
// Pins `NutritionReadService.totalMacrosForDate` and
// `.totalMacrosFromItems` semantics. Atwater fallback is mirrored from
// `FoodItem.kcalWithFallback`; this test fails if either side drifts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDownAll(() async {
    await tearDownHiveForTests(tempDir);
  });

  tearDown(() async {
    await HiveService.instance.nutritionBox.clear();
  });

  group('NutritionReadService.totalMacrosForDate', () {
    test('sums every nlog_* row for the matching date', () async {
      await HiveService.instance.nutritionBox.put('nlog_1', {
        'date': '2026-05-17',
        'meal_type': 'breakfast',
        'total_calories': 400,
        'total_protein': 25,
        'total_carbs': 50,
        'total_fat': 10,
        'total_fiber': 8,
      });
      await HiveService.instance.nutritionBox.put('nlog_2', {
        'date': '2026-05-17',
        'meal_type': 'lunch',
        'total_calories': 600,
        'total_protein': 35,
        'total_carbs': 80,
        'total_fat': 15,
        'total_fiber': 12,
      });

      final totals = NutritionReadService.instance
          .totalMacrosForDate(DateTime(2026, 5, 17));
      expect(totals['calories'], 1000);
      expect(totals['protein'], 60);
      expect(totals['carbs'], 130);
      expect(totals['fat'], 25);
      expect(totals['fiber'], 20);
    });

    test('excludes saved-meal templates from the sum', () async {
      await HiveService.instance.nutritionBox.put('nlog_meal', {
        'date': '2026-05-17',
        'total_calories': 300,
        'total_protein': 20,
        'is_saved_meal': true,
      });
      await HiveService.instance.nutritionBox.put('nlog_real', {
        'date': '2026-05-17',
        'total_calories': 500,
        'total_protein': 30,
      });

      final totals = NutritionReadService.instance
          .totalMacrosForDate(DateTime(2026, 5, 17));
      expect(totals['calories'], 500);
      expect(totals['protein'], 30);
    });

    test('returns zeros when no rows match', () async {
      final totals = NutritionReadService.instance
          .totalMacrosForDate(DateTime(2026, 5, 17));
      expect(totals['calories'], 0);
      expect(totals['protein'], 0);
    });
  });

  group('NutritionReadService.totalMacrosFromItems', () {
    test('applies Atwater fallback per item when calories=0', () {
      final totals = NutritionReadService.totalMacrosFromItems([
        // Atwater: 4*20 + 4*30 + 9*10 = 80+120+90 = 290
        {'calories': 0, 'protein': 20, 'carbs': 30, 'fat': 10, 'fiber': 5},
        // Direct calories (non-zero overrides Atwater)
        {'calories': 100, 'protein': 5, 'carbs': 15, 'fat': 2, 'fiber': 1},
      ]);
      expect(totals['calories'], 390);
      expect(totals['protein'], 25);
      expect(totals['carbs'], 45);
      expect(totals['fat'], 12);
      expect(totals['fiber'], 6);
    });

    test('returns zeros for empty list', () {
      final totals = NutritionReadService.totalMacrosFromItems(const []);
      expect(totals['calories'], 0);
      expect(totals['protein'], 0);
    });

    test('ignores non-Map entries gracefully', () {
      final totals = NutritionReadService.totalMacrosFromItems([
        {'calories': 100, 'protein': 10, 'carbs': 0, 'fat': 0, 'fiber': 0},
        null,
        'garbage',
        42,
      ]);
      expect(totals['calories'], 100);
      expect(totals['protein'], 10);
    });
  });
}
