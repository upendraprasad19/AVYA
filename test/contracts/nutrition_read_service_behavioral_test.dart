// Behavioral contract: NutritionReadService.totalMacrosForDate
//
// Asserts:
//  A) totalMacrosForDate sums pre-computed total_calories (writer applied
//     Atwater at write time); a kcal=0 item's contribution is non-zero.
//  B) entries with is_saved_meal=true are EXCLUDED from the daily total
//     (template rows must not double-count).
//
// FAILS when: totalMacrosForDate changes to skip `total_calories` field;
// OR stops excluding is_saved_meal==true rows; OR field names drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  group('nutrition_read_service behavioral contract', () {
    test(
        'totalMacrosForDate returns non-zero calories for kcal=0 item written with Atwater',
        () async {
      final testDate = DateTime(2026, 6, 18);

      // Write a meal with one kcal=0 item; writer applies Atwater at write time.
      // protein=15g, carbs=20g, fat=5g → 4*15 + 4*20 + 9*5 = 60+80+45 = 185 kcal
      final result = await NutritionWriteService.instance.logMeal(
        date: testDate,
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Unlabelled Powder',
            quantityG: 40,
            calories: 0, // no explicit kcal label
            protein: 15,
            carbs: 20,
            fat: 5,
            fiber: 1,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(result.success, isTrue);

      final totals = NutritionReadService.instance.totalMacrosForDate(testDate);

      // Atwater: 4*15 + 4*20 + 9*5 = 185 kcal
      expect(totals['calories'], equals(185),
          reason:
              'totalMacrosForDate reads pre-computed total_calories which writer '
              'calculated with Atwater; must not return 0 for kcal=0 item');
      expect(totals['calories']!.toDouble(), greaterThan(0),
          reason: 'Atwater fallback must produce non-zero calories');
    });

    test(
        'is_saved_meal=true rows are EXCLUDED from totalMacrosForDate',
        () async {
      final testDate = DateTime(2026, 6, 18);

      // Write a real meal log (counts toward daily total).
      final realLog = await NutritionWriteService.instance.logMeal(
        date: testDate,
        mealType: 'lunch',
        items: const [
          FoodItem(
            name: 'Dal Rice',
            quantityG: 300,
            calories: 450,
            protein: 18,
            carbs: 72,
            fat: 9,
            fiber: 5,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(realLog.success, isTrue);

      // Manually inject a saved_meal template entry that must NOT count.
      // This simulates what saveMeal() writes for template storage.
      final box = HiveService.instance.nutritionBox;
      final savedMealKey = 'saved_meal_template_test_${DateTime.now().millisecondsSinceEpoch}';
      final dateStr = istDateStr(testDate);
      await box.put(savedMealKey, {
        'id': savedMealKey,
        'log_key': savedMealKey,
        'date': dateStr,
        'meal_type': 'lunch',
        'is_saved_meal': true,
        'total_calories': 999, // large value — must NOT appear in totals
        'total_protein': 99,
        'total_carbs': 99,
        'total_fat': 99,
        'total_fiber': 9,
        'items': <dynamic>[],
        'source': 'saved',
        'logged_at': DateTime.now().toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final totals = NutritionReadService.instance.totalMacrosForDate(testDate);

      // Only the real log (450 kcal) must be counted; saved_meal template excluded.
      expect(totals['calories'], equals(450),
          reason:
              'totalMacrosForDate must skip is_saved_meal==true rows; '
              'template calories must not add to daily total');
      expect(totals['calories']!.toDouble(), lessThan(999),
          reason: 'saved_meal template (999 kcal) must be excluded');

      // Protein must also exclude the template.
      expect(totals['protein'], equals(18),
          reason:
              'saved_meal exclusion applies to all macro fields, not just calories');
    });

    test(
        'totalMacrosForDate returns zero map when no logs exist for date',
        () async {
      // A date with no logs should return zeros (not null / not throw).
      final emptyDate = DateTime(2020, 1, 1);

      final totals =
          NutritionReadService.instance.totalMacrosForDate(emptyDate);

      expect(totals['calories'], equals(0),
          reason: 'empty date must return 0 calories, not null');
      expect(totals['protein'], equals(0));
      expect(totals['carbs'], equals(0));
      expect(totals['fat'], equals(0));
      expect(totals['fiber'], equals(0));
    });
  });
}
