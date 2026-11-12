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

    // OI-493 Landing B (B3, founder decision F4): the collision MERGE these
    // three tests used to pin is gone. A move into a slot already holding the
    // same meal writes the first FREE occurrence (`<dest>_2`): two entries
    // stay two. The FC6 clamp-after-recompute and the macroUpdates ordering
    // they also protected are re-pinned on the moved row.
    const oats = [
      FoodItem(
        name: 'Oats',
        quantityG: 100,
        calories: 300,
        protein: 10,
        carbs: 50,
        fat: 5,
        fiber: 4,
      ),
    ];

    Future<(String, String)> logTwiceInTwoSlots(List<FoodItem> items) async {
      final date = DateTime(2026, 9, 20);
      final first = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'breakfast',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      final second = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'lunch',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      expect(first.success, isTrue);
      expect(second.success, isTrue);
      return (first.logKey!, second.logKey!);
    }

    test(
        'moveMealLog keeps two entries apart when the destination already '
        'holds the same meal (OI-493 Landing B)', () async {
      final (firstKey, secondKey) = await logTwiceInTwoSlots(oats);

      final firstMove = await NutritionWriteService.instance.moveMealLog(
        logKey: firstKey,
        newMealType: 'dinner',
      );
      expect(firstMove.success, isTrue);
      final destinationKey = firstMove.logKey!;

      final secondMove = await NutritionWriteService.instance.moveMealLog(
        logKey: secondKey,
        newMealType: 'dinner',
      );
      expect(secondMove.success, isTrue);
      expect(secondMove.logKey, '${destinationKey}_2',
          reason: 'the second move takes the first free occurrence');

      final box = HiveService.instance.nutritionBox;
      expect(box.get(firstKey), isNull);
      expect(box.get(secondKey), isNull);

      for (final key in [destinationKey, '${destinationKey}_2']) {
        final row = Map<String, dynamic>.from(box.get(key) as Map);
        expect(row['meal_type'], 'dinner');
        expect(row['id'], key);
        expect(row['log_key'], key);
        expect(row['items'], hasLength(1),
            reason: 'no merge: each entry keeps its own item');
        expect(row['total_calories'], 300);
      }
    });

    test(
        'moveMealLog clamps the written total AFTER macroUpdates '
        '(FC6, re-pinned without the merge)', () async {
      final (firstKey, _) = await logTwiceInTwoSlots(oats);
      final moved = await NutritionWriteService.instance.moveMealLog(
        logKey: firstKey,
        newMealType: 'snacks',
        macroUpdates: const {'total_calories': 18000},
      );
      expect(moved.success, isTrue);
      final row = Map<String, dynamic>.from(
          HiveService.instance.nutritionBox.get(moved.logKey!) as Map);
      expect(row['total_calories'], 15000,
          reason: 'an over-ceiling total must be clamped after macroUpdates '
              'are applied, never written raw');
    });

    test(
        'moveMealLog applies macroUpdates to the moved occurrence only, '
        'not to the entry already at the destination', () async {
      final (firstKey, secondKey) = await logTwiceInTwoSlots(oats);
      final firstMove = await NutritionWriteService.instance.moveMealLog(
        logKey: firstKey,
        newMealType: 'dinner',
      );
      final destinationKey = firstMove.logKey!;
      final secondMove = await NutritionWriteService.instance.moveMealLog(
        logKey: secondKey,
        newMealType: 'dinner',
        macroUpdates: const {'total_calories': 42},
      );
      expect(secondMove.success, isTrue);
      expect(secondMove.logKey, '${destinationKey}_2');

      final box = HiveService.instance.nutritionBox;
      final movedRow = Map<String, dynamic>.from(
          box.get('${destinationKey}_2') as Map);
      final destRow =
          Map<String, dynamic>.from(box.get(destinationKey) as Map);
      expect(movedRow['total_calories'], 42,
          reason: 'the caller\'s macro edit applies to the moved row');
      expect(destRow['total_calories'], 300,
          reason: 'the entry already at the destination is untouched');
    });

    test('moveMealLog rejects an unknown mealType', () async {
      final logResult = await NutritionWriteService.instance.logMeal(
        date: DateTime(2026, 9, 20),
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
      final result = await NutritionWriteService.instance.moveMealLog(
        logKey: logResult.logKey!,
        newMealType: 'brunch',
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('not in'));
      // The row must be untouched at its original key.
      expect(
          HiveService.instance.nutritionBox.get(logResult.logKey!), isNotNull);
    });

    test(
        'moveMealLog to the SAME mealType is a no-op that still applies '
        'macroUpdates via editLog', () async {
      final logResult = await NutritionWriteService.instance.logMeal(
        date: DateTime(2026, 9, 20),
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
      final oldKey = logResult.logKey!;

      final result = await NutritionWriteService.instance.moveMealLog(
        logKey: oldKey,
        newMealType: 'breakfast',
        macroUpdates: const {'total_calories': 777},
      );
      expect(result.success, isTrue);
      expect(result.logKey, oldKey, reason: 'no-op move keeps the same key');

      final row = Map<String, dynamic>.from(
          HiveService.instance.nutritionBox.get(oldKey) as Map);
      expect(row['total_calories'], 777);
      expect(row['meal_type'], 'breakfast');
    });
  });
}
