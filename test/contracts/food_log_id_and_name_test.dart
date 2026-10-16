// APK Test #12.6 / Obs 7 — pin: NutritionWriteService writes `id` field
// (additive in 12.6) so consumers' `meal['id']` reads succeed; readers
// derive display name from `items[].name` join (canonical) instead of
// the nonexistent `food_name` field.
//
// History: founder install of APK 12.5 saw breakfast logged as "Unknown"
// + edit silently no-op. Two bugs in one — readers expected `food_name`
// + `id` fields that the canonical writer never produces.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('NutritionWriteService payload — Obs 7 fixes', () {
    test('logMeal writes both `id` and `log_key` fields with same value',
        () async {
      final result = await NutritionWriteService.instance.logMeal(
        date: DateTime(2026, 5, 7),
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Idli',
            quantityG: 80,
            calories: 158,
            protein: 5,
            carbs: 32,
            fat: 1,
            fiber: 2,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(result.success, isTrue);
      final logKey = result.logKey;
      expect(logKey, isNotNull);

      final box = HiveService.instance.nutritionBox;
      final row = box.get(logKey) as Map;
      expect(row['id'], logKey,
          reason:
              'Test #12.6 — id must equal log_key so legacy readers '
              '(meal["id"]) work without a separate field rename.');
      expect(row['log_key'], logKey,
          reason: 'Canonical Hive contract field per docs/architecture/sync.md.');
    });

    test('per-item entries carry name, calories, protein (canonical names)',
        () async {
      final result = await NutritionWriteService.instance.logMeal(
        date: DateTime(2026, 5, 7),
        mealType: 'lunch',
        items: const [
          FoodItem(
            name: 'Roti',
            quantityG: 60,
            calories: 180,
            protein: 6,
            carbs: 36,
            fat: 1,
            fiber: 4,
          ),
          FoodItem(
            name: 'Dal',
            quantityG: 150,
            calories: 200,
            protein: 12,
            carbs: 28,
            fat: 4,
            fiber: 5,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(result.success, isTrue);

      final box = HiveService.instance.nutritionBox;
      final row = box.get(result.logKey) as Map;
      final items = row['items'] as List;
      expect(items, hasLength(2));

      final first = items.first as Map;
      expect(first['name'], 'Roti',
          reason: 'Per-item field name is `name` (NOT `food_name`).');
      expect(first['calories'], 180,
          reason: 'Per-item field name is `calories` (NOT `total_calories`).');
      expect(first['protein'], 6);
      expect(first.containsKey('food_name'), isFalse,
          reason:
              'Pre-fix readers expected `food_name` — the writer never wrote it. '
              'Test ensures we did not regress to writing the wrong field.');
    });
  });
}
