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

  test('editLog replaces items + recomputes totals', () async {
    final r1 = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'breakfast',
      items: const [
        FoodItem(
            name: 'Oats',
            quantityG: 50,
            calories: 180,
            protein: 6,
            carbs: 30,
            fat: 3,
            fiber: 4),
      ],
      source: NutritionWriteSource.manualSearch,
    );

    final r2 = await NutritionWriteService.instance.editLog(
      logKey: r1.logKey!,
      updates: {
        'items': [
          const FoodItem(
            name: 'Oats',
            quantityG: 75,
            calories: 270,
            protein: 9,
            carbs: 45,
            fat: 5,
            fiber: 6,
          ).toMap(),
        ],
      },
    );
    expect(r2.success, true);

    final m = Map<String, dynamic>.from(
        HiveService.instance.nutritionBox.get(r1.logKey!) as Map);
    expect(m['total_calories'], 270);
    expect(m['total_fiber'], 6);
    expect((m['items'] as List).first['quantity_g'], 75);
  });

  test('editLog returns error when key missing', () async {
    final r = await NutritionWriteService.instance.editLog(
      logKey: 'nlog_missing',
      updates: const {'meal_type': 'lunch'},
    );
    expect(r.success, false);
  });
}
