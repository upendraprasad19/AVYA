// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §4 tests 1, 2):
// the pure pieces. `BmrCalculator.macroSplit` (low carb / keto carb bounds,
// the Balanced cap, fat >= 0, energy within ±4.5 kcal, Balanced throws) and
// `effectiveMacroTargets` (the ONE rule: enabled && pro && non-Balanced &&
// a real pack; every other case returns the base EXACTLY with Balanced).
// Plus the vocabulary, the targets-map carrier read, the label and the push
// entry.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/utils/effective_macro_targets.dart';

import '../helpers/dart_source_scan.dart';

void main() {
  group('macroSplit', () {
    // (kcal, protein, balancedCarbs)
    const rows = <(double, double, double)>[
      (2400, 150, 280),
      (1800, 120, 200),
      (3200, 180, 400),
      (1200, 120, 60), // protein at its 40 % cap, Balanced carbs at 60 g
      (1500, 150, 50), // Balanced at its own floor of 50 g
      (5000, 250, 600),
      (2000, 400, 100), // inconsistent pair: low carb fat lands exactly at 0
    ];

    for (final s in [DietStrategy.lowCarb, DietStrategy.keto]) {
      for (final (k, p, b) in rows) {
        test('${s.storageKey} $k kcal / ${p}P / ${b}C', () {
          final r = BmrCalculator.macroSplit(
              dailyCalories: k,
              proteinGrams: p,
              balancedCarbs: b,
              strategy: s);
          final strategyCarbs = s == DietStrategy.lowCarb
              ? (0.20 * k / 4).round().clamp(75, 150)
              : (0.05 * k / 4).round().clamp(20, 50);
          final expectedCarbs =
              strategyCarbs < b.round() ? strategyCarbs : b.round();
          expect(r.carbGrams, expectedCarbs);
          expect(r.carbGrams, lessThanOrEqualTo(b.round()),
              reason: 'never more carbs than Balanced');
          expect(r.fatGrams, greaterThanOrEqualTo(0));
          final fatRaw = ((k - 4 * p - 4 * r.carbGrams) / 9).round();
          expect(r.fatGrams, fatRaw < 0 ? 0 : fatRaw);
          if (fatRaw >= 0) {
            final energy = 4 * p + 4 * r.carbGrams + 9 * r.fatGrams;
            expect((energy - k).abs(), lessThanOrEqualTo(4.5));
          }
        });
      }
    }

    test('bounds: low carb 75..150, keto 20..50', () {
      int lc(double k) => BmrCalculator.macroSplit(
              dailyCalories: k,
              proteinGrams: 100,
              balancedCarbs: 9999,
              strategy: DietStrategy.lowCarb)
          .carbGrams;
      int kt(double k) => BmrCalculator.macroSplit(
              dailyCalories: k,
              proteinGrams: 100,
              balancedCarbs: 9999,
              strategy: DietStrategy.keto)
          .carbGrams;
      expect(lc(1200), 75); // 60 -> floor
      expect(lc(2400), 120);
      expect(lc(5000), 150); // 250 -> cap
      expect(kt(1200), 20); // 15 -> floor
      expect(kt(2400), 30);
      expect(kt(5000), 50); // 62.5 -> cap
    });

    test('a heavy-protein, low-calorie user: Low carb equals Balanced carbs',
        () {
      final r = BmrCalculator.macroSplit(
          dailyCalories: 1500,
          proteinGrams: 150,
          balancedCarbs: 60,
          strategy: DietStrategy.lowCarb);
      expect(r.carbGrams, 60, reason: 'capped at Balanced, not the 75 floor');
    });

    // B-pass seat C finding 1: no row above drove the remainder below zero,
    // so the clamp was never exercised. Literal values, not the ternary.
    test('fat never goes negative: an inconsistent pack clamps to 0', () {
      // Low carb: carbs clamp(60, 75, 150) = 75 (<= Balanced 300);
      // 1200 - 4 x 300 - 4 x 75 = -300 kcal -> fat 0.
      final lc = BmrCalculator.macroSplit(
          dailyCalories: 1200,
          proteinGrams: 300,
          balancedCarbs: 300,
          strategy: DietStrategy.lowCarb);
      expect(lc.carbGrams, 75);
      expect(lc.fatGrams, 0);
      // Keto: carbs clamp(15, 20, 50) = 20; 1200 - 1200 - 80 = -80 -> 0.
      final kt = BmrCalculator.macroSplit(
          dailyCalories: 1200,
          proteinGrams: 300,
          balancedCarbs: 300,
          strategy: DietStrategy.keto);
      expect(kt.carbGrams, 20);
      expect(kt.fatGrams, 0);
    });

    test('Balanced throws', () {
      expect(
          () => BmrCalculator.macroSplit(
              dailyCalories: 2400,
              proteinGrams: 150,
              balancedCarbs: 280,
              strategy: DietStrategy.balanced),
          throwsArgumentError);
    });
  });

  group('effectiveMacroTargets truth table', () {
    const real = (calories: 2400.0, protein: 150.0, carbs: 280.0, fat: 80.0);
    const fractional =
        (calories: 2399.6, protein: 150.4, carbs: 279.5, fat: 79.7);
    const zeroCalories = (calories: 0.0, protein: 150.0, carbs: 280.0, fat: 80.0);
    const zeroProtein = (calories: 2400.0, protein: 0.0, carbs: 280.0, fat: 80.0);
    const zeroCarbs = (calories: 2400.0, protein: 150.0, carbs: 0.0, fat: 80.0);
    final stored = <Object?>['balanced', 'low_carb', 'keto', null, 42, 'zone'];

    for (final enabled in [true, false]) {
      for (final pro in [true, false]) {
        for (final s in stored) {
          for (final base in <MacroPack?>[
            real,
            fractional,
            zeroCalories,
            zeroProtein,
            zeroCarbs,
            null
          ]) {
            test('enabled=$enabled pro=$pro stored=$s base=$base', () {
              final r = effectiveMacroTargets(base, s,
                  pro: pro, enabled: enabled);
              if (base == null) {
                expect(r, isNull);
                return;
              }
              final strategy = dietStrategyOf(s);
              final applies = enabled &&
                  pro &&
                  strategy != DietStrategy.balanced &&
                  base.calories > 0 &&
                  base.protein > 0 &&
                  base.carbs > 0;
              expect(r!.calories, base.calories);
              expect(r.protein, base.protein);
              if (!applies) {
                expect(r.strategy, DietStrategy.balanced);
                expect(r.carbs, base.carbs);
                expect(r.fat, base.fat);
                return;
              }
              final split = BmrCalculator.macroSplit(
                  dailyCalories: base.calories,
                  proteinGrams: base.protein,
                  balancedCarbs: base.carbs,
                  strategy: strategy);
              expect(r.strategy, strategy);
              expect(r.carbs, split.carbGrams.toDouble());
              expect(r.fat, split.fatGrams.toDouble());
            });
          }
        }
      }
    }

    test('keto on a real pack actually lowers carbs (the table is not vacuous)',
        () {
      final r = effectiveMacroTargets(real, 'keto', pro: true, enabled: true)!;
      expect(r.strategy, DietStrategy.keto);
      expect(r.carbs, 30);
      expect(r.fat, ((2400 - 600 - 120) / 9).round().toDouble());
    });
  });

  // Unit 3b-3 round 1 finding 8: with no Hive box (a pure unit test, or a
  // read that throws) the flag is the build default, which is ON since the
  // flip; no seam is set here.
  test('enabled with no Hive and no seam is the build default (on)', () {
    expect(DietStrategyFlags.debugEnabledOverride, isNull);
    // B-pass seat C finding 6: the precondition, so a later Hive setUp in
    // this file cannot turn this into a test of the box read.
    expect(() => HiveService.instance.configBox, throwsA(anything));
    expect(kDietStrategyDefaultOn, isTrue);
    expect(DietStrategyFlags.enabled, isTrue);
  });

  // B-pass seat C finding 2: the fleet-wide off (a build with the constant
  // false) cannot be executed while the constant is true, so its order is
  // pinned: the seam first, then the constant, then the box read.
  test('PRESENCE: enabled checks the build constant before the box', () {
    final src = stripDartComments(
        File('lib/features/nutrition/services/diet_strategy_flags.dart')
            .readAsStringSync());
    final getter = src.substring(src.indexOf('static bool get enabled {'));
    final seam = getter.indexOf('if (override != null) return override;');
    final guard = getter.indexOf('if (!kDietStrategyDefaultOn) return false;');
    final read = getter.indexOf('HiveService.instance.configBox');
    expect(seam, greaterThan(0));
    expect(guard, greaterThan(seam));
    expect(read, greaterThan(guard));
  });

  group('vocabulary', () {
    test('dietStrategyOf is tolerant; anything unreadable is Balanced', () {
      expect(dietStrategyOf('keto'), DietStrategy.keto);
      expect(dietStrategyOf(' Low-Carb '), DietStrategy.lowCarb);
      expect(dietStrategyOf('low carb'), DietStrategy.lowCarb);
      expect(dietStrategyOf('balanced'), DietStrategy.balanced);
      for (final bad in <Object?>[null, '', 'zone', 7, true, const ['keto']]) {
        expect(dietStrategyOf(bad), DietStrategy.balanced, reason: '$bad');
      }
    });

    test('dietStrategyOfTargets reads strategy_index; absent or out of range '
        'is Balanced', () {
      expect(dietStrategyOfTargets(null), DietStrategy.balanced);
      expect(dietStrategyOfTargets({'calories': 2400.0}), DietStrategy.balanced);
      expect(dietStrategyOfTargets({'strategy_index': 2.0}), DietStrategy.keto);
      expect(dietStrategyOfTargets({'strategy_index': 1.0}),
          DietStrategy.lowCarb);
      expect(dietStrategyOfTargets({'strategy_index': 9.0}),
          DietStrategy.balanced);
      expect(dietStrategyOfTargets({'strategy_index': -1.0}),
          DietStrategy.balanced);
      // B-pass seat A finding 4: toInt() throws on these.
      for (final v in [double.nan, double.infinity, double.negativeInfinity]) {
        expect(dietStrategyOfTargets({'strategy_index': v}),
            DietStrategy.balanced, reason: '$v');
      }
    });

    test('label: Balanced adds nothing', () {
      expect(withDietStrategyTag('NON-VEG', DietStrategy.balanced), 'NON-VEG');
      expect(withDietStrategyTag('NON-VEG', DietStrategy.keto),
          'NON-VEG · KETO');
      expect(withDietStrategyTag('VEG', DietStrategy.lowCarb),
          'VEG · LOW CARB');
    });

    test('push entry: flag off sends nothing even when the field is present',
        () {
      expect(dietStrategyPushEntry({'diet_strategy': 'keto'}, enabled: false),
          isEmpty);
      expect(dietStrategyPushEntry({}, enabled: true), isEmpty);
      expect(dietStrategyPushEntry({'diet_strategy': '  '}, enabled: true),
          isEmpty);
      expect(dietStrategyPushEntry({'diet_strategy': 'keto'}, enabled: true),
          {'diet_strategy': 'keto'});
      expect(
          dietStrategyPushEntry({'diet_strategy': 'Low-Carb'}, enabled: true),
          {'diet_strategy': 'low_carb'});
      expect(dietStrategyPushEntry({'diet_strategy': 'zone'}, enabled: true),
          {'diet_strategy': 'balanced'},
          reason: 'a stray value must never fail the CHECK');
    });
  });
}
