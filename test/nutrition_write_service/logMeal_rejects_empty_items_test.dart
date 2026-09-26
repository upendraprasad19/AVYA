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

  test('rejects empty items list (closes 0-cal ghost row bug)', () async {
    final result = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'snacks',
      items: const [],
      source: NutritionWriteSource.aiText,
    );

    expect(result.success, false);
    expect(result.errorMessage, contains('empty'));

    final nlogs = HiveService.instance.nutritionBox.keys
        .whereType<String>()
        .where((k) => k.startsWith('nlog_'))
        .toList();
    expect(nlogs, isEmpty,
        reason: 'no nlog_* row should be written for empty items');
  });

  test('rejects unknown mealType', () async {
    final result = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'second_breakfast',
      items: const [
        FoodItem(
          name: 'Toast',
          quantityG: 30,
          calories: 90,
          protein: 3,
          carbs: 16,
          fat: 1,
          fiber: 1,
        ),
      ],
      source: NutritionWriteSource.manualSearch,
    );

    expect(result.success, false);
    expect(result.errorMessage, contains('mealType'));

    final nlogs = HiveService.instance.nutritionBox.keys
        .whereType<String>()
        .where((k) => k.startsWith('nlog_'))
        .toList();
    expect(nlogs, isEmpty);
  });
}
