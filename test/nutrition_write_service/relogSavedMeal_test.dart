// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import 'helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  test('relogSavedMeal creates a new nlog_* from a template', () async {
    final src = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'lunch',
      items: const [
        FoodItem(
            name: 'Paneer',
            quantityG: 100,
            calories: 265,
            protein: 18,
            carbs: 4,
            fat: 20,
            fiber: 0),
      ],
      source: NutritionWriteSource.manualSearch,
    );
    final tpl = await NutritionWriteService.instance.saveMealAsTemplate(
      sourceLogKey: src.logKey!,
      customName: 'Paneer bowl',
    );
    expect(tpl.success, true);

    final relog = await NutritionWriteService.instance.relogSavedMeal(
      savedMealKey: tpl.logKey!,
      date: DateTime(2026, 5, 2),
      mealType: 'dinner',
    );
    expect(relog.success, true);
    expect(relog.logKey, isNot(src.logKey));
    expect(relog.logKey, startsWith('nlog_2026-05-02_dinner_'));
  });
}
