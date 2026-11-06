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

  test('saveMealAsTemplate writes meal_<hash> with is_template=true',
      () async {
    final src = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'breakfast',
      items: const [
        FoodItem(
            name: 'Idli',
            quantityG: 80,
            calories: 145,
            protein: 5,
            carbs: 30,
            fat: 1,
            fiber: 2),
        FoodItem(
            name: 'Sambar',
            quantityG: 200,
            calories: 105,
            protein: 6,
            carbs: 17,
            fat: 2,
            fiber: 5),
      ],
      source: NutritionWriteSource.manualSearch,
    );
    final tpl = await NutritionWriteService.instance.saveMealAsTemplate(
      sourceLogKey: src.logKey!,
      customName: 'Idli + sambar',
    );
    expect(tpl.success, true);
    final m = Map<String, dynamic>.from(
        HiveService.instance.nutritionBox.get(tpl.logKey!) as Map);
    expect(m['is_template'], true);
    expect(m['name'], 'Idli + sambar');
    expect((m['items'] as List).length, 2);
  });
}
