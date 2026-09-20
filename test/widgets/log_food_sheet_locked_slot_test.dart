import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_sheet.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

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
}
