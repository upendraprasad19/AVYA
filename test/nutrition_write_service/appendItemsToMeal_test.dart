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

  test('appendItemsToMeal grows items[] and recomputes totals', () async {
    final r1 = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'lunch',
      items: const [
        FoodItem(
            name: 'Roti',
            quantityG: 60,
            calories: 200,
            protein: 6,
            carbs: 40,
            fat: 1,
            fiber: 4),
      ],
      source: NutritionWriteSource.manualSearch,
    );
    expect(r1.success, true);

    final r2 = await NutritionWriteService.instance.appendItemsToMeal(
      existingLogKey: r1.logKey!,
      additionalItems: const [
        FoodItem(
            name: 'Dal',
            quantityG: 150,
            calories: 180,
            protein: 12,
            carbs: 26,
            fat: 3,
            fiber: 6),
      ],
    );
    expect(r2.success, true);

    final m = Map<String, dynamic>.from(
        HiveService.instance.nutritionBox.get(r1.logKey!) as Map);
    expect((m['items'] as List).length, 2);
    expect(m['total_calories'], 380);
    expect(m['total_protein'], 18);
    expect(m['total_fiber'], 10);
  });

  test('appendItemsToMeal returns error when key missing', () async {
    final r = await NutritionWriteService.instance.appendItemsToMeal(
      existingLogKey: 'nlog_does_not_exist',
      additionalItems: const [
        FoodItem(
            name: 'X',
            quantityG: 1,
            calories: 1,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0),
      ],
    );
    expect(r.success, false);
    expect(r.errorMessage, contains('not found'));
  });
}
