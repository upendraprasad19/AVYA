// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import 'helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  test('deleteLog removes nlog_* row + stashes for undo', () async {
    final r1 = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'snacks',
      items: const [
        FoodItem(
            name: 'Banana',
            quantityG: 120,
            calories: 105,
            protein: 1,
            carbs: 27,
            fat: 0,
            fiber: 3),
      ],
      source: NutritionWriteSource.manualSearch,
    );

    final box = HiveService.instance.nutritionBox;
    expect(box.containsKey(r1.logKey!), true);

    final r2 = await NutritionWriteService.instance.deleteLog(
      logKey: r1.logKey!,
      allowUndo: true,
    );
    expect(r2.success, true);
    expect(box.containsKey(r1.logKey!), false);

    final restored =
        await NutritionWriteService.instance.restoreLastDeleted();
    expect(restored.success, true);
    expect(box.containsKey(r1.logKey!), true);
  });

  test('deleteLog with allowUndo:false drops the stash', () async {
    final r1 = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'snacks',
      items: const [
        FoodItem(
            name: 'Apple',
            quantityG: 150,
            calories: 80,
            protein: 0,
            carbs: 21,
            fat: 0,
            fiber: 4),
      ],
      source: NutritionWriteSource.manualSearch,
    );
    await NutritionWriteService.instance.deleteLog(
      logKey: r1.logKey!,
      allowUndo: false,
    );
    final restored =
        await NutritionWriteService.instance.restoreLastDeleted();
    expect(restored.success, false);
    expect(restored.errorMessage, contains('nothing to restore'));
  });
}
