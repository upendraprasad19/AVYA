// OI-517: the Portions / Grams label function (docs/plans/diet-grams-toggle.md
// sections 3 and 6). Pure, so every shape of the real asset is a fixture.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart'
    show scaleServingDesc;
import 'package:icanbefitter/features/nutrition/services/diet_serving_label.dart';

const g = DietServingView.grams;
const p = DietServingView.portions;

void main() {
  final rows = (jsonDecode(File('assets/data/food_database.json')
          .readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  group('table', () {
    test('plain, count, volume and oz', () {
      expect(servingLabel('1 cup', 158, g), '158 g (1 cup)');
      expect(servingLabel('2 idli', 60, g), '60 g (2 idli)');
      expect(servingLabel('1 egg', 50, g), '50 g (1 egg)');
      expect(servingLabel('1 oz', 28, g), '28 g (1 oz)');
      expect(servingLabel('1/2 cup', 40, g), '40 g (1/2 cup)');
    });
    test('a leading gram or ml figure shows once', () {
      expect(servingLabel('100g', 100, g), '100 g');
      expect(servingLabel('100 g', 150, g), '150 g');
      expect(servingLabel('250 ml', 250, g), '250 ml');
      expect(servingLabel('200mL', 200, g), '200 ml');
    });
    test('a gram or ml bracket is stripped, never nested or doubled', () {
      expect(servingLabel('1 packet (52g)', 52, g), '52 g (1 packet)');
      expect(servingLabel('1 portion (150 g)', 150, g), '150 g (1 portion)');
      expect(servingLabel('1 peg (60ml)', 60, g), '60 ml (1 peg)');
      expect(servingLabel('1 can (330 ml)', 330, g), '330 ml (1 can)');
      expect(servingLabel('0.667 cup (170 g)', 170, g), '170 g (0.667 cup)');
    });
    test('a non-gram bracket moves inside', () {
      expect(servingLabel('1 cup (2 eggs)', 200, g), '200 g (1 cup, 2 eggs)');
      expect(servingLabel('13g (6 biscuits)', 13, g), '13 g (6 biscuits)');
    });
    test('a bare number or an unparseable desc gives grams only', () {
      expect(servingLabel('180', 100, g), '100 g');
      expect(servingLabel('52.3', 100, g), '100 g');
      expect(servingLabel('2 × 1 packet (52g)', 104, g), '104 g');
      expect(servingLabel('', 100, g), '100 g');
    });
    test('custom free text: never doubled, nested, empty or a tiny 0 g', () {
      // B-pass seat B (B1-B4): a bracket-only desc, a weight restated in or
      // beside a bracket, other spellings of grams, a weight with words after it.
      expect(servingLabel('(2 eggs)', 50, g), '50 g (2 eggs)');
      expect(servingLabel('1 cup (150g) (2 eggs)', 200, g), '200 g (1 cup, 2 eggs)');
      expect(servingLabel('1 cup (200 g, 2 eggs)', 200, g), '200 g (1 cup)');
      expect(servingLabel('1 cup (about 150 g)', 150, g), '150 g (1 cup)');
      expect(servingLabel('100 gms', 100, g), '100 g');
      expect(servingLabel('100gms', 100, g), '100 g');
      expect(servingLabel('100 gr', 100, g), '100 g');
      expect(servingLabel('1 gram scoop', 30, g), '30 g (scoop)');
      expect(servingLabel('2 g scoop', 30, g), '30 g (scoop)');
      expect(servingLabel('handful of nuts', 30, g), '30 g (handful of nuts)');
      expect(servingLabel('1 glass', 250, g), '250 g (1 glass)');
      expect(servingLabel('2 gulab jamun', 100, g), '100 g (2 gulab jamun)');
      expect(servingLabel('1 tsp', 0.3, g), '1 tsp');
      expect(servingLabel('1 tsp', 0.49, g), '1 tsp');
      expect(servingLabel('1 tsp', 0.5, g), '1 g (1 tsp)');
    });
    test('the liquid flag and an ml description force ml', () {
      expect(servingLabel('1 glass', 250, g, isLiquid: true), '250 ml (1 glass)');
      expect(servingLabel('250 g', 250, g, isLiquid: true), '250 ml');
      expect(servingLabel('1 serving (200 ml)', 200, g), '200 ml (1 serving)');
      expect(servingLabel('1 cup', 158, g), '158 g (1 cup)');
    });
    test('Portions is byte-identical; a missing weight falls back to it', () {
      for (final d in ['1 cup', '100g', '1 packet (52g)', '180', '', '1 cup (2 eggs)']) {
        expect(servingLabel(d, 100, p, isLiquid: true), d);
      }
      expect(servingLabel('1 cup', 0, g), '1 cup');
      expect(servingLabel('1 cup', -5, g), '1 cup');
      expect(servingLabel('1 cup', double.nan, g), '1 cup');
    });
    test('the stored value: absent and unknown read as Portions', () {
      expect(DietServingView.fromStorage(null), p);
      expect(DietServingView.fromStorage('x'), p);
      expect(DietServingView.fromStorage('grams'), g);
      expect(DietServingView.fromStorage('portions'), p);
    });
  });

  group('every real row, every multiplier', () {
    test('a sensible label: no empty text, no nested or doubled bracket', () {
      for (final r in rows) {
        final desc = (r['standard_serving_desc'] as String? ?? '');
        final grams = (r['standard_serving_g'] as num).toDouble();
        final liquid = r['weight_unit'] == 'ml';
        for (final m in const [1.0, 0.5, 1.5, 2.0, 3.0]) {
          final scaled = scaleServingDesc(desc, m);
          final label = servingLabel(scaled, grams * m, g, isLiquid: liquid);
          final why = '${r['id']} ${r['name']} "$desc" x$m -> "$label"';
          expect(label.trim(), isNotEmpty, reason: why);
          expect(label.contains('(('), isFalse, reason: why);
          expect(RegExp(r'\([^)]*\([^)]*\)').hasMatch(label), isFalse,
              reason: why);
          // Starts with a whole number of grams or ml, never a bare desc.
          expect(RegExp(r'^\d+ (g|ml)\b').hasMatch(label), isTrue, reason: why);
          // The weight is never shown twice: at most one "N g|ml" figure
          // outside a portion word.
          expect(RegExp(r'\d+\s*(g|ml)\b').allMatches(label).length,
              lessThanOrEqualTo(1),
              reason: why);
          // Portions view is untouched.
          expect(servingLabel(scaled, grams * m, p, isLiquid: liquid), scaled);
        }
      }
    });
  });
}
