// FC6 regression test (diagnose 4e8f1b) — absurd-value clamp in the nutrition
// write path.
//
// A coach `log_meal_by_text` override (or any caller) could persist an absurd
// calorie value (e.g. 1,000,000 kcal) — there was NO upstream numeric bound, so
// the garbage flowed straight into `total_calories` and each `items[].calories`
// and corrupted every downstream sum (daily macros, streak, weekly report).
//
// The fix wires `NutritionWriteService.clampMealPayloadValues` (the pure,
// side-effect-free core of `_clampMealPayload`) into logMeal / appendItemsToMeal
// / editLog before each `box.put`. Ceilings: meal total 15000 kcal, item 10000,
// macros 2000 g, fiber 500 g. Clamp-and-telemetry, NEVER reject.
//
// This test drives the PURE method directly (no Hive) — it asserts the clamp
// mutates the payload in place and reports whether anything was clamped.
//
// FAILS when: the clamp is removed, a ceiling drifts, the item loop stops
// clamping per-item, or a normal meal is wrongly reported as clamped.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';

void main() {
  group('FC6 nutrition_total_calories absurd-value clamp', () {
    test('clamps an absurd meal total + item to the ceilings and returns true',
        () {
      final payload = <String, dynamic>{
        'total_calories': 1000000,
        'total_protein': 5000,
        'total_carbs': 5000,
        'total_fat': 5000,
        'total_fiber': 5000,
        'items': [
          {
            'name': 'garbage',
            'calories': 1000000,
            'protein': 999,
            'carbs': 3000,
            'fat': 3000,
            'fiber': 900,
          },
        ],
      };

      final clamped = NutritionWriteService.clampMealPayloadValues(payload);

      expect(clamped, isTrue,
          reason: 'an absurd payload must report that it was clamped');

      // Meal-level ceilings.
      expect(payload['total_calories'], 15000);
      expect(payload['total_protein'], 2000);
      expect(payload['total_carbs'], 2000);
      expect(payload['total_fat'], 2000);
      expect(payload['total_fiber'], 500);

      // Item-level ceilings (item calorie ceiling is 10000, distinct from the
      // 15000 meal ceiling; macros share the 2000 g ceiling; fiber 500 g).
      final item = (payload['items'] as List).first as Map;
      expect(item['calories'], 10000.0);
      expect(item['protein'], 999.0, reason: 'below ceiling — unchanged');
      expect(item['carbs'], 2000.0);
      expect(item['fat'], 2000.0);
      expect(item['fiber'], 500.0);
    });

    test('leaves a normal meal untouched and returns false', () {
      final payload = <String, dynamic>{
        'total_calories': 650,
        'total_protein': 40,
        'total_carbs': 70,
        'total_fat': 20,
        'total_fiber': 8,
        'items': [
          {
            'name': 'dal chawal',
            'calories': 300,
            'protein': 18,
            'carbs': 40,
            'fat': 8,
            'fiber': 5,
          },
        ],
      };

      final clamped = NutritionWriteService.clampMealPayloadValues(payload);

      expect(clamped, isFalse,
          reason: 'a normal meal must NOT be reported as clamped');

      // Totals unchanged (round() is a no-op on these int-valued fields).
      expect(payload['total_calories'], 650);
      expect(payload['total_protein'], 40);
      expect(payload['total_carbs'], 70);
      expect(payload['total_fat'], 20);
      expect(payload['total_fiber'], 8);

      final item = (payload['items'] as List).first as Map;
      expect(item['calories'], 300.0);
      expect(item['protein'], 18.0);
      expect(item['carbs'], 40.0);
      expect(item['fat'], 8.0);
      expect(item['fiber'], 5.0);
    });
  });
}
