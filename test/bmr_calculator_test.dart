import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

void main() {
  group('BmrCalculator.calculateBmr', () {
    test('male — standard values', () {
      // 80kg, 175cm, 30yo male
      // BMR = (10*80) + (6.25*175) - (5*30) + 5 - 50 (offset)
      //     = 800 + 1093.75 - 150 + 5 - 50 = 1698.75 → 1699
      final result = BmrCalculator.calculateBmr(
        weightKg: 80,
        heightCm: 175,
        age: 30,
        gender: 'male',
      );
      expect(result, 1699.0);
    });

    test('female — standard values', () {
      // 60kg, 165cm, 28yo female
      // BMR = (10*60) + (6.25*165) - (5*28) - 161 - 50 (offset)
      //     = 600 + 1031.25 - 140 - 161 - 50 = 1280.25 → 1280
      final result = BmrCalculator.calculateBmr(
        weightKg: 60,
        heightCm: 165,
        age: 28,
        gender: 'female',
      );
      expect(result, 1280.0);
    });

    test('gender check is case-insensitive', () {
      final lower = BmrCalculator.calculateBmr(
        weightKg: 75, heightCm: 170, age: 25, gender: 'male',
      );
      final upper = BmrCalculator.calculateBmr(
        weightKg: 75, heightCm: 170, age: 25, gender: 'Male',
      );
      expect(lower, upper);
    });

    test('female BMR is always lower than male BMR (same stats)', () {
      final male = BmrCalculator.calculateBmr(
        weightKg: 70, heightCm: 170, age: 25, gender: 'male',
      );
      final female = BmrCalculator.calculateBmr(
        weightKg: 70, heightCm: 170, age: 25, gender: 'female',
      );
      // Difference should be 166 (male +5, female -161)
      expect(male - female, 166.0);
    });

    test('older age reduces BMR', () {
      final young = BmrCalculator.calculateBmr(
        weightKg: 80, heightCm: 175, age: 25, gender: 'male',
      );
      final older = BmrCalculator.calculateBmr(
        weightKg: 80, heightCm: 175, age: 45, gender: 'male',
      );
      expect(older, lessThan(young));
    });
  });

  group('BmrCalculator.calculateTdee', () {
    const weightKg = 75.0;
    const heightCm = 175.0;
    const age = 30;
    const gender = 'male';

    test('sedentary multiplier (1.2)', () {
      final bmr = BmrCalculator.calculateBmr(
        weightKg: weightKg, heightCm: heightCm, age: age, gender: gender,
      );
      final tdee = BmrCalculator.calculateTdee(
        weightKg: weightKg, heightCm: heightCm, age: age,
        gender: gender, activityLevel: 'sedentary',
      );
      // TDEE applies a -100 offset in addition to the multiplier
      expect(tdee, (bmr * 1.2 - 100).roundToDouble());
    });

    test('active multiplier (1.725)', () {
      final bmr = BmrCalculator.calculateBmr(
        weightKg: weightKg, heightCm: heightCm, age: age, gender: gender,
      );
      final tdee = BmrCalculator.calculateTdee(
        weightKg: weightKg, heightCm: heightCm, age: age,
        gender: gender, activityLevel: 'active',
      );
      // TDEE applies a -100 offset in addition to the multiplier
      expect(tdee, (bmr * 1.725 - 100).roundToDouble());
    });

    test('unknown activity level defaults to sedentary (1.2)', () {
      final sedentary = BmrCalculator.calculateTdee(
        weightKg: weightKg, heightCm: heightCm, age: age,
        gender: gender, activityLevel: 'sedentary',
      );
      final unknown = BmrCalculator.calculateTdee(
        weightKg: weightKg, heightCm: heightCm, age: age,
        gender: gender, activityLevel: 'invalid_level',
      );
      expect(unknown, sedentary);
    });

    test('all 5 activity levels produce ascending TDEE', () {
      const levels = ['sedentary', 'light', 'moderate', 'active', 'very_active'];
      final results = levels.map((l) => BmrCalculator.calculateTdee(
        weightKg: weightKg, heightCm: heightCm, age: age,
        gender: gender, activityLevel: l,
      )).toList();
      for (int i = 1; i < results.length; i++) {
        expect(results[i], greaterThan(results[i - 1]));
      }
    });
  });

  group('BmrCalculator.calculateTargets', () {
    const baseParams = (
      weightKg: 75.0,
      heightCm: 175.0,
      age: 30,
      gender: 'male',
      activityLevel: 'moderate',
    );

    test('build_muscle applies pace-based surplus vs general_fitness', () {
      // Bug #24 — 75kg male at balanced pace: 75 × 0.005 × 7700 / 7 ≈ 412.5 kcal surplus.
      final muscle = BmrCalculator.calculateTargets(
        weightKg: baseParams.weightKg, heightCm: baseParams.heightCm,
        age: baseParams.age, gender: baseParams.gender,
        activityLevel: baseParams.activityLevel, goal: 'build_muscle',
        pacePreference: 'balanced',
      );
      final general = BmrCalculator.calculateTargets(
        weightKg: baseParams.weightKg, heightCm: baseParams.heightCm,
        age: baseParams.age, gender: baseParams.gender,
        activityLevel: baseParams.activityLevel, goal: 'general_fitness',
        pacePreference: 'balanced',
      );
      expect(muscle.dailyCalories - general.dailyCalories, inInclusiveRange(405, 420));
    });

    test('lose_fat applies pace-based deficit vs general_fitness', () {
      // Bug #24 — 75kg male at balanced pace: 75 × 0.005 × 7700 / 7 ≈ 412.5 kcal deficit.
      final fat = BmrCalculator.calculateTargets(
        weightKg: baseParams.weightKg, heightCm: baseParams.heightCm,
        age: baseParams.age, gender: baseParams.gender,
        activityLevel: baseParams.activityLevel, goal: 'lose_fat',
        pacePreference: 'balanced',
      );
      final general = BmrCalculator.calculateTargets(
        weightKg: baseParams.weightKg, heightCm: baseParams.heightCm,
        age: baseParams.age, gender: baseParams.gender,
        activityLevel: baseParams.activityLevel, goal: 'general_fitness',
        pacePreference: 'balanced',
      );
      expect(general.dailyCalories - fat.dailyCalories, inInclusiveRange(405, 420));
    });

    test('calories respect gender-aware floor + 5000 ceiling', () {
      // Bug #24 — female floor is 1200, male floor is 1500.
      final low = BmrCalculator.calculateTargets(
        weightKg: 30, heightCm: 140, age: 70,
        gender: 'female', activityLevel: 'sedentary', goal: 'lose_fat',
        pacePreference: 'balanced',
      );
      expect(low.dailyCalories, greaterThanOrEqualTo(1200));

      // Extreme high: large person, build_muscle, very active
      final high = BmrCalculator.calculateTargets(
        weightKg: 200, heightCm: 220, age: 20,
        gender: 'male', activityLevel: 'very_active', goal: 'build_muscle',
        pacePreference: 'balanced',
      );
      expect(high.dailyCalories, lessThanOrEqualTo(5000));
    });

    test('output contains all required fields with positive values', () {
      final targets = BmrCalculator.calculateTargets(
        weightKg: 70, heightCm: 170, age: 28,
        gender: 'male', activityLevel: 'moderate', goal: 'general_fitness',
        pacePreference: 'balanced',
      );
      expect(targets.bmr, greaterThan(0));
      expect(targets.tdee, greaterThan(0));
      expect(targets.dailyCalories, greaterThan(0));
      expect(targets.proteinGrams, greaterThan(0));
      expect(targets.carbGrams, greaterThan(0));
      expect(targets.fatGrams, greaterThan(0));
      expect(targets.tdee, greaterThanOrEqualTo(targets.bmr));
    });

    test('toMap() returns all 6 keys', () {
      final targets = BmrCalculator.calculateTargets(
        weightKg: 70, heightCm: 170, age: 28,
        gender: 'male', activityLevel: 'moderate', goal: 'general_fitness',
        pacePreference: 'balanced',
      );
      final map = targets.toMap();
      expect(map.containsKey('bmr'), isTrue);
      expect(map.containsKey('tdee'), isTrue);
      expect(map.containsKey('daily_calories'), isTrue);
      expect(map.containsKey('protein_grams'), isTrue);
      expect(map.containsKey('carb_grams'), isTrue);
      expect(map.containsKey('fat_grams'), isTrue);
    });
  });

  group('Katch-McArdle (body fat % provided)', () {
    test('uses Katch-McArdle when bodyFatPercent is given', () {
      // 80kg, 20% BF → lean mass = 64kg
      // KM BMR = 370 + (21.6 * 64) = 370 + 1382.4 = 1752.4 - 50 = 1702
      final result = BmrCalculator.calculateBmr(
        weightKg: 80, heightCm: 175, age: 30,
        gender: 'male', bodyFatPercent: 20.0,
      );
      expect(result, 1702.0);
    });

    test('falls back to Mifflin-St Jeor when bodyFatPercent is null', () {
      final withBf = BmrCalculator.calculateBmr(
        weightKg: 80, heightCm: 175, age: 30,
        gender: 'male', bodyFatPercent: null,
      );
      final without = BmrCalculator.calculateBmr(
        weightKg: 80, heightCm: 175, age: 30, gender: 'male',
      );
      expect(withBf, without);
    });

    test('Katch-McArdle is gender-neutral (same BF% same weight = same BMR)', () {
      final male = BmrCalculator.calculateBmr(
        weightKg: 70, heightCm: 170, age: 25,
        gender: 'male', bodyFatPercent: 15.0,
      );
      final female = BmrCalculator.calculateBmr(
        weightKg: 70, heightCm: 170, age: 25,
        gender: 'female', bodyFatPercent: 15.0,
      );
      expect(male, female); // KM doesn't use gender
    });

    test('offset (-50) is applied in Katch-McArdle', () {
      // 70kg, 15% BF → lean mass = 59.5kg
      // Raw KM = 370 + (21.6 * 59.5) = 370 + 1285.2 = 1655.2
      // With offset = 1655.2 - 50 = 1605.2 → 1605
      final result = BmrCalculator.calculateBmr(
        weightKg: 70, heightCm: 170, age: 25,
        gender: 'male', bodyFatPercent: 15.0,
      );
      expect(result, 1605.0);
    });

    test('ignores invalid bodyFatPercent (0, negative, >=70)', () {
      final baseline = BmrCalculator.calculateBmr(
        weightKg: 80, heightCm: 175, age: 30, gender: 'male',
      );
      expect(
        BmrCalculator.calculateBmr(
          weightKg: 80, heightCm: 175, age: 30,
          gender: 'male', bodyFatPercent: 0,
        ),
        baseline,
      );
      expect(
        BmrCalculator.calculateBmr(
          weightKg: 80, heightCm: 175, age: 30,
          gender: 'male', bodyFatPercent: -5,
        ),
        baseline,
      );
      expect(
        BmrCalculator.calculateBmr(
          weightKg: 80, heightCm: 175, age: 30,
          gender: 'male', bodyFatPercent: 70,
        ),
        baseline,
      );
    });

    test('TDEE passes bodyFatPercent through to BMR', () {
      final tdeeWithBf = BmrCalculator.calculateTdee(
        weightKg: 80, heightCm: 175, age: 30,
        gender: 'male', activityLevel: 'moderate', bodyFatPercent: 20.0,
      );
      final tdeeWithout = BmrCalculator.calculateTdee(
        weightKg: 80, heightCm: 175, age: 30,
        gender: 'male', activityLevel: 'moderate',
      );
      // These should differ since BF% changes the BMR formula
      expect(tdeeWithBf, isNot(equals(tdeeWithout)));
    });

    test('calculateTargets uses Katch-McArdle when BF% provided', () {
      final withBf = BmrCalculator.calculateTargets(
        weightKg: 80, heightCm: 175, age: 30,
        gender: 'male', activityLevel: 'moderate',
        goal: 'build_muscle', pacePreference: 'balanced', bodyFatPercent: 20.0,
      );
      final without = BmrCalculator.calculateTargets(
        weightKg: 80, heightCm: 175, age: 30,
        gender: 'male', activityLevel: 'moderate',
        goal: 'build_muscle', pacePreference: 'balanced',
      );
      // BMR should differ
      expect(withBf.bmr, isNot(equals(without.bmr)));
      // Both should still have valid positive values
      expect(withBf.dailyCalories, greaterThan(0));
      expect(withBf.proteinGrams, greaterThan(0));
    });
  });
}
