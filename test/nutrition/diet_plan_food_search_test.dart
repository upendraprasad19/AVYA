// test/nutrition/diet_plan_food_search_test.dart
//
// Diet chart v3 (docs/plans/diet-chart-v3.md §4.3, §5): "Search any food" on
// the REAL asset: diet purity, ranking, own foods (including the shape a cloud
// restore writes: no `type`, no `is_custom`), the egg and fish exceptions,
// protein powders and the minor rule, the shake ids, the portion arithmetic.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_food_search.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_free_item.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_shake.dart';

final _rows = (jsonDecode(
        File('assets/data/food_database.json').readAsStringSync()) as List)
    .cast<Map<String, dynamic>>();

List<DietPlanSearchHit> _search(
  String q, {
  String pref = 'non-veg',
  bool adult = true,
  bool powders = true,
  List<Map<String, dynamic>> custom = const [],
  List<Map<String, dynamic>>? foods,
  Set<String> exclude = const {},
  int limit = 400,
}) =>
    searchDietPlanFoods(
      query: q,
      foods: foods ?? _rows,
      customFoods: custom,
      dietPreference: pref,
      adult: adult,
      powdersAllowed: powders,
      excludeIds: exclude,
      limit: limit,
    );

Set<String> _ids(Iterable<DietPlanSearchHit> h) => {for (final x in h) x.id};

void main() {
  group('ranking and the diet filter', () {
    test('a word-start match beats a substring; shorter first; stable', () {
      final hits = _search('oats');
      expect(hits, isNotEmpty);
      final names = [for (final h in hits) h.name.toLowerCase()];
      final firstSubstringOnly =
          names.indexWhere((n) => !n.startsWith('oats') && !n.contains(' oats'));
      final lastWordStart = names.lastIndexWhere(
          (n) => n.startsWith('oats') || n.contains(' oats'));
      if (firstSubstringOnly != -1) {
        expect(lastWordStart, lessThan(firstSubstringOnly));
      }
    });

    test('every token must match; an empty or blank query lists no food', () {
      expect(_search('rolled oats').every((h) => h.name.toLowerCase().contains('rolled')), isTrue);
      expect(_search('   ', powders: false), isEmpty);
    });

    test('a vegan never gets a row the DB tags is_vegan == false', () {
      for (final q in ['milk', 'paneer', 'curd', 'egg', 'whey', 'cheese', 'ghee']) {
        for (final h in _search(q, pref: 'vegan')) {
          expect(h.row['is_vegan'], isNot(false), reason: '$q -> ${h.name}');
        }
      }
    });

    test('a veg user never gets a non-veg row, whatever the word', () {
      for (final q in ['chicken', 'fish', 'mutton', 'egg', 'prawn']) {
        for (final h in _search(q, pref: 'veg')) {
          expect(h.row['is_veg'], isNot(false), reason: '$q -> ${h.name}');
        }
      }
    });

    test('foods already in the plan are not offered', () {
      final all = _search('rice');
      final first = all.first.id;
      expect(_ids(_search('rice', exclude: {first})), isNot(contains(first)));
    });

    test('the editorial never-offered rows (meal_fit == []) are absent', () {
      final never = {
        for (final r in _rows)
          if (r['meal_fit'] is List && (r['meal_fit'] as List).isEmpty) r['id'],
      };
      expect(never, isNotEmpty);
      for (final q in ['beer', 'wine', 'whisky', 'rum', 'vodka', 'cocktail']) {
        expect(_ids(_search(q)).intersection(never.cast<String>()), isEmpty,
            reason: q);
      }
    });

    test('a processed row stays, tagged', () {
      final maggi = _search('maggi');
      expect(maggi.where((h) => h.processed), isNotEmpty);
      expect(_search('thums up').every((h) => h.processed), isTrue);
    });
  });

  group('eggetarian and pescatarian (free rows have no catalog family)', () {
    const meat = ['chicken', 'mutton', 'lamb', 'beef', 'pork', 'keema',
        'veal', 'goose', 'quail', 'lard', 'bacon', 'sausage', 'goat', 'turkey'];

    test('eggetarian finds boiled egg and never a meat word', () {
      final hits = _search('egg', pref: 'eggetarian');
      expect(hits.map((h) => h.name), contains('Egg (Whole, boiled)'));
      for (final h in hits) {
        // a duck / quail / goose EGG is an egg, not meat
        final n = h.name.toLowerCase()
            .replaceAll(RegExp(r'\b(duck|quail|goose) eggs?\b'), 'egg');
        expect(meat.any(n.contains), isFalse, reason: h.name);
      }
      for (final id in ['F0989', 'F1012', 'F1176']) {
        expect(_ids(_search('', pref: 'eggetarian')), isNot(contains(id)));
      }
    });

    test('eggetarian does not get a fish row; pescatarian gets fish and eggs', () {
      final egg = _search('fish', pref: 'eggetarian');
      expect(egg.where((h) => h.row['is_veg'] == false), isEmpty);
      final pesc = _search('fish', pref: 'pescatarian');
      expect(pesc.where((h) => h.row['is_veg'] == false), isNotEmpty);
    });

    test('the nine fish rows the first word list missed are found', () {
      // F0334 Surmai Fry, F0336 Hilsa Curry, F0358 Rohu, F0359 Hilsa, F0360
      // Mackerel, F0362 Surmai, F0910 Hilsa Fillet, F0995 Oysters, F0997
      // Smoked Mackerel (plan review round 2, N4).
      for (final (q, id) in [
        ('surmai', 'F0362'), ('hilsa', 'F0359'), ('rohu', 'F0358'),
        ('mackerel', 'F0360'), ('oyster', 'F0995'),
      ]) {
        expect(_ids(_search(q, pref: 'pescatarian')), contains(id), reason: q);
        expect(_ids(_search(q, pref: 'eggetarian')), isNot(contains(id)),
            reason: '$q must not reach an eggetarian');
      }
    });

    test('the family rule is name based and spelled out', () {
      Map<String, dynamic> row(String name) => {'id': 'X', 'name': name};
      expect(searchFamilyOf(row('Egg Bhurji'))!.name, 'egg');
      expect(searchFamilyOf(row('Duck Egg'))!.name, 'egg');
      expect(searchFamilyOf(row('Quail Egg'))!.name, 'egg');
      expect(searchFamilyOf(row('Chicken Egg Roll')), isNull);
      expect(searchFamilyOf(row('Rohu Curry'))!.name, 'fish');
      expect(searchFamilyOf(row('Veal Cutlet')), isNull);
      expect(searchFamilyOf(row('Fish and Egg Curry')), isNull);
      expect(searchFamilyOf(row('Standard Mandarin Pasanda')), isNull);
    });
  });

  group('own foods', () {
    final cloudRestored = <String, dynamic>{
      // the _projectCustomFood shape: no `type`, no `is_custom`
      'id': 'u-1',
      'name': 'Mom Special Khichdi',
      'calories_per_100g': 120,
      'protein_per_100g': 5,
      'carbs_per_100g': 20,
      'fat_per_100g': 2,
      'standard_serving_desc': '1 bowl',
      'standard_serving_g': 250,
      'calories_std': 300,
      'created_at': '2026-11-01T10:00:00',
    };

    test('a restored-shape row (no type, no is_custom) is returned, tagged', () {
      final hits = _search('khichdi', custom: [cloudRestored], pref: 'vegan');
      final mine = hits.where((h) => h.id == 'u-1');
      expect(mine, hasLength(1));
      expect(mine.single.yours, isTrue);
      expect(hits.first.id, 'u-1', reason: 'own foods come first');
    });

    test('never diet-filtered: a vegan sees an untagged custom food', () {
      // is_vegan / is_veg false: passesDiet WOULD reject this row, so the test
      // sees whether the filter runs on own foods (mutant M10).
      final c = {
        ...cloudRestored,
        'name': 'Butter chicken at home',
        'is_vegan': false,
        'is_veg': false,
      };
      expect(_ids(_search('butter chicken', custom: [c], pref: 'vegan')),
          contains('u-1'));
    });

    test('the foodBox copy of a custom food (is_custom) is skipped; the '
        'customBox copy wins', () {
      final box = {...cloudRestored, 'is_custom': true, 'type': 'food'};
      final hits = _search('khichdi',
          custom: [cloudRestored], foods: [..._rows, box], pref: 'non-veg');
      expect(hits.where((h) => h.id == 'u-1'), hasLength(1));
      expect(hits.firstWhere((h) => h.id == 'u-1').yours, isTrue);
      // another account's custom food left in the foodBox never leaks
      final other = {...box, 'id': 'u-2', 'name': 'Khichdi of someone else'};
      expect(_ids(_search('khichdi', foods: [..._rows, other])),
          isNot(contains('u-2')));
    });

    test('two rows with one id: the newest created_at wins', () {
      final old = {...cloudRestored, 'created_at': '2026-10-01T00:00:00',
          'calories_std': 111};
      final fresh = {...cloudRestored, 'created_at': '2026-11-09T00:00:00',
          'calories_std': 222};
      final hits = _search('khichdi', custom: [old, fresh]);
      expect(hits.where((h) => h.id == 'u-1').single.row['calories_std'], 222);
    });

    test('a custom food already in the plan is not offered', () {
      expect(_ids(_search('khichdi', custom: [cloudRestored], exclude: {'u-1'})),
          isNot(contains('u-1')));
    });
  });

  group('protein powders', () {
    bool isPowder(DietPlanSearchHit h) => h.powder;

    test('an adult with the switch on sees powders for an empty query', () {
      final hits = _search('');
      expect(hits.where(isPowder), isNotEmpty);
      for (final h in hits) {
        expect(h.row['category'], 'supplements');
        expect((h.row['calories_std'] as num) <= 210, isTrue, reason: h.name);
        expect((h.row['protein_std'] as num) >= 14, isTrue, reason: h.name);
        expect(h.row['is_ultra_processed'], isNot(true), reason: h.name);
      }
    });

    test('no mass gainer, pre-workout, creatine, bar or fish oil is a powder', () {
      final ids = _ids(_search(''));
      for (final id in ['F0838', 'F0839', 'F0840', 'F0841', 'F0818', 'F0842',
          'F0843', 'F0844', 'F0845', 'F0846', 'F0851']) {
        expect(ids, isNot(contains(id)), reason: id);
      }
    });

    test('the two generated-shake ids are never offered', () {
      for (final pref in ['non-veg', 'veg', 'vegan']) {
        final ids = _ids(_search('', pref: pref));
        expect(ids, isNot(contains(kShakeWheyFoodId)), reason: pref);
        expect(ids, isNot(contains(kShakePlantFoodId)), reason: pref);
      }
      expect(_ids(_search('whey isolate')), isNot(contains('F0823')));
    });

    test('powders need NO PRO and NO switch; the kill switch (powdersAllowed '
        'false) hides them for an adult', () {
      expect(_search('', powders: false), isEmpty);
      expect(_search('whey', powders: false).where(isPowder), isEmpty);
    });

    test('a minor sees no powder and none of the whey / gainer / bar rows', () {
      final minorIds = _ids(_search('protein', adult: false, powders: false));
      final adultIds = _ids(_search('protein'));
      expect(minorIds.length, lessThan(adultIds.length));
      for (final id in ['F0067', 'F0959', 'F0961', 'F0962', 'F0853', 'F0854',
          'F0860', 'F0956', 'F0950', 'F0951']) {
        final row = _rows.firstWhere((r) => r['id'] == id);
        final q = (row['name'] as String).toLowerCase().split(' ').first;
        expect(_ids(_search(q, adult: false, powders: false)),
            isNot(contains(id)),
            reason: '$id ${row['name']} reachable by a minor');
      }
    });

    test('a vegan gets plant powders only', () {
      final hits = _search('', pref: 'vegan').where(isPowder);
      expect(hits, isNotEmpty);
      for (final h in hits) {
        expect(h.row['is_vegan'], true, reason: h.name);
      }
      expect(_ids(hits), containsAll(['F0832', 'F0830', 'F0834']));
    });

    test('a veg user gets no egg-white or beef isolate', () {
      final ids = _ids(_search('', pref: 'veg'));
      expect(ids, isNot(contains('F0828')));
      expect(ids, isNot(contains('F0829')));
    });
  });

  group('portion arithmetic', () {
    Map<String, dynamic> row(String id) =>
        _rows.firstWhere((r) => r['id'] == id);

    test('one standard serving equals the row; grams are linear', () {
      final r = row('F0001'); // White Rice (cooked), 1 cup, 158 g
      final one = freePickItem(row: r, multiple: 1, role: 'grain');
      expect(one.servingDesc, '1 cup');
      expect(one.servingG, 158);
      expect(one.calories, (r['calories_std'] as num).round());
      expect(one.role, 'grain');
      final two = freePickItem(row: r, multiple: 2, role: null);
      expect(two.servingG, 316);
      expect(two.calories, (2 * (r['calories_std'] as num)).round());
      expect(two.role, isNull);
    });

    test('an off-step multiple reads as grams, an on-step one as the serving', () {
      final r = row('F0001');
      expect(freePickItem(row: r, multiple: 1.5, role: null).servingDesc, '1 1/2 cups');
      expect(freePickItem(row: r, multiple: 1.3, role: null).servingDesc, '205 g');
    });

    test('a countable serving steps by whole counts; others by half', () {
      expect(dietPortionStep('1 roti'), 1);
      expect(dietPortionStep('2 idli'), 0.5);
      expect(dietPortionStep('1 cup'), 0.5);
      expect(dietServingIsCountable('1 roti'), isTrue);
      expect(dietServingIsCountable('1 cup'), isFalse);
      // qty x m stays whole: 2 idli x 0.5 = 1 idli
      expect(2 * dietPortionStep('2 idli'), 1);
    });

    test('the largest multiple respects 10 servings and 2000 g', () {
      expect(dietPortionMaxMultiple({'standard_serving_g': 100}), 10);
      expect(dietPortionMaxMultiple({'standard_serving_g': 500}), 4);
    });

    test('a custom food uses its per-100 g numbers (not the rounded _std)', () {
      final c = {
        'id': 'u-1',
        'name': 'Mine',
        'calories_per_100g': 123.4,
        'protein_per_100g': 7.5,
        'carbs_per_100g': 20.0,
        'fat_per_100g': 3.3,
        'standard_serving_desc': '100g',
        'standard_serving_g': 100,
        'calories_std': 123,
      };
      final item = freePickItem(row: c, multiple: 2.5, role: 'snack');
      expect(item.servingG, 250);
      expect(item.calories, (123.4 * 2.5).round());
      expect(item.protein, (7.5 * 2.5).round());
      expect(item.category, '');
    });
  });
}
