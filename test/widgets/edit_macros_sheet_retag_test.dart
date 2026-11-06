// test/widgets/edit_macros_sheet_retag_test.dart
//
// Task 5 (food-logging-observations batch, Obs 1 — retag) — the Edit Macros
// sheet's meal-slot selector.
//
// ⚠ DEVIATION FROM THE BRIEF'S LITERAL TEST SKETCH, documented per the task
// instructions. `_showEditMacrosSheet` is a private method on the private
// `_NutritionScreenState` class in nutrition_screen.dart — Dart privacy is
// per-LIBRARY (file), so neither is reachable from this test file except by
// pumping the real `NutritionScreen` and tapping through to it. Doing that
// requires booting every Hive box + Riverpod provider the screen's
// `_buildMealsTab` depends on (dailyNutritionProvider, macroTargetsProvider,
// userProfileProvider, weeklyNutritionProvider, dietPlanProvider,
// authUserIdTokenProvider via HiveTabScaffoldMixin, etc.) — a much larger
// surface than this task's two-file scope (nutrition_screen.dart + this
// test), and no existing test in the repo pumps `NutritionScreen` to build
// from (confirmed via `grep -rl "NutritionScreen(" test/` returning nothing).
//
// Per the task brief's own escape hatch, this test instead pumps the
// `MealSlotSelector` widget directly — extracted in nutrition_screen.dart
// (Task 5) as a small top-level, public, real widget specifically so it CAN
// be tested this way, rather than being left as inline sheet markup. This
// is still a real widget test exercising real production code (the actual
// `MealSlotSelector` class, the actual `WardChip`/`WardChipTone` primitives,
// the actual `mealSlotLabel` helper) — not a bare unit test of extracted
// logic, and not a re-implementation of the selector's markup in the test
// file. It proves exactly what the brief's Step 1 asked for: the selector
// renders with the current slot indicated, and the other three slots are
// selectable (verified here by tapping one and observing the notifier flip).
//
// No Hive / path_provider / google_fonts setup is needed — this widget has
// no Hive dependency, so none of the batch's earlier-documented pitfalls
// (real I/O inside a fake-async testWidgets body; google_fonts hitting a
// live-fetch path once path_provider is mocked) apply here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/screens/nutrition_screen.dart';

void main() {
  testWidgets(
      "Edit Macros sheet has a meal-slot selector defaulted to the log's current slot",
      (tester) async {
    final selectedMealType = ValueNotifier<String>('breakfast');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealSlotSelector(selectedMealType: selectedMealType),
        ),
      ),
    );

    // Current slot (breakfast) is shown, plus the other three slots.
    expect(find.text('BREAKFAST'), findsOneWidget,
        reason: 'current slot chip must render');
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.text('DINNER'), findsOneWidget);
    expect(find.text('SNACK'), findsOneWidget);

    // The other three slots are selectable — tapping LUNCH flips the
    // notifier, proving the chips are wired to it (not decorative).
    expect(selectedMealType.value, 'breakfast');
    await tester.tap(find.text('LUNCH'));
    await tester.pumpAndSettle();
    expect(selectedMealType.value, 'lunch',
        reason: 'tapping a non-current slot chip must select it');

    // All four labels still present after the switch — no chip vanished.
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.text('DINNER'), findsOneWidget);
    expect(find.text('SNACK'), findsOneWidget);
  });
}
