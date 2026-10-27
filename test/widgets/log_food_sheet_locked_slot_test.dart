import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_sheet.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/meal_slot_inference.dart';

void main() {
  testWidgets('lockedSlot sets mealTypeProvider and shows all 5 tabs', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.ai, lockedSlot: 'lunch')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(mealTypeProvider), 'lunch');
    expect(find.text('LOG TO LUNCH'), findsOneWidget);
    expect(find.textContaining('CART'), findsOneWidget);
    expect(find.textContaining('BAR'), findsOneWidget);
  });

  testWidgets('no lockedSlot keeps the default LOG FOOD title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.ai)),
        ),
      ),
    );
    expect(find.text('LOG FOOD'), findsOneWidget);
  });

  testWidgets(
      'header title stays in sync when the live slot changes after open '
      '(B-pass finding, 2026-09-20)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.ai, lockedSlot: 'lunch')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LOG TO LUNCH'), findsOneWidget);

    // Simulate a tab's own selector (the AI chip, the Barcode pill row)
    // moving the actual write destination after open — pre-fix, the
    // header read the static widget.lockedSlot and stayed frozen on
    // "LOG TO LUNCH" even though the real destination had moved.
    container.read(mealTypeProvider.notifier).select('dinner');
    await tester.pump();

    expect(find.text('LOG TO DINNER'), findsOneWidget);
    expect(find.text('LOG TO LUNCH'), findsNothing);
  });

  testWidgets(
      'opening unlocked re-infers the current slot, not a leftover value '
      'from an earlier locked sheet (round-2 plan review, 2026-09-20)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Simulate mealTypeProvider carrying a stale value from an earlier
    // LOCKED sheet opened in the same app session — deliberately chosen
    // to disagree with whatever the real current time-of-day inference
    // is, so the test discriminates regardless of wall-clock time.
    final freshInference = inferMealSlot(DateTime.now());
    final staleValue = freshInference == 'breakfast' ? 'dinner' : 'breakfast';
    container.read(mealTypeProvider.notifier).select(staleValue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          // No lockedSlot — the free-floating "+ LOG FOOD" entry point.
          home: Scaffold(body: LogFoodSheet(initial: LogFoodMode.ai)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(mealTypeProvider), freshInference,
        reason: 'an unlocked open must re-infer the CURRENT slot — '
            'pre-fix, MealTypeNotifier.build() only infers once per app '
            'session, so this would have silently kept logging to '
            '$staleValue (an earlier locked sheet\'s leftover value)');
  });
}
