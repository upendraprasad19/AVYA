// test/contracts/nutrition_recent_logs_name_behavioral_test.dart
//
// WI-4 (regression-prevention batch) — BEHAVIORAL reader-contract for the
// `nutrition_recent_logs_name` SoT concept. Replaces the source-grep-only guard
// with a real reader round-trip that pins diagnose 8b3d4e: the writer
// (NutritionWriteService.logMeal) stores the food name ONLY inside items[].name
// (never a top-level food_name); the Home + Nutrition readers MUST derive the
// display name from items[].name via NutritionReadService.deriveMealDisplayName.
// The bug: Home read a non-existent top-level food_name -> every meal "Unknown".
//
// Feeds the WRITER'S REAL MAP SHAPE to the REAL reader and asserts the derived
// name. A presence-grep can't catch a reader that reads the wrong key; this can.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';

void main() {
  group('nutrition_recent_logs_name behavioral reader-contract (8b3d4e)', () {
    test('derives display name from items[].name (the writer\'s real shape)',
        () {
      final name = NutritionReadService.deriveMealDisplayName({
        'items': [
          {'name': 'Oats'},
          {'name': 'Banana'},
        ],
      });
      expect(name, 'Oats · Banana');
    });

    test('does NOT read a top-level food_name (the 8b3d4e bug key)', () {
      // The writer never writes a top-level food_name; a reader that did would
      // return "Pizza" here. The fixed reader falls back to meal_type → "Lunch".
      final name = NutritionReadService.deriveMealDisplayName({
        'food_name': 'Pizza',
        'meal_type': 'lunch',
      });
      expect(name, 'Lunch');
      expect(name, isNot('Pizza'));
    });

    test('items[].name wins over any stray top-level food_name', () {
      final name = NutritionReadService.deriveMealDisplayName({
        'items': [
          {'name': 'Oats'},
        ],
        'food_name': 'WRONG',
      });
      expect(name, 'Oats');
    });
  });
}
