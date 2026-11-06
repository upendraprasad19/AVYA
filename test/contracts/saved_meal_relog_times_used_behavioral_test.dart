// BEHAVIORAL CONTRACT TEST — saved_meals `times_used` (diagnose a8e3f1)
//
// Concept:  saved_meals
// Writer:   NutritionWriteService.relogSavedMeal (owns the bump for BOTH
//           formats since a8e3f1) + saveMealAsTemplate (re-save keeps it)
// Reader:   SavedMealsNotifier.build most-used sort; saved_meals_section
//           "used N×"; sync_nutrition._syncSavedMeals push.
//
// The bug: the bump lived in SavedMealsNotifier.relogSavedMeal, which only
// the LEGACY `saved_meal_*` path calls. `meal_*` templates — the only format
// the UI creates — re-log straight through the service and never counted.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

const _paneer = FoodItem(
    name: 'Paneer',
    quantityG: 100,
    calories: 265,
    protein: 18,
    carbs: 4,
    fat: 20,
    fiber: 0);

int? _timesUsed(String key) =>
    (HiveService.instance.nutritionBox.get(key) as Map?)?['times_used'] as int?;

Future<String> _seedTemplate() async {
  final src = await NutritionWriteService.instance.logMeal(
    date: DateTime(2026, 5, 1),
    mealType: 'lunch',
    items: const [_paneer],
    source: NutritionWriteSource.manualSearch,
  );
  final tpl = await NutritionWriteService.instance.saveMealAsTemplate(
    sourceLogKey: src.logKey!,
    customName: 'Paneer bowl',
  );
  expect(tpl.success, isTrue);
  return tpl.logKey!;
}

Future<void> _relog(String key) async {
  final r = await NutritionWriteService.instance.relogSavedMeal(
    savedMealKey: key,
    date: DateTime(2026, 5, 2),
    mealType: 'dinner',
  );
  expect(r.success, isTrue, reason: r.errorMessage);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  test('a meal_* template counts every re-log (the a8e3f1 bug)', () async {
    final key = await _seedTemplate();
    expect(key, startsWith('meal_'));
    expect(_timesUsed(key), isNull);
    await _relog(key);
    expect(_timesUsed(key), 1);
    await _relog(key);
    expect(_timesUsed(key), 2);
  });

  test('a legacy saved_meal_* row counts once per re-log, not twice',
      () async {
    const key = 'saved_meal_legacy';
    await HiveService.instance.nutritionBox.put(key, {
      'id': key,
      'name': 'Legacy bowl',
      'is_saved_meal': true,
      'times_used': 4,
      'items': [_paneer.toMap()],
    });
    await _relog(key);
    expect(_timesUsed(key), 5);
  });

  test('a missing template changes nothing and reports failure', () async {
    final r = await NutritionWriteService.instance.relogSavedMeal(
      savedMealKey: 'meal_missing',
      date: DateTime(2026, 5, 2),
      mealType: 'dinner',
    );
    expect(r.success, isFalse);
    expect(HiveService.instance.nutritionBox.get('meal_missing'), isNull);
  });

  test('re-saving the same meal keeps its count (R2-7)', () async {
    final key = await _seedTemplate();
    await _relog(key);
    await _relog(key);
    // Save the same meal again → same meal_<hash> key.
    final src = await NutritionWriteService.instance.logMeal(
      date: DateTime(2026, 5, 3),
      mealType: 'lunch',
      items: const [_paneer],
      source: NutritionWriteSource.manualSearch,
    );
    final again = await NutritionWriteService.instance.saveMealAsTemplate(
      sourceLogKey: src.logKey!,
      customName: 'Paneer bowl',
    );
    expect(again.logKey, key);
    expect(_timesUsed(key), 2);
  });

  test('bumpSavedMealTimesUsed: absent or non-int counts as 0', () {
    expect(NutritionWriteService.bumpSavedMealTimesUsed({})['times_used'], 1);
    expect(
        NutritionWriteService.bumpSavedMealTimesUsed({'times_used': 'x'})[
            'times_used'],
        1);
    expect(
        NutritionWriteService.bumpSavedMealTimesUsed({'times_used': 7})[
            'times_used'],
        8);
  });
}
