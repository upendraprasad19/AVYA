import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/widgets/todays_meals_card.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';

void main() {
  testWidgets('planned-only slot shows a SUGGESTED chip, not a bare eyebrow',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodaysMealsCard(
            meals: const [],
            plannedSlots: {
              'breakfast': const PlannedSlot(
                slot: 'breakfast',
                summary: 'Oats + banana',
                calories: 320,
                protein: 12,
                firstFoodName: 'Oats',
              ),
            },
          ),
        ),
      ),
    );
    expect(find.text('SUGGESTED'), findsOneWidget,
        reason:
            'obs 7 — a diet-plan hint must read as a suggestion, not a logged entry');
  });
}
