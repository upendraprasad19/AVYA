// test/features/nutrition/ai_breakdown_save_confirmation_test.dart
//
// Widget test for the AI breakdown card save-confirmation snackbar (Theme L1,
// APK Test #11).
//
// Strategy: override `aiBreakdownProvider` with a fake notifier whose
// `saveMeal` returns a controlled WriteResult. Pump the `AiBreakdownCard`
// inside a ProviderScope with those overrides, tap SAVE MEAL, and assert
// the expected snackbar text appears.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/ai_breakdown_card.dart';

// ── Fake notifiers ──────────────────────────────────────────────────────────

class _FakeSuccessNotifier extends AiBreakdownNotifier {
  @override
  AiBreakdownData? build() => const AiBreakdownData(
        mealName: 'Test Meal',
        totalKcal: 400,
        items: [
          AiFoodItem(
            name: 'Rice',
            quantity: '1 cup',
            calories: 200,
            protein: '4g',
            carbs: '44g',
            fat: '0g',
            fiber: 1,
          ),
          AiFoodItem(
            name: 'Dal',
            quantity: '1 bowl',
            calories: 200,
            protein: '12g',
            carbs: '30g',
            fat: '2g',
            fiber: 2,
          ),
        ],
      );

  @override
  Future<WriteResult> saveMeal({String mealType = 'snacks'}) async {
    // Simulate success: clear state, return ok result.
    state = null;
    return WriteResult.ok('nlog_test_key_123');
  }
}

class _FakeFailureNotifier extends AiBreakdownNotifier {
  @override
  AiBreakdownData? build() => const AiBreakdownData(
        mealName: 'Fail Meal',
        totalKcal: 300,
        items: [
          AiFoodItem(
            name: 'Bread',
            quantity: '2 slices',
            calories: 300,
            protein: '8g',
            carbs: '56g',
            fat: '4g',
            fiber: 2,
          ),
        ],
      );

  @override
  Future<WriteResult> saveMeal({String mealType = 'snacks'}) async {
    return WriteResult.fail('Hive write failed: disk full');
  }
}

class _FakeNoStateNotifier extends AiBreakdownNotifier {
  @override
  AiBreakdownData? build() => const AiBreakdownData(
        mealName: 'Ghost Meal',
        totalKcal: 250,
        items: [
          AiFoodItem(
            name: 'Idli',
            quantity: '2 pieces',
            calories: 250,
            protein: '6g',
            carbs: '50g',
            fat: '1g',
            fiber: 1,
          ),
        ],
      );

  @override
  Future<WriteResult> saveMeal({String mealType = 'snacks'}) async {
    // Simulate double-tap: state is already gone, return the no_state sentinel.
    return WriteResult.noState();
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('AiBreakdownCard save confirmation', () {
    testWidgets(
        'shows "Meal saved ✓" snackbar on successful saveMeal',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiBreakdownProvider.overrideWith(() => _FakeSuccessNotifier()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AiBreakdownCard(),
              ),
            ),
          ),
        ),
      );

      // Card should be visible with a SAVE MEAL button.
      expect(find.text('SAVE MEAL'), findsOneWidget);

      // Tap the save button.
      await tester.tap(find.text('SAVE MEAL'));
      // Let the async saveMeal() complete and the snackbar animation start.
      await tester.pumpAndSettle();

      // Expect the success snackbar.
      expect(find.text('Meal saved ✓'), findsOneWidget);
    });

    testWidgets(
        'shows "Could not save — try again." snackbar on failed saveMeal',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiBreakdownProvider.overrideWith(() => _FakeFailureNotifier()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AiBreakdownCard(),
              ),
            ),
          ),
        ),
      );

      expect(find.text('SAVE MEAL'), findsOneWidget);

      await tester.tap(find.text('SAVE MEAL'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save — try again.'), findsOneWidget);
    });

    testWidgets(
        'shows "Already saved." snackbar on no_state error (double-tap / state cleared)',
        (tester) async {
      // Arrange: notifier returns WriteResult.noState() — the sentinel emitted
      // when saveMeal() is called after state was already cleared. This pins
      // the WriteResult.noState() / isNoState / "Already saved." chain so a
      // future refactor cannot break it silently.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiBreakdownProvider.overrideWith(() => _FakeNoStateNotifier()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AiBreakdownCard(),
              ),
            ),
          ),
        ),
      );

      // Act: tap SAVE MEAL.
      expect(find.text('SAVE MEAL'), findsOneWidget);
      await tester.tap(find.text('SAVE MEAL'));
      await tester.pumpAndSettle();

      // Assert: "Already saved." snackbar — NOT the generic error message.
      expect(find.text('Already saved.'), findsOneWidget);
      expect(find.text('Could not save — try again.'), findsNothing);
    });
  });
}
