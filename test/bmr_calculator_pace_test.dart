import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

void main() {
  group('BmrCalculator pace-based deltas', () {
    test('balanced + lose_fat: -kcal delta matches 0.5% BW per week', () {
      // 80 kg * 0.005 = 0.4 kg/week → 0.4 * 7700 / 7 = ~440 kcal/day
      final t = BmrCalculator.calculateTargets(
        weightKg: 80,
        heightCm: 175,
        age: 30,
        gender: 'male',
        activityLevel: 'moderate',
        goal: 'lose_fat',
        pacePreference: 'balanced',
      );
      // TDEE for this user ≈ 2530. Target ≈ 2530 - 440 = 2090.
      expect((t.tdee - t.dailyCalories), inInclusiveRange(430, 450));
    });

    test('slow pace halves the delta vs balanced', () {
      final balanced = BmrCalculator.calculateTargets(
        weightKg: 80, heightCm: 175, age: 30, gender: 'male',
        activityLevel: 'moderate', goal: 'lose_fat', pacePreference: 'balanced',
      );
      final slow = BmrCalculator.calculateTargets(
        weightKg: 80, heightCm: 175, age: 30, gender: 'male',
        activityLevel: 'moderate', goal: 'lose_fat', pacePreference: 'slow',
      );
      final balancedDelta = balanced.tdee - balanced.dailyCalories;
      final slowDelta = slow.tdee - slow.dailyCalories;
      // Slow is half the rate → delta is half.
      expect(slowDelta, closeTo(balancedDelta / 2, 10));
    });

    test('aggressive pace is 1.5x balanced', () {
      final balanced = BmrCalculator.calculateTargets(
        weightKg: 80, heightCm: 175, age: 30, gender: 'male',
        activityLevel: 'moderate', goal: 'lose_fat', pacePreference: 'balanced',
      );
      final aggro = BmrCalculator.calculateTargets(
        weightKg: 80, heightCm: 175, age: 30, gender: 'male',
        activityLevel: 'moderate', goal: 'lose_fat', pacePreference: 'aggressive',
      );
      final balancedDelta = balanced.tdee - balanced.dailyCalories;
      final aggroDelta = aggro.tdee - aggro.dailyCalories;
      expect(aggroDelta, closeTo(balancedDelta * 1.5, 10));
    });

    test('build_muscle applies +delta (surplus) instead of deficit', () {
      final t = BmrCalculator.calculateTargets(
        weightKg: 70, heightCm: 175, age: 25, gender: 'male',
        activityLevel: 'moderate', goal: 'build_muscle', pacePreference: 'balanced',
      );
      expect(t.dailyCalories, greaterThan(t.tdee));
    });

    test('general_fitness / maintain: delta is zero', () {
      final t = BmrCalculator.calculateTargets(
        weightKg: 70, heightCm: 175, age: 25, gender: 'male',
        activityLevel: 'moderate', goal: 'general_fitness', pacePreference: 'aggressive',
      );
      expect(t.dailyCalories, closeTo(t.tdee.toDouble(), 5));
    });

    test('physiological floor: male never below 1500 kcal', () {
      final t = BmrCalculator.calculateTargets(
        weightKg: 50, heightCm: 160, age: 40, gender: 'male',
        activityLevel: 'sedentary', goal: 'lose_fat', pacePreference: 'aggressive',
      );
      expect(t.dailyCalories, greaterThanOrEqualTo(1500));
    });

    test('physiological floor: female never below 1200 kcal', () {
      final t = BmrCalculator.calculateTargets(
        weightKg: 45, heightCm: 155, age: 40, gender: 'female',
        activityLevel: 'sedentary', goal: 'lose_fat', pacePreference: 'aggressive',
      );
      expect(t.dailyCalories, greaterThanOrEqualTo(1200));
    });
  });

  group('BmrCalculator.projectGoalDate', () {
    test('balanced user 85→80 kg projects ~12.5 weeks', () {
      final p = BmrCalculator.projectGoalDate(
        currentKg: 85,
        targetKg: 80,
        pacePreference: 'balanced',
      );
      // weekly rate = 85 * 0.005 = 0.425 kg. 5/0.425 ≈ 11.76 weeks.
      expect(p.weeks, inInclusiveRange(11.0, 13.0));
      expect(p.date.isAfter(DateTime.now()), isTrue);
    });

    test('slow pace pushes projection further out', () {
      final slow = BmrCalculator.projectGoalDate(
          currentKg: 85, targetKg: 80, pacePreference: 'slow');
      final balanced = BmrCalculator.projectGoalDate(
          currentKg: 85, targetKg: 80, pacePreference: 'balanced');
      expect(slow.weeks, greaterThan(balanced.weeks));
    });

    test('aggressive pace pulls projection in', () {
      final agg = BmrCalculator.projectGoalDate(
          currentKg: 85, targetKg: 80, pacePreference: 'aggressive');
      final balanced = BmrCalculator.projectGoalDate(
          currentKg: 85, targetKg: 80, pacePreference: 'balanced');
      expect(agg.weeks, lessThan(balanced.weeks));
    });

    test('within 2kg the chosen pace applies (goal-change-targets B1)', () {
      final agg = BmrCalculator.projectGoalDate(
          currentKg: 80, targetKg: 79, pacePreference: 'aggressive');
      final slow = BmrCalculator.projectGoalDate(
          currentKg: 80, targetKg: 79, pacePreference: 'slow');
      // aggressive is 0.75 %/week: 1 / (80 * 0.0075) = 1.67 weeks, not the old
      // forced-slow four-week floor; slow is 5 weeks.
      expect(agg.weeks, closeTo(1.667, 0.01));
      expect(agg.weeks, lessThan(slow.weeks));
      expect(slow.weeks, closeTo(5.0, 0.01));
    });

    test('the projection is never under one week', () {
      final p = BmrCalculator.projectGoalDate(
          currentKg: 80, targetKg: 79.8, pacePreference: 'aggressive');
      expect(p.weeks, 1.0);
    });

    test('current == target yields zero weeks (no projection needed)', () {
      final p = BmrCalculator.projectGoalDate(
          currentKg: 80, targetKg: 80, pacePreference: 'balanced');
      expect(p.weeks, 0);
    });
  });
}
