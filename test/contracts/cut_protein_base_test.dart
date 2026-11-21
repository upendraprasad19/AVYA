// goal-change-targets B1: a Cut's protein base is the HIGHER of the target weight and
// 90 % of the current weight (was: the target weight alone), so a far target does not
// starve a Cut. Writer: BmrCalculator.calculateTargets. Readers: every caller of it
// (recomputeDerivedTargets, the nutrition provider fallback, onboarding).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

NutritionTargets _t(String goal, double kg, {double? target}) =>
    BmrCalculator.calculateTargets(
      weightKg: kg,
      heightCm: 178,
      age: 30,
      gender: 'male',
      activityLevel: 'moderate',
      goal: goal,
      pacePreference: 'balanced',
      targetWeightKg: target,
    );

void main() {
  group('Cut protein base', () {
    test('a far target: 75 kg to 65 uses 90 % of 75 = 67.5 kg, 135 g', () {
      expect(_t('lose_fat', 75, target: 65).proteinGrams, 135);
    });

    test('a near target keeps the target: 75 kg to 72 is 72 kg, 144 g', () {
      expect(_t('lose_fat', 75, target: 72).proteinGrams, 144);
    });

    test('a very far target: 100 kg to 70 uses 90 kg, 180 g', () {
      expect(_t('lose_fat', 100, target: 70).proteinGrams, 180);
    });

    test('no target, or one at or above the weight, uses the current weight', () {
      expect(_t('lose_fat', 75).proteinGrams, 150);
      expect(_t('lose_fat', 75, target: 80).proteinGrams, 150);
      expect(_t('lose_fat', 75, target: 0).proteinGrams, 150);
    });

    test('other goals ignore the target', () {
      expect(_t('build_muscle', 75, target: 65).proteinGrams,
          _t('build_muscle', 75).proteinGrams);
      expect(_t('general_fitness', 75, target: 65).proteinGrams,
          _t('general_fitness', 75).proteinGrams);
    });

    test('a Cut never gets fewer grams than Build, in the uncapped region', () {
      for (final w in [60.0, 75.0, 90.0, 110.0]) {
        for (final f in [0.4, 0.6, 0.8, 0.9, 1.0]) {
          final cut = _t('lose_fat', w, target: w * f);
          final build = _t('build_muscle', w);
          bool capped(NutritionTargets t) =>
              t.proteinGrams >= (t.dailyCalories * 0.40 / 4).round();
          if (capped(cut) || capped(build)) continue;
          expect(cut.proteinGrams, greaterThanOrEqualTo(build.proteinGrams),
              reason: 'w=$w target=${w * f}');
        }
      }
    });
  });

  group('provider fallback carries the target weight', () {
    test('a Cut profile with no stored targets resolves the new-rule protein', () {
      final t = resolveNutritionTargetsForTest(<String, dynamic>{
        'current_weight_kg': 75.0,
        'target_weight_kg': 65.0,
        'height_cm': 178.0,
        'gender': 'male',
        'primary_goal': 'lose_fat',
        'activity_level': 'moderate',
        'date_of_birth': '1995-01-01',
      });
      expect(t['protein_grams'], 135.0);
    });
  });
}
