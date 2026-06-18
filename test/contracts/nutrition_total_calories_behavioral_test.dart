// Behavioral contract: NutritionWriteService.logMeal → NutritionRepository.dailyMacros
//
// Asserts that the reader sums calories INCLUDING the Atwater fallback
// (4/4/9 kcal per g of protein/carb/fat) for items with kcal=0.
//
// The Atwater calculation is performed at WRITE TIME by NutritionWriteService
// via FoodItem.kcalWithFallback; the reader sums the pre-computed
// `total_calories` field stored in each nlog_* row.
//
// FAILS when: writer drops kcalWithFallback → totalCals from Atwater items
// becomes 0; OR reader stops reading `total_calories`; OR field is renamed.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  group('nutrition_total_calories behavioral contract', () {
    test(
        'dailyMacros sums calories including Atwater fallback for kcal=0 item',
        () async {
      // Item 1: explicit calories=300.
      // Item 2: calories=0, protein=20g, carbs=30g, fat=10g
      //   → Atwater: (4*20) + (4*30) + (9*10) = 80 + 120 + 90 = 290 kcal
      // Expected total = 300 + 290 = 590 kcal
      final testDate = DateTime(2026, 6, 18);

      final result = await NutritionWriteService.instance.logMeal(
        date: testDate,
        mealType: 'lunch',
        items: const [
          FoodItem(
            name: 'Chicken Rice',
            quantityG: 200,
            calories: 300,
            protein: 25,
            carbs: 35,
            fat: 6,
            fiber: 2,
          ),
          FoodItem(
            name: 'Mystery Supplement',
            quantityG: 30,
            calories: 0, // no label kcal — must use Atwater fallback
            protein: 20,
            carbs: 30,
            fat: 10,
            fiber: 0,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );

      expect(result.success, isTrue,
          reason: 'logMeal must succeed to exercise the write→read path');

      final macros = NutritionRepository.instance.dailyMacros(testDate);

      // Atwater: 4*20 + 4*30 + 9*10 = 290; total = 300 + 290 = 590
      expect(macros['calories'], 590.0,
          reason:
              'reader must sum total_calories which writer computed with '
              'Atwater fallback (kcalWithFallback) at write time');

      // Verify protein, carbs, fat also pass through (basic contract)
      expect(macros['protein'], 45.0,
          reason: 'total protein = 25 + 20 = 45g');
      expect(macros['carbs'], 65.0,
          reason: 'total carbs = 35 + 30 = 65g');
      expect(macros['fat'], 16.0,
          reason: 'total fat = 6 + 10 = 16g');
    });

    test(
        'Atwater fallback is NOT applied when item already has explicit calories',
        () async {
      // Confirm kcalWithFallback short-circuits: calories>0 → use as-is.
      final testDate = DateTime(2026, 6, 17);

      await NutritionWriteService.instance.logMeal(
        date: testDate,
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Oats',
            quantityG: 80,
            calories: 300, // explicit — Atwater would give 4*8+4*54+9*6 = 326
            protein: 8,
            carbs: 54,
            fat: 6,
            fiber: 8,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );

      final macros = NutritionRepository.instance.dailyMacros(testDate);

      // Must use explicit 300, NOT Atwater-recomputed 326
      expect(macros['calories'], 300.0,
          reason:
              'when item.calories > 0 writer must use it directly; '
              'Atwater only applies when calories == 0');
    });
  });
}
