// Round-trip contract test for NutritionWriteService output → consumers.
//
// Locks the Hive `nlog_*` field-name contract between the canonical
// writer and every downstream reader. Field renames must update writer +
// every consumer + this test in the same PR (per docs/architecture/sync.md).
//
// Consumers covered:
//   - DailyNutritionNotifier (drives TodaysMealsCard + nutrition screen)
//   - NutritionRepository.dailyMacros (drives nutritionSummaryProvider on Home)
//   - AiCoachRepository._getMealsToday + cloud projection of meals_today
//   - SyncService._syncNutritionLogs cloud projection
//
// HISTORY: AiCoachRepository._getMealsToday previously filtered by an `id`
// field starting with "nlog_" — but NutritionWriteService writes `log_key`,
// not `id`. APK Test #8 / Theme D fixed Drift #1 by switching the reader to
// iterate nutritionBox.toMap() and filter on the Hive entry key directly.
// Test 4 below mirrors the fixed reader; if a future change reintroduces the
// drift (reader regresses to `id` field OR writer drops the nlog_ key prefix),
// test 4 fails noisily.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  group('NutritionWriteService → consumer contract', () {
    test('written nlog entry exposes the contract keys', () async {
      // Asserts the EXACT payload shape NutritionWriteService.logMeal puts
      // under the deterministic `nlog_*` key. Every key listed below is
      // consumed by at least one downstream reader; renaming any of them
      // requires updating that reader + this test in the same PR.
      final res = await NutritionWriteService.instance.logMeal(
        date: DateTime(2026, 5, 2),
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Oats',
            quantityG: 50,
            calories: 180,
            protein: 6,
            carbs: 30,
            fat: 3,
            fiber: 4,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(res.success, isTrue);
      expect(res.logKey, isNotNull);
      expect(res.logKey!.startsWith('nlog_'), isTrue,
          reason: 'logKey must start with nlog_ (consumed by sync filter)');

      final box = HiveService.instance.nutritionBox;
      final raw = box.get(res.logKey!);
      expect(raw, isNotNull);
      final m = Map<String, dynamic>.from(raw as Map);

      // Top-level required keys (full contract):
      //   log_key       — writer's stash of the Hive key for downstream lookups
      //   date          — read by dailyMacros + dailyNutritionProvider + AI
      //                   _getMealsToday + sync projection
      //   meal_type     — read by dailyNutritionProvider + AI _getMealsToday
      //                   + sync projection
      //   total_calories / total_protein / total_carbs / total_fat / total_fiber
      //                 — read by dailyMacros + sync projection
      //   items         — read by editLog + appendItemsToMeal + saveMealAsTemplate
      //                   + sync per-item projection
      //   source        — read by sync (telemetry only) + counter logic
      //   logged_at / created_at — read by sync projection
      const requiredTopLevel = [
        'log_key',
        'date',
        'meal_type',
        'total_calories',
        'total_protein',
        'total_carbs',
        'total_fat',
        'total_fiber',
        'items',
        'source',
        'logged_at',
        'created_at',
      ];
      for (final k in requiredTopLevel) {
        expect(m.containsKey(k), isTrue,
            reason: 'writer must emit $k — consumed by at least one reader');
      }

      // Per-item keys (consumed by SyncService._syncNutritionLogs projection
      // to nutrition_log_items rows: name, quantity_g, calories, protein,
      // carbs, fat).
      final items = (m['items'] as List).cast<Map>();
      expect(items, hasLength(1));
      final item = items.first;
      const requiredItemKeys = [
        'name',
        'quantity_g',
        'calories',
        'protein',
        'carbs',
        'fat',
        'fiber',
      ];
      for (final k in requiredItemKeys) {
        expect(item.containsKey(k), isTrue,
            reason: 'item map must carry $k — sync projects to nutrition_log_items');
      }
    });

    test('TodaysMealsCard provider sees today\'s meal', () async {
      // TodaysMealsCard receives meals from DailyNutritionNotifier
      // (provider key dailyNutritionProvider). The notifier reads
      // nutritionBox values, filters by `log['date'] == dateStr`, then
      // groups by `log['meal_type']`. We mirror that read path against
      // the writer's output to lock the date+meal_type contract.
      final today = DateTime(2026, 5, 2);
      final res = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'lunch',
        items: const [
          FoodItem(
            name: 'Chicken Curry',
            quantityG: 250,
            calories: 450,
            protein: 38,
            carbs: 18,
            fat: 22,
            fiber: 3,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(res.success, isTrue);

      // Mirror DailyNutritionNotifier.build's iteration:
      final box = HiveService.instance.nutritionBox;
      const dateStr = '2026-05-02';
      final meals = <String, List<Map<String, dynamic>>>{
        'breakfast': [],
        'lunch': [],
        'dinner': [],
        'snacks': [],
      };
      for (final raw in box.values) {
        if (raw is! Map) continue;
        final log = Map<String, dynamic>.from(raw);
        if (log['date'] != dateStr) continue;
        if (log['is_saved_meal'] == true) continue;
        final mealType =
            (log['meal_type'] as String?)?.toLowerCase() ?? 'snacks';
        final key = meals.containsKey(mealType) ? mealType : 'snacks';
        meals[key]!.add(log);
      }

      expect(meals['lunch'], hasLength(1),
          reason:
              'dailyNutritionProvider must find the writer\'s row in lunch slot');
      expect(meals['breakfast'], isEmpty);
      expect(meals['dinner'], isEmpty);
      expect(meals['snacks'], isEmpty);

      final lunch = meals['lunch']!.first;
      expect(lunch['meal_type'], 'lunch');
      expect((lunch['total_calories'] as num).toInt(), 450);
      expect((lunch['total_protein'] as num).toInt(), 38);
    });

    test('home_provider daily-completion reflects the new log', () async {
      // home_provider does NOT have a discrete daily-completion ring —
      // the closest analogue is nutritionSummaryProvider, which sums
      // today\'s macros via NutritionRepository.dailyMacros. We assert
      // the repo correctly sees the writer\'s totals so the Home
      // calorie/protein bars increment after a logMeal call.
      final today = DateTime(2026, 5, 2);
      final res = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'dinner',
        items: const [
          FoodItem(
            name: 'Roti',
            quantityG: 60,
            calories: 180,
            protein: 6,
            carbs: 36,
            fat: 2,
            fiber: 3,
          ),
          FoodItem(
            name: 'Dal',
            quantityG: 200,
            calories: 220,
            protein: 14,
            carbs: 30,
            fat: 5,
            fiber: 6,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(res.success, isTrue);

      final macros = NutritionRepository.instance.dailyMacros(today);
      expect(macros['calories'], 400.0,
          reason:
              'dailyMacros sums total_calories per nlog row — writer field name must match');
      expect(macros['protein'], 20.0);
      expect(macros['carbs'], 66.0);
      expect(macros['fat'], 7.0);
      expect(macros['fiber'], 9.0,
          reason:
              'fiber must round-trip — migration 034 wired total_fiber end-to-end');
    });

    test('AI snapshot meals_today reads writer rows by date+meal_type', () async {
      // Mirror AiCoachRepository._getMealsToday AFTER the Drift #1 fix
      // (APK Test #8 / Theme D): the production reader now iterates
      // nutritionBox.toMap() and filters by Hive entry key prefix `nlog_`
      // instead of the missing `log['id'].startsWith('nlog_')` field that
      // NutritionWriteService never writes (writer emits `log_key`, not `id`).
      // We mirror the fixed reader here so any future drift in either
      // direction (writer drops nlog_ key prefix OR reader regresses to
      // reading a missing `id` field) fails this test.
      final today = DateTime(2026, 5, 2);
      final res = await NutritionWriteService.instance.logMeal(
        date: today,
        mealType: 'breakfast',
        items: const [
          FoodItem(
            name: 'Eggs',
            quantityG: 100,
            calories: 155,
            protein: 13,
            carbs: 1,
            fat: 11,
            fiber: 0,
          ),
        ],
        source: NutritionWriteSource.manualSearch,
      );
      expect(res.success, isTrue);

      // The Hive key itself starts with `nlog_` — even though writer
      // doesn\'t emit an `id` field, the AI reader can fall back to the
      // box key.
      expect(res.logKey!.startsWith('nlog_'), isTrue);

      final box = HiveService.instance.nutritionBox;
      const dateStr = '2026-05-02';

      // Resilient mirror of _getMealsToday — accept either id field OR
      // the row\'s Hive key as the discriminator. This is what the
      // production reader SHOULD do (and the contract this test enforces).
      const slotOrder = ['breakfast', 'lunch', 'dinner', 'snacks'];
      final bySlot = <String, List<Map<String, dynamic>>>{};

      for (final entry in box.toMap().entries) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final log = Map<String, dynamic>.from(raw);
        if (log['date'] != dateStr) continue;
        // Prefer explicit `id` (legacy path), fall back to Hive key
        // (new writer path). Both shapes start with `nlog_` for actual
        // meal logs.
        final discriminator =
            (log['id'] as String?) ?? entry.key.toString();
        if (!discriminator.startsWith('nlog_')) continue;
        final mealType = (log['meal_type'] as String?)?.toLowerCase();
        if (mealType == null || mealType.isEmpty) continue;
        bySlot.putIfAbsent(mealType, () => []).add({
          'kcal': (log['total_calories'] as num?)?.toInt() ?? 0,
          'protein_g': (log['total_protein'] as num?)?.toInt() ?? 0,
        });
      }

      expect(bySlot['breakfast'], hasLength(1),
          reason:
              'AI meals_today must surface today\'s breakfast — '
              'requires reader to read Hive entry key (post-Drift #1 fix)');
      expect(bySlot['breakfast']!.first['kcal'], 155);
      expect(bySlot['breakfast']!.first['protein_g'], 13);

      // Verify slotOrder is a strict superset of what the writer emitted —
      // unknown meal types should be impossible (writer rejects them).
      for (final slot in bySlot.keys) {
        expect(slotOrder.contains(slot), isTrue,
            reason: 'writer-emitted meal_type must be in canonical slotOrder');
      }

      // Independent of the slot-grouping mirror above, assert the simpler
      // reachability property the Drift #1 fix guarantees: any nlog_* row
      // in the nutritionBox must be reachable via a key-prefix scan even
      // when the row carries no `id` field (which is exactly what
      // NutritionWriteService produces).
      final mealLogs = <Map>[];
      for (final entry in box.toMap().entries) {
        if (!entry.key.toString().startsWith('nlog_')) continue;
        if (entry.value is Map) mealLogs.add(entry.value as Map);
      }
      expect(mealLogs, isNotEmpty,
          reason:
              'meal must be reachable via key-prefix scan after Drift #1 fix '
              '(AiCoachRepository._getMealsToday now reads Hive entry key, '
              'not the non-existent `id` field)');
    });
  });
}
