import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

/// F19 regression (audit 2026-06-07): the default onboarding goal 'recompose'
/// silently fell through BmrCalculator's `default` → maintenance calories + the
/// lowest protein (1.6) + a fat-loss plan — the opposite of a recomp. This pins
/// the real recomp profile (slight deficit + 2.0 protein + hypertrophy + cardio),
/// the canonical goal SoT, and the new Build default, so no goal token can fall
/// through a `default` again.
void main() {
  // One representative user (75 kg moderate male, balanced pace).
  NutritionTargets t(String goal) => BmrCalculator.calculateTargets(
        weightKg: 75,
        heightCm: 178,
        age: 28,
        gender: 'male',
        activityLevel: 'moderate',
        goal: goal,
        pacePreference: 'balanced',
      );

  group('FitnessGoals SoT', () {
    test('recompose is a first-class profile (deficit + high protein + hypertrophy + cardio)', () {
      final r = FitnessGoals.of('recompose');
      expect(r.deltaMult, -0.5, reason: 'modest deficit');
      expect(r.proteinPerKg, 2.0, reason: 'hold muscle through the deficit');
      expect(r.planGoal, 'build_muscle', reason: 'hypertrophy training architecture');
      expect(r.cardio, isTrue, reason: 'light cardio finisher');
    });

    test('every token resolves; the five canonical goals exist', () {
      for (final token in FitnessGoals.tokens) {
        expect(FitnessGoals.isKnown(token), isTrue);
        expect(FitnessGoals.of(token).token, token);
        expect(FitnessGoals.label(token), isNotEmpty);
      }
      expect(
        FitnessGoals.tokens,
        containsAll(<String>['build_muscle', 'lose_fat', 'strength', 'general_fitness', 'recompose']),
      );
    });
  });

  group('Recompose targets (the F19 bug was: == maintenance + 1.6 protein)', () {
    test('recompose is NOT maintenance — calories sit below general_fitness', () {
      expect(t('recompose').dailyCalories, lessThan(t('general_fitness').dailyCalories));
    });

    test('recompose protein is higher than maintenance (2.0 vs 1.6 g/kg)', () {
      expect(t('recompose').proteinGrams, greaterThan(t('general_fitness').proteinGrams));
    });

    test('recompose is a SMALLER deficit than a full cut', () {
      expect(t('recompose').dailyCalories, greaterThan(t('lose_fat').dailyCalories));
    });

    test('calorie ordering pins every goal: build > strength > maintain > recomp > cut', () {
      expect(t('build_muscle').dailyCalories, greaterThan(t('strength').dailyCalories));
      expect(t('strength').dailyCalories, greaterThan(t('general_fitness').dailyCalories));
      expect(t('general_fitness').dailyCalories, greaterThan(t('recompose').dailyCalories));
      expect(t('recompose').dailyCalories, greaterThan(t('lose_fat').dailyCalories));
    });
  });

  group('Onboarding default goal', () {
    test('the pre-selected default card is Build (build_muscle), not recompose', () {
      final src = File('lib/features/onboarding/screens/goal_screen.dart').readAsStringSync();
      final firstKey = RegExp(r"key:\s*'(\w+)'").firstMatch(src)?.group(1);
      expect(firstKey, 'build_muscle',
          reason: 'goal_screen _goals.first (the pre-selected default) must be build_muscle');
    });
  });
}
