// test/ai_coach/meals_today_snapshot_test.dart
//
// Validates the new _getMealsToday snapshot helper added to
// AiCoachRepository in APK Test #3 / Q6.3. Builds an in-memory Hive
// nutritionBox with three nlog_* rows for today (one per slot), invokes
// the helper via its @visibleForTesting public seam, and asserts the
// grouped shape.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('aicoach_test_');
    // Mock path_provider so HiveService.init()'s Hive.initFlutter() works
    // outside a Flutter app binding. Without this, `getApplicationDocumentsDirectory`
    // throws MissingPluginException in pure unit tests.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.nutritionBox.clear();
  });

  String todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, "0")}-'
        '${now.day.toString().padLeft(2, "0")}';
  }

  test('_getMealsToday groups today nlog_ rows by meal_type', () async {
    final box = HiveService.instance.nutritionBox;
    final today = todayStr();

    await box.put('nlog_1', {
      'id': 'nlog_1',
      'date': today,
      'meal_type': 'breakfast',
      'food_name': 'Oats',
      'total_calories': 152,
      'total_protein': 5,
      'total_carbs': 27,
      'total_fat': 3,
    });
    await box.put('nlog_2', {
      'id': 'nlog_2',
      'date': today,
      'meal_type': 'breakfast',
      'food_name': 'Milk (Toned)',
      'total_calories': 140,
      'total_protein': 8,
      'total_carbs': 12,
      'total_fat': 8,
    });
    await box.put('nlog_3', {
      'id': 'nlog_3',
      'date': today,
      'meal_type': 'lunch',
      'food_name': 'Chicken Breast',
      'total_calories': 165,
      'total_protein': 31,
      'total_carbs': 0,
      'total_fat': 4,
    });

    final meals = AiCoachRepository.instance.mealsTodayForTest();

    // Should have at most 4 slots (breakfast / lunch / dinner / snacks)
    expect(meals.length, lessThanOrEqualTo(4));

    final breakfast = meals.firstWhere((m) => m['slot'] == 'breakfast',
        orElse: () => <String, dynamic>{});
    expect(breakfast.isNotEmpty, isTrue, reason: 'breakfast slot must exist');
    expect(breakfast['total_kcal'], equals(292));
    expect(breakfast['total_protein_g'], equals(13));
    expect((breakfast['items'] as List).length, equals(2));
    final names =
        (breakfast['items'] as List).map((i) => i['name'] as String).toList();
    expect(names, containsAll(['Oats', 'Milk (Toned)']));

    final lunch = meals.firstWhere((m) => m['slot'] == 'lunch',
        orElse: () => <String, dynamic>{});
    expect(lunch.isNotEmpty, isTrue, reason: 'lunch slot must exist');
    expect(lunch['total_protein_g'], equals(31));

    // No dinner / snacks rows written → those slots must NOT appear.
    expect(meals.any((m) => m['slot'] == 'dinner'), isFalse);
    expect(meals.any((m) => m['slot'] == 'snacks'), isFalse);
  });

  test('_getMealsToday item shape contains name + macros', () async {
    final box = HiveService.instance.nutritionBox;
    final today = todayStr();
    await box.put('nlog_1', {
      'id': 'nlog_1',
      'date': today,
      'meal_type': 'lunch',
      'food_name': 'Paneer',
      'total_calories': 265,
      'total_protein': 18,
      'total_carbs': 1,
      'total_fat': 21,
    });

    final meals = AiCoachRepository.instance.mealsTodayForTest();
    final item = (meals.first['items'] as List).first as Map;

    expect(item['name'], equals('Paneer'));
    expect(item['kcal'], equals(265));
    expect(item['protein_g'], equals(18));
    expect(item['carbs_g'], equals(1));
    expect(item['fat_g'], equals(21));
  });

  test('_getMealsToday excludes rows from other dates', () async {
    final box = HiveService.instance.nutritionBox;
    await box.put('nlog_yesterday', {
      'id': 'nlog_yesterday',
      'date': '2020-01-01', // far past
      'meal_type': 'breakfast',
      'food_name': 'Old log',
      'total_calories': 100,
      'total_protein': 5,
    });
    final meals = AiCoachRepository.instance.mealsTodayForTest();
    expect(meals, isEmpty);
  });
}
