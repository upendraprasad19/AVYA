// test/contracts/nutrition_write_service_ist_anchored_test.dart
//
// Drift-fix batch 2026-05-24 / F1 nutrition (P0).
//
// `NutritionWriteService.computeLogKey` parameter `istDate` asserts
// the caller pre-shifts to IST, but 7 production callers pass raw
// `DateTime.now()` (device-local). On any device in a timezone west
// of IST, a meal logged just past local midnight would produce a
// Hive key with yesterday's IST date — but readers (TodaysMealsCard,
// _getMealsToday) use `istDateStr(DateTime.now())` so the meal would
// vanish from "Today's Meals."
//
// This test pins the fix: `computeLogKey` MUST internally route
// through `istDateStr(date)` from lib/core/utils/ist_date.dart so
// the parameter-name assertion is no longer a load-bearing caller
// contract.
//
// Test design: pass a UTC instant that crosses the IST date boundary
// (UTC May 24 22:00 = IST May 25 03:30). The Hive key must reflect
// IST's date, not UTC's.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

void main() {
  group('NutritionWriteService IST anchoring', () {
    test('computeLogKey resolves IST date from UTC input crossing midnight', () {
      // UTC 2026-05-24 22:00 == IST 2026-05-25 03:30.
      final utcLate = DateTime.utc(2026, 5, 24, 22, 0);

      final key = NutritionWriteService.computeLogKey(
        istDate: utcLate,
        mealType: 'breakfast',
        items: [
          FoodItem(
            name: 'Test',
            quantityG: 100,
            calories: 100,
            protein: 10,
            carbs: 10,
            fat: 5,
            fiber: 2,
          ),
        ],
      );

      // Must use IST's date (2026-05-25), not UTC's (2026-05-24).
      expect(
        key.startsWith('nlog_2026-05-25_'),
        isTrue,
        reason:
            'computeLogKey must IST-anchor the date. Got key="$key" — '
            'expected prefix "nlog_2026-05-25_". If this assertion '
            'fails with "nlog_2026-05-24_" the fix has not been '
            'applied: replace hand-built `\${date.year}-...` with '
            '`istDateStr(date)` from lib/core/utils/ist_date.dart.',
      );
    });

    test('computeLogKey resolves IST date from device-local DateTime far from midnight', () {
      // Mid-afternoon — should never produce date confusion regardless
      // of the device's local timezone.
      final localAfternoon = DateTime(2026, 5, 24, 14, 0);
      final key = NutritionWriteService.computeLogKey(
        istDate: localAfternoon,
        mealType: 'lunch',
        items: [
          FoodItem(
            name: 'X',
            quantityG: 50,
            calories: 50,
            protein: 5,
            carbs: 5,
            fat: 2,
            fiber: 1,
          ),
        ],
      );

      // istDateStr applies istDateOf which converts to UTC then shifts
      // +5:30. For a local DateTime in IST, the IST date is unchanged.
      // For a local DateTime in UTC, 2026-05-24 14:00 UTC becomes
      // 2026-05-24 19:30 IST — still 2026-05-24. Either way: 2026-05-24.
      expect(key.startsWith('nlog_2026-05-24_'), isTrue,
        reason: 'mid-afternoon log should always reflect the same '
            'IST date as the input. Got key="$key"');
    });

    // Drift-fix batch 2026-05-24 / F1 nutrition (P0) — extension.
    //
    // Sweep-gap regression test per `feedback_ist_sweep_gap.md` —
    // IST migrations recurrently miss 2-3 sites on the first pass.
    // The initial F1 fix patched `logMeal` (line 88) + `computeLogKey`
    // (line 740) but missed `logWater` (line 401) which had the same
    // hand-rolled `${date.year.toString().padLeft(4, '0')}-...` shape.
    //
    // This grep test catches every future same-class regression on
    // this file without requiring a Hive harness — extends the
    // [[feedback_source_grep_false_confidence]] rule (source-grep is
    // valid as a sweep-gap defence; behavioral tests above pin
    // semantics).
    test('nutrition_write_service.dart has zero hand-rolled date string assemblies', () {
      final src = File('lib/core/services/nutrition_write_service.dart')
          .readAsStringSync();

      // Strip `// ...` line comments so an explanatory comment that
      // quotes the old anti-pattern doesn't false-positive — per
      // `feedback_source_grep_strip_comments_first.md`.
      final stripped = src.split('\n').map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      }).join('\n');

      // Pattern: `.year.toString().padLeft(4, '0')` shape.
      // Any DateTime variable being decomposed via .year/.month/.day +
      // padLeft is a hand-rolled date assembly that bypasses IST shift.
      final pattern = RegExp(r"\.year\.toString\(\)\.padLeft");
      expect(
        pattern.hasMatch(stripped),
        isFalse,
        reason: 'Hand-rolled date assembly found in '
            'nutrition_write_service.dart. Use istDateStr(<var>) from '
            'lib/core/utils/ist_date.dart. See drift-fix batch '
            '2026-05-24 / F1 nutrition (P0).',
      );
    });
  });
}
