// test/contracts/nutrition_log_retag_writer_to_reader_test.dart
//
// Contract: nutrition_log_retag
// Writer: NutritionWriteService.moveMealLog (rekeys nlog_* row to a new
//         meal-type slot; obs 1, 2026-09-20 food-logging observations batch)
// Reader: TodaysMealsCard (groups nlog_* rows by meal_type)
//
// Pins: (1) the old Hive key is deleted and a NEW key (embedding the new
// mealType) is written with meal_type/id/log_key all updated; (2) an
// optional macroUpdates map is applied atomically with the rekey.
//
// FAILS when: moveMealLog stops deleting the old key (duplicate rows) OR
// stops updating meal_type/id/log_key on the new row OR drops macroUpdates.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  group('nutrition_log_retag writer→reader contract', () {
    test('moveMealLog rekeys a log to a new slot and the new slot reads it',
        () async {
      final date = DateTime(2026, 9, 20);
      final logResult = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Oats',
            quantityG: 100,
            calories: 300,
            protein: 10,
            carbs: 50,
            fat: 5,
            fiber: 4,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(logResult.success, isTrue);
      final oldKey = logResult.logKey!;

      final moveResult = await NutritionWriteService.instance.moveMealLog(
        logKey: oldKey,
        newMealType: 'lunch',
      );
      expect(moveResult.success, isTrue);
      final newKey = moveResult.logKey!;
      expect(newKey, isNot(equals(oldKey)));

      final box = HiveService.instance.nutritionBox;
      expect(box.get(oldKey), isNull, reason: 'old slot key must be gone');
      final moved = Map<String, dynamic>.from(box.get(newKey) as Map);
      expect(moved['meal_type'], 'lunch');
      expect(moved['id'], newKey);
      expect(moved['log_key'], newKey);
      expect(moved['items'], isNotEmpty);
    });

    test('moveMealLog applies macroUpdates atomically with the rekey',
        () async {
      final date = DateTime(2026, 9, 20);
      final logResult = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Oats',
            quantityG: 100,
            calories: 300,
            protein: 10,
            carbs: 50,
            fat: 5,
            fiber: 4,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(logResult.success, isTrue);
      final oldKey = logResult.logKey!;

      final moveResult = await NutritionWriteService.instance.moveMealLog(
        logKey: oldKey,
        newMealType: 'dinner',
        macroUpdates: const {'total_calories': 999},
      );
      expect(moveResult.success, isTrue);
      final newKey = moveResult.logKey!;
      final moved = Map<String, dynamic>.from(
          HiveService.instance.nutritionBox.get(newKey) as Map);
      expect(moved['total_calories'], 999);
      expect(moved['meal_type'], 'dinner');
    });
  });
}
