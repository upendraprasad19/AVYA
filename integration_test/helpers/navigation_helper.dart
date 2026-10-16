import 'package:flutter_test/flutter_test.dart';

/// Tab-navigation helpers for integration tests.
///
/// All helpers use soft-matching on tab label text so they remain
/// resilient to minor label wording changes. They pump-and-settle
/// after navigation so the destination screen is fully rendered.

Future<void> navigateToTab(WidgetTester tester, String label) async {
  final tab = find.textContaining(label, findRichText: true);
  if (tab.evaluate().isNotEmpty) {
    await tester.tap(tab.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
}

Future<void> navigateToHome(WidgetTester tester) =>
    navigateToTab(tester, 'Home');

Future<void> navigateToTrain(WidgetTester tester) =>
    navigateToTab(tester, 'Train');

Future<void> navigateToNutrition(WidgetTester tester) =>
    navigateToTab(tester, 'Nutrition');

Future<void> navigateToProfile(WidgetTester tester) =>
    navigateToTab(tester, 'Profile');

/// Coach tab may be labelled "Coach", "AI", or "AI Coach".
Future<void> navigateToAiCoach(WidgetTester tester) async {
  for (final label in ['Coach', 'AI']) {
    final tab = find.textContaining(label, findRichText: true);
    if (tab.evaluate().isNotEmpty) {
      await tester.tap(tab.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      return;
    }
  }
}

/// Returns true if any of the given text fragments is currently visible.
bool anyTextVisible(List<String> texts) => texts.any(
      (t) => find.textContaining(t, findRichText: true).evaluate().isNotEmpty,
    );
