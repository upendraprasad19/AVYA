// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md §2.3.2, §3, T3):
// DietPlanGenerator.passesDiet with the five food types.
//
// Two row sets, each pinned: values whose result is UNCHANGED from before
// Unit 2a, and values that are STRICTER by design (pescatarian, eggetarian,
// unknown and whitespace variants used to pass everything).
//
// Mutations: drop the egg exception (eggetarian + family egg on the
// blocklisted 'Egg (Whole, boiled)' reddens); let pescatarian take chicken;
// map unknown to non-veg (the xyz rows redden).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';

void main() {
  // Real names and tags from assets/data/food_database.json.
  const chicken = {'name': 'Chicken Curry', 'is_veg': false, 'is_vegan': false};
  const egg = {'name': 'Egg (Whole, boiled)', 'is_veg': false, 'is_vegan': false};
  const fish = {'name': 'Fish Curry', 'is_veg': false, 'is_vegan': false};
  const paneer = {'name': 'Paneer Bhurji', 'is_veg': true, 'is_vegan': false};
  const dal = {'name': 'Toor Dal (cooked)', 'is_veg': true, 'is_vegan': true};

  bool p(Map<String, Object> row, String pref, [DietFamily? f]) =>
      DietPlanGenerator.passesDiet(Map<String, dynamic>.from(row), pref,
          family: f);

  group('unchanged from before Unit 2a', () {
    for (final pref in ['non_veg', 'non-veg', 'keto', '']) {
      test('$pref passes everything', () {
        for (final r in [chicken, egg, fish, paneer, dal]) {
          expect(p(r, pref), isTrue, reason: '${r['name']}');
        }
      });
    }
    for (final pref in ['veg', 'vegetarian']) {
      test('$pref: no meat, fish or egg; dairy and dal pass', () {
        expect(p(chicken, pref), isFalse);
        expect(p(egg, pref), isFalse);
        expect(p(fish, pref), isFalse);
        expect(p(paneer, pref), isTrue);
        expect(p(dal, pref), isTrue);
        // A family never widens veg.
        expect(p(egg, pref, DietFamily.egg), isFalse);
      });
    }
    test('vegan: only is_vegan rows', () {
      expect(p(paneer, 'vegan'), isFalse);
      expect(p(dal, 'vegan'), isTrue);
      expect(p(egg, 'vegan', DietFamily.egg), isFalse);
      expect(p(fish, 'vegan', DietFamily.fish), isFalse);
    });
  });

  group('stricter by design', () {
    test('eggetarian: egg family passes before BOTH veg checks', () {
      // 'Egg (Whole, boiled)' is is_veg false AND on the _nonVegNames list.
      expect(p(egg, 'eggetarian', DietFamily.egg), isTrue);
      expect(p(paneer, 'eggetarian'), isTrue);
      expect(p(fish, 'eggetarian', DietFamily.fish), isFalse);
      expect(p(chicken, 'eggetarian', DietFamily.chicken), isFalse);
      // Legacy path (no family): the veg rule, never meat.
      expect(p(egg, 'eggetarian'), isFalse);
      expect(p(chicken, 'eggetarian'), isFalse);
    });
    test('pescatarian: egg and fish families pass; never chicken or mutton', () {
      expect(p(fish, 'pescatarian', DietFamily.fish), isTrue);
      expect(p(egg, 'pescatarian', DietFamily.egg), isTrue);
      expect(p(chicken, 'pescatarian', DietFamily.chicken), isFalse);
      expect(p(chicken, 'pescatarian', DietFamily.mutton), isFalse);
      expect(p(fish, 'pescatarian'), isFalse, reason: 'legacy: veg rule');
      expect(p(dal, 'pescatarian'), isTrue);
    });
    for (final pref in ['xyz', 'flexitarian', 'veg ', 'VEG']) {
      test('"$pref" reads as veg', () {
        expect(p(chicken, pref), isFalse);
        expect(p(egg, pref, DietFamily.egg), isFalse);
        expect(p(paneer, pref), isTrue);
      });
    }
  });
}
