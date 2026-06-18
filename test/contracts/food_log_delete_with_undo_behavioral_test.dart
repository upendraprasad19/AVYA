// Behavioral contract: NutritionWriteService.deleteLog → restoreLastDeleted
//
// Asserts:
//  A) delete then UNDO restores exact entry including all macros
//  B) delete without undo (allowUndo:false) commits permanently;
//     subsequent restoreLastDeleted returns failure
//
// FAILS when: _lastDeletedPayload stash is cleared prematurely; OR
// restoreLastDeleted writes under a different key; OR macro fields drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  group('food_log_delete_with_undo behavioral contract', () {
    test('delete then restoreLastDeleted restores exact entry with all macros',
        () async {
      final testDate = DateTime(2026, 6, 18);

      // Write a meal log.
      final logResult = await NutritionWriteService.instance.logMeal(
        date: testDate,
        mealType: 'dinner',
        items: const [
          FoodItem(
            name: 'Paneer Tikka',
            quantityG: 200,
            calories: 420,
            protein: 32,
            carbs: 12,
            fat: 28,
            fiber: 2,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(logResult.success, isTrue);
      final logKey = logResult.logKey!;

      final box = HiveService.instance.nutritionBox;

      // Confirm it exists before delete.
      expect(box.get(logKey), isNotNull,
          reason: 'entry must exist in Hive before delete');

      // Delete with undo allowed (default).
      final deleteResult = await NutritionWriteService.instance.deleteLog(
        logKey: logKey,
        allowUndo: true,
        writeAuditLog: false,
      );
      expect(deleteResult.success, isTrue);

      // After delete, key must be absent.
      expect(box.get(logKey), isNull,
          reason: 'entry must be removed from Hive after deleteLog');

      // UNDO.
      final restoreResult =
          await NutritionWriteService.instance.restoreLastDeleted();
      expect(restoreResult.success, isTrue,
          reason: 'restoreLastDeleted must succeed when stash is populated');

      // Entry must be back.
      final restored = box.get(logKey);
      expect(restored, isNotNull,
          reason: 'restoreLastDeleted must re-put the entry at the original key');

      final m = Map<String, dynamic>.from(restored as Map);

      // All macro fields must be exact.
      expect(m['total_calories'], 420,
          reason: 'total_calories must survive the delete→undo round-trip');
      expect(m['total_protein'], 32,
          reason: 'total_protein must survive the delete→undo round-trip');
      expect(m['total_carbs'], 12,
          reason: 'total_carbs must survive the delete→undo round-trip');
      expect(m['total_fat'], 28,
          reason: 'total_fat must survive the delete→undo round-trip');
      expect(m['total_fiber'], 2,
          reason: 'total_fiber must survive the delete→undo round-trip');
      expect(m['meal_type'], 'dinner',
          reason: 'meal_type must survive the delete→undo round-trip');
      expect(m['date'], isNotNull,
          reason: 'date field must survive the delete→undo round-trip');

      // A second restoreLastDeleted must fail (stash cleared after first restore).
      final secondRestore =
          await NutritionWriteService.instance.restoreLastDeleted();
      expect(secondRestore.success, isFalse,
          reason:
              'stash must be cleared after first restore; second call must fail');
    });

    test(
        'delete with allowUndo:false commits permanently; restoreLastDeleted fails',
        () async {
      final testDate = DateTime(2026, 6, 17);

      final logResult = await NutritionWriteService.instance.logMeal(
        date: testDate,
        mealType: 'snacks',
        items: const [
          FoodItem(
            name: 'Protein Bar',
            quantityG: 60,
            calories: 220,
            protein: 20,
            carbs: 22,
            fat: 8,
            fiber: 3,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(logResult.success, isTrue);
      final logKey = logResult.logKey!;

      final box = HiveService.instance.nutritionBox;

      // Delete with NO undo.
      final deleteResult = await NutritionWriteService.instance.deleteLog(
        logKey: logKey,
        allowUndo: false,
        writeAuditLog: false,
      );
      expect(deleteResult.success, isTrue);

      // Entry must be gone.
      expect(box.get(logKey), isNull,
          reason: 'entry must be absent after allowUndo:false delete');

      // Restore must fail (stash was not set).
      final restoreResult =
          await NutritionWriteService.instance.restoreLastDeleted();
      expect(restoreResult.success, isFalse,
          reason:
              'allowUndo:false must NOT populate the stash; '
              'restoreLastDeleted must return failure');

      // Entry must remain absent after failed restore.
      expect(box.get(logKey), isNull,
          reason: 'entry must still be absent after failed restore attempt');
    });
  });
}
