import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/nutrition/screens/nutrition_screen.dart',
  ).readAsStringSync();

  test('NutritionScreen renders the redesigned layout', () {
    // New widgets
    expect(source.contains('HydrationCard()'), isTrue,
        reason: 'NutritionScreen must render the new HydrationCard.');
    expect(source.contains('YourFoodsSection()'), isTrue,
        reason: 'NutritionScreen must render the new YourFoodsSection.');
    expect(source.contains('+ LOG FOOD'), isTrue,
        reason: 'NutritionScreen must show the + LOG FOOD CTA button.');
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
