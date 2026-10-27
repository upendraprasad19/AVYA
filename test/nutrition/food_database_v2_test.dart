// V2 food database guards (APK Test #3, 2026-04-26).
//
// Pins the contract that the V2 expansion (93 → 1431 items) preserves the
// strict-on-macros filter, all required fields exist on every item, no
// duplicate names exist, and the 12 critical diet-plan anchor names are
// still present.
//
// If a future seed or expansion regresses any of these, the regression
// shows up in test failures BEFORE it ships to users.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<dynamic> foods;

  setUpAll(() {
    final src = File('assets/data/food_database.json').readAsStringSync();
    foods = json.decode(src) as List<dynamic>;
  });

  test('V2 contains at least 1000 items', () {
    expect(foods.length, greaterThanOrEqualTo(1000),
        reason: 'V2 expansion target was ~1500 (achieved ${foods.length})');
  });

  test('every item has all required strict-on-macros fields', () {
    final missing = <String>[];
    for (final raw in foods) {
      final f = raw as Map<String, dynamic>;
      final id = f['id'] as String? ?? '<no-id>';
      final issues = <String>[];
      if ((f['name'] as String? ?? '').length < 3) issues.add('name');
      if ((f['calories_per_100g'] as num?) == null ||
          (f['calories_per_100g'] as num) <= 0) issues.add('calories');
      if (f['protein_per_100g'] == null) issues.add('protein');
      if (f['carbs_per_100g'] == null) issues.add('carbs');
      if (f['fat_per_100g'] == null) issues.add('fat');
      if ((f['standard_serving_g'] as num?) == null ||
          (f['standard_serving_g'] as num) <= 0) issues.add('serving_g');
      if (f['is_veg'] is! bool) issues.add('is_veg');
      if (f['is_vegan'] is! bool) issues.add('is_vegan');
      if (issues.isNotEmpty) missing.add('$id: ${issues.join(",")}');
    }
    expect(missing, isEmpty,
        reason:
            'V2 strict-on-macros filter violations: ${missing.take(10).join("; ")}');
  });

  test('no duplicate names (case-insensitive)', () {
    final seen = <String, int>{};
    for (final raw in foods) {
      final f = raw as Map<String, dynamic>;
      final key = (f['name'] as String).toLowerCase().trim();
      seen[key] = (seen[key] ?? 0) + 1;
    }
    final dupes =
        seen.entries.where((e) => e.value > 1).map((e) => e.key).toList();
    expect(dupes, isEmpty, reason: 'Duplicate names: ${dupes.take(5)}');
  });

  test('all 12 critical diet plan anchor names present', () {
    // diet_plan_generator.dart hardcodes these names in the anchor pools.
    // If V2 ever drops one of them, the diet plan algorithm breaks for
    // some user/diet-preference combo. Keep this test in sync with the
    // _breakfastAnchorNames / _mainAnchorNames / _snackAnchorNames sets.
    final required = {
      'Mutton Curry',
      'Whey Protein (scoop)',
      'Chicken Breast (grilled)',
      'Tofu',
      'Paneer',
      'Greek Yogurt',
      'Egg (Whole, boiled)',
      'Almonds',
      'Peanuts (Roasted)',
      'Sprouts (Mixed)',
      'Toor Dal (cooked)',
      'Rajma (cooked)',
    };
    final names =
        foods.map((f) => (f as Map)['name'] as String).toSet();
    final missing = required.difference(names);
    expect(missing, isEmpty,
        reason: 'Diet plan anchors removed by V2: $missing');
  });

  test('original 93 seed items preserved with original IDs', () {
    final seedItems = foods
        .where((f) => (f as Map)['source'] == 'icanbefitter_seed')
        .toList();
    expect(seedItems.length, equals(93),
        reason: 'V2 must preserve all 93 original seed items');
    final seedIds = seedItems
        .map((f) => (f as Map)['id'] as String)
        .toList()
      ..sort();
    expect(seedIds.first, equals('F0001'));
    expect(seedIds.last, equals('F0093'));
  });

  test('is_veg / is_vegan logical consistency', () {
    // is_vegan implies is_veg (vegan items must also be vegetarian).
    final inconsistent = foods
        .where((f) {
          final m = f as Map;
          return m['is_vegan'] == true && m['is_veg'] != true;
        })
        .map((f) => (f as Map)['name'] as String)
        .toList();
    expect(inconsistent, isEmpty,
        reason:
            'is_vegan=true must imply is_veg=true. Violations: $inconsistent');
  });
}
