// test/nutrition/meal_slot_vocabulary_test.dart
//
// Round-2 plan-review fix (food-logging-observations batch, 2026-09-20):
// TodaysMealsCard's DISPLAY slot vocabulary uses the singular 'snack',
// while NutritionWriteService's WRITE vocabulary (isAllowedMealType) and
// MealTypeNotifier.build()'s own default both use the plural 'snacks'.
// Before this fix, tapping the Snack slot's "+ LOG" CTA anywhere in the
// app silently failed every write with no user-visible error, because
// `MealTypeNotifier.select('snack')` stored the singular value verbatim.
//
// Pins: (1) MealTypeNotifier.select normalizes 'snack' -> 'snacks' and
// passes every other value through unchanged; (2) resolveInitialMealSlot
// (the pure function backing both the Edit Macros selector's initial
// value AND its SAVE-time "did the slot change?" comparison) folds any
// legacy/unknown meal_type — including the singular 'snack' — to the
// canonical 'snacks'.
//
// FAILS when: `select` stops normalizing (redendering the Snack CTA a
// silent no-op again) OR `resolveInitialMealSlot` stops treating 'snack'
// as a legacy alias for 'snacks' (reopening the Edit Macros
// silent-retag-on-macros-only-edit bug for any row still carrying the
// singular value).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/meal_slot_inference.dart';

void main() {
  group('MealTypeNotifier.select — write-vocabulary normalization', () {
    test('normalizes the display-only singular "snack" to "snacks"', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(mealTypeProvider.notifier).select('snack');
      expect(container.read(mealTypeProvider), 'snacks');
    });

    test('passes every other canonical value through unchanged', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (final v in ['breakfast', 'lunch', 'dinner', 'snacks']) {
        container.read(mealTypeProvider.notifier).select(v);
        expect(container.read(mealTypeProvider), v);
      }
    });
  });

  group('resolveInitialMealSlot — Edit Macros selector default', () {
    test('canonical values pass through unchanged', () {
      for (final v in mealSlotKeys) {
        expect(resolveInitialMealSlot({'meal_type': v}), v);
      }
    });

    test('the legacy singular "snack" resolves to "snacks"', () {
      expect(resolveInitialMealSlot({'meal_type': 'snack'}), 'snacks');
    });

    test('is case-insensitive', () {
      expect(resolveInitialMealSlot({'meal_type': 'BREAKFAST'}), 'breakfast');
      expect(resolveInitialMealSlot({'meal_type': 'SNACK'}), 'snacks');
    });

    test('an absent or unknown meal_type falls back to "snacks"', () {
      expect(resolveInitialMealSlot({}), 'snacks');
      expect(resolveInitialMealSlot({'meal_type': 'brunch'}), 'snacks');
    });
  });

  group('mealSlotLabel / mealSlotEmoji — singular and plural both render',
      () {
    test('label is identical for "snack" and "snacks"', () {
      expect(mealSlotLabel('snack'), mealSlotLabel('snacks'));
      expect(mealSlotLabel('snack'), 'SNACK');
    });

    test('emoji is identical for "snack" and "snacks"', () {
      expect(mealSlotEmoji('snack'), mealSlotEmoji('snacks'));
    });
  });
}
