import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/nutrition/screens/nutrition_screen.dart',
  ).readAsStringSync();

  test('NutritionScreen renders the redesigned layout', () {
    // New widgets
    // Hydration moved behind the LOG HYDRATION button (founder call 2026-11-01):
    // the card is NOT inline on the page any more; the page opens it in a sheet.
    expect(source.contains('HydrationCard()'), isFalse,
        reason: 'HydrationCard must not be inline on the page — it lives in '
            'showHydrationSheet so the logged meals stay in view.');
    // Comment-stripped and wired to the RIGHT callback: a mention in a comment, or
    // LOG HYDRATION opening the food sheet, must not satisfy this pin.
    final code = source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((l) {
      final at = l.indexOf('//');
      return at < 0 ? l : l.substring(0, at);
    }).join('\n');
    expect(
        RegExp(r'onLogHydration:\s*\(\)\s*=>\s*showHydrationSheet\(context\)')
            .hasMatch(code),
        isTrue,
        reason: 'LOG HYDRATION must call showHydrationSheet on tap.');
    expect(
        RegExp(r'onLogFood:\s*\(\)\s*=>\s*showLogFoodSheet\(context\)')
            .hasMatch(code),
        isTrue,
        reason: 'LOG FOOD must call showLogFoodSheet on tap.');
    expect(source.contains('LogActionRow('), isTrue,
        reason: 'NutritionScreen must render the LOG FOOD | LOG HYDRATION row.');
    expect(source.contains('YourFoodsSection()'), isTrue,
        reason: 'NutritionScreen must render the new YourFoodsSection.');

    expect(source.contains('showLogFoodSheet'), isTrue,
        reason: 'CTA must call showLogFoodSheet on tap.');

    // Existing kept widgets
    expect(source.contains('TodaysMealsCard'), isTrue,
        reason: 'TodaysMealsCard must still render (kept, repositioned).');
    expect(source.contains('WeeklyChartCard'), isTrue,
        reason: 'WeeklyChartCard must still render (under INSIGHTS).');

    // Hoisted-into-sheet sections must NOT be instantiated on the page
    for (final removed in const [
      'FoodLoggerSection()',
      'ScanMealSection()',
      'CartAuditorSection()',
      'SavedMealsSection()',
      '_buildInlineWaterTracker',
      '_buildSearchAndCustomCard',
      '_buildAiInputCard',
    ]) {
      expect(
        source.contains(removed),
        isFalse,
        reason: '$removed must NOT appear on the redesigned nutrition '
            'page — it lives inside LogFoodSheet now (or is replaced).',
      );
    }
  });

  test('NutritionScreen does not import the hoisted widgets directly', () {
    for (final imp in const [
      "import '../widgets/food_logger_section.dart'",
      "import '../widgets/scan_meal_section.dart'",
      "import '../widgets/cart_auditor_section.dart'",
      "import '../widgets/saved_meals_section.dart'",
    ]) {
      expect(source.contains(imp), isFalse,
          reason: '$imp must be removed — those widgets are referenced '
              'from inside log_food_modes/* now.');
    }
  });
}
