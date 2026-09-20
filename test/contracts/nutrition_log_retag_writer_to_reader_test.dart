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

    test(
        'moveMealLog merges items and clamps totals when two logs collide '
        'at the same destination key', () async {
      // Two logs with IDENTICAL items (same items → same computeLogKey
      // hash) logged into two DIFFERENT source slots, both moved into the
      // SAME destination slot, must land at the SAME newKey and merge —
      // exercising the `existingAtDestination is Map` branch.
      const items = [
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
      final date = DateTime(2026, 9, 20);

      final firstLog = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'breakfast',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      final secondLog = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'lunch',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      expect(firstLog.success, isTrue);
      expect(secondLog.success, isTrue);

      final firstMove = await NutritionWriteService.instance.moveMealLog(
        logKey: firstLog.logKey!,
        newMealType: 'dinner',
      );
      expect(firstMove.success, isTrue);
      final destinationKey = firstMove.logKey!;

      final secondMove = await NutritionWriteService.instance.moveMealLog(
        logKey: secondLog.logKey!,
        newMealType: 'dinner',
      );
      expect(secondMove.success, isTrue);
      // Collision: both moves must land at the SAME key (same date +
      // mealType + identical-items hash).
      expect(secondMove.logKey, destinationKey);

      final box = HiveService.instance.nutritionBox;
      expect(box.get(firstLog.logKey!), isNull);
      expect(box.get(secondLog.logKey!), isNull);

      final merged =
          Map<String, dynamic>.from(box.get(destinationKey) as Map);
      expect(merged['meal_type'], 'dinner');
      final mergedItems = merged['items'] as List;
      expect(mergedItems, hasLength(2),
          reason: 'both source logs\' items must be unioned on collision');
      // Two identical items (300 kcal / 10P / 50C / 5F / 4Fi each) summed.
      expect(merged['total_calories'], 600);
      expect(merged['total_protein'], 20);
      expect(merged['total_carbs'], 100);
      expect(merged['total_fat'], 10);
      expect(merged['total_fiber'], 8);
      // Every field the collision branch recomputes must still be within
      // the FC6 clamp ceilings — proves _clampMealPayload ran on the
      // POST-merge row, not the pre-merge one (review round 1 Important
      // finding: clamp was called BEFORE the merge, so a merge that pushed
      // a total past the ceiling would have written an unclamped value).
      expect(merged['total_calories'], lessThanOrEqualTo(15000));
      expect(merged['total_protein'], lessThanOrEqualTo(2000));
    });

    test(
        'moveMealLog clamps the POST-merge total, not the pre-merge one, '
        'on a collision (review round 1 Important finding)', () async {
      // Two logs whose items are each individually under the per-meal
      // ceiling (_kMaxMealCalories=15000) but whose MERGED sum exceeds it.
      // If _clampMealPayload ran BEFORE the collision-merge recompute (the
      // pre-fix order), the pre-merge total (9000, under ceiling) would
      // pass through unclamped, and the merge step would then overwrite
      // total_calories with the unclamped 18000. Correct (post-merge
      // clamp) order must leave the written total at the 15000 ceiling.
      const items = [
        FoodItem(
          name: 'Mega Bar',
          quantityG: 500,
          calories: 9000,
          protein: 10,
          carbs: 50,
          fat: 5,
          fiber: 4,
        ),
      ];
      final date = DateTime(2026, 9, 20);

      final firstLog = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'breakfast',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      final secondLog = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'lunch',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );

      final firstMove = await NutritionWriteService.instance.moveMealLog(
        logKey: firstLog.logKey!,
        newMealType: 'snacks',
      );
      final destinationKey = firstMove.logKey!;
      final secondMove = await NutritionWriteService.instance.moveMealLog(
        logKey: secondLog.logKey!,
        newMealType: 'snacks',
      );
      expect(secondMove.logKey, destinationKey,
          reason: 'both moves must collide at the same destination key');

      final merged = Map<String, dynamic>.from(
          HiveService.instance.nutritionBox.get(destinationKey) as Map);
      // Unclamped merge would be 9000 + 9000 = 18000, which exceeds the
      // 15000 ceiling — the write must never persist that raw value.
      expect(merged['total_calories'], 15000,
          reason:
              'merged total (18000) must be clamped to the 15000 ceiling '
              'AFTER the merge recompute, not left at the pre-merge '
              'per-source value');
    });

    test(
        'moveMealLog applies macroUpdates on top of a collision-merge, not '
        'the other way around (B-pass finding, 2026-09-20)', () async {
      // Pre-fix: the collision branch unconditionally recomputed every
      // total_* field from the merged item list AFTER macroUpdates had
      // already been applied to `row`, silently discarding the caller's
      // explicit macro edit whenever the destination slot already held a
      // log. This is exactly the Edit Macros sheet's real call shape: a
      // user can both retag AND edit macros in one SAVE.
      const items = [
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
      final date = DateTime(2026, 9, 20);

      final firstLog = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'breakfast',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      final secondLog = await NutritionWriteService.instance.logMeal(
        date: date,
        mealType: 'lunch',
        items: items,
        source: NutritionWriteSource.manualSearch,
      );

      final firstMove = await NutritionWriteService.instance.moveMealLog(
        logKey: firstLog.logKey!,
        newMealType: 'dinner',
      );
      final destinationKey = firstMove.logKey!;

      // Second move collides at `destinationKey` AND carries an explicit
      // macro override — the two effects the pre-fix ordering couldn't
      // combine correctly.
      final secondMove = await NutritionWriteService.instance.moveMealLog(
        logKey: secondLog.logKey!,
        newMealType: 'dinner',
        macroUpdates: const {'total_calories': 42},
      );
      expect(secondMove.success, isTrue);
      expect(secondMove.logKey, destinationKey,
          reason: 'both moves must collide at the same destination key');

      final merged = Map<String, dynamic>.from(
          HiveService.instance.nutritionBox.get(destinationKey) as Map);
      // Pre-fix this would read 600 (the merged item-fold total), silently
      // discarding the caller's macroUpdates.
      expect(merged['total_calories'], 42,
          reason: 'an explicit macroUpdates value must win over the '
              'collision-merge recompute, not be silently discarded by it');
      // The item merge itself must still have happened — macroUpdates
      // overriding totals must not skip the items union.
      expect(merged['items'], hasLength(2));
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
