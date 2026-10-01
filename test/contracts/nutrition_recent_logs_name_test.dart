import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';

/// Obs 2 (2026-06-05): the Home "Recent Logs" list rendered every food as
/// "Unknown" because the home provider read top-level `food_name`/`meal_name`/
/// `name` — fields the writer (`NutritionWriteService.logMeal`) never writes
/// (names live in `items[].name`). The nutrition Today's-Meals card already
/// derived the name correctly; both readers now share ONE SoT helper
/// (`NutritionReadService.deriveMealDisplayName`) so the name can't drift again.

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('deriveMealDisplayName (Obs 2 — shared SoT, no "Unknown")', () {
    test('items[].name joined — the writer shape', () {
      final meal = {
        'meal_type': 'lunch',
        'items': [
          {'name': 'Dal'},
          {'name': 'Rice'},
        ],
      };
      expect(NutritionReadService.deriveMealDisplayName(meal), 'Dal · Rice');
    });

    test('no items → capitalized meal_type', () {
      final meal = {'meal_type': 'breakfast', 'items': const []};
      expect(NutritionReadService.deriveMealDisplayName(meal), 'Breakfast');
    });

    test('derivation uses items[].name even if a stray top-level field exists',
        () {
      final meal = {
        'food_name': 'STALE',
        'meal_type': 'dinner',
        'items': [
          {'name': 'Paneer'},
        ],
      };
      expect(NutritionReadService.deriveMealDisplayName(meal), 'Paneer');
    });

    test('empty meal → sentinel (NOT "Unknown")', () {
      expect(NutritionReadService.deriveMealDisplayName(const {}),
          NutritionReadService.kFallbackMealName);
      expect(NutritionReadService.kFallbackMealName, isNot('Unknown'));
    });
  });

  group('wiring — both readers use the shared helper', () {
    test('home recent-logs provider uses deriveMealDisplayName + IST + no '
        'food_name read', () {
      final src = _strip(
          File('lib/features/home/providers/home_provider.dart')
              .readAsStringSync());
      expect(
        src.contains('NutritionReadService.deriveMealDisplayName('),
        isTrue,
        reason: 'home recent-logs must use the shared helper (Obs 2)',
      );
      expect(
        src.contains("log['food_name']"),
        isFalse,
        reason: 'the drift read of top-level food_name must be gone',
      );
      expect(
        src.contains('istDateStr('),
        isTrue,
        reason: 'home recent-logs date key must be IST, not local y/m/d',
      );
    });

    test('nutrition Today\'s-Meals card routes through the shared helper', () {
      final src = _strip(
          File('lib/features/nutrition/widgets/todays_meals_card.dart')
              .readAsStringSync());
      expect(
        src.contains('NutritionReadService.deriveMealDisplayName('),
        isTrue,
        reason: 'the card must forward to the shared helper (no private copy '
            'of the derivation logic that could drift)',
      );
    });
  });
}
