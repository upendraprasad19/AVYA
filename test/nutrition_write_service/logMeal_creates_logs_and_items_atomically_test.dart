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

  test('logMeal writes Hive nlog_* row with all required fields', () async {
    final result = await NutritionWriteService.instance.logMeal(
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
          fiber: 4,
        ),
        FoodItem(
          name: 'Whey',
          quantityG: 30,
          calories: 120,
          protein: 24,
          carbs: 3,
          fat: 1,
          fiber: 0,
        ),
      ],
      source: NutritionWriteSource.manualSearch,
    );

    expect(result.success, true);
    expect(result.logKey, isNotNull);

    final box = HiveService.instance.nutritionBox;
    final raw = box.get(result.logKey!);
    expect(raw, isNotNull);
    final m = Map<String, dynamic>.from(raw as Map);
    expect(m['meal_type'], 'breakfast');
    expect(m['date'], '2026-05-01');
    expect((m['total_calories'] as num).toInt(), 300);
    expect((m['total_protein'] as num).toInt(), 30);
    expect((m['total_fiber'] as num).toInt(), 4);
    expect((m['items'] as List).length, 2);
    expect(m['source'], 'manualSearch');
  });

  test('cloud projection includes per-item rows (closes obs #23)', () async {
    // Unit-level shape check — actual cloud upsert is exercised by
    // integration tests. Asserts the Hive payload carries everything
    // _syncNutritionLogs needs to project both nutrition_logs +
    // nutrition_log_items.
    final result = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 1),
      mealType: 'breakfast',
      items: const [
        FoodItem(
            name: 'Eggs',
            quantityG: 100,
            calories: 155,
            protein: 13,
            carbs: 1,
            fat: 11,
            fiber: 0),
        FoodItem(
            name: 'Toast',
            quantityG: 30,
            calories: 90,
            protein: 3,
            carbs: 16,
            fat: 1,
            fiber: 1),
      ],
      source: NutritionWriteSource.scan,
    );

    expect(result.success, true);
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(result.logKey!);
    final m = Map<String, dynamic>.from(raw as Map);
    final items = (m['items'] as List).cast<Map>();
    expect(items.length, 2,
        reason:
            'Hive items[] must carry every food row so sync can project nutrition_log_items');
    expect(items.first['name'], 'Eggs');
    expect(items.first['quantity_g'], 100);
    expect(items.last['fiber'], 1);
    expect(m['source'], 'scan');
  });
}
