import 'package:icanbefitter/core/constants/fitness_goals.dart';

/// Hybrid BMR calculator: Katch-McArdle when body fat % is available,
/// Mifflin-St Jeor otherwise.
///
/// Katch-McArdle: BMR = 370 + (21.6 x lean_mass_kg)
///   where lean_mass = weight_kg x (1 - body_fat_pct / 100)
///
/// Mifflin-St Jeor:
///   Male:   BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) + 5
///   Female: BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) - 161
///
/// TDEE = BMR x activity multiplier
class BmrCalculator {
  BmrCalculator._();

  /// Universal calibration offsets applied to all users.
  ///
  /// The Mifflin-St Jeor formula tends to overestimate for the app's target
  /// demographic (young Indian professionals with predominantly sedentary
  /// lifestyles). These flat deductions correct for that bias app-wide.
  /// Change only here — both [calculateBmr] and [calculateTdee] apply them.
  static const int _bmrOffset = -50;
  static const int _tdeeOffset = -100;

  /// Bug #24 — Pace preference → weekly body-weight change rate.
  /// Applied in both directions (deficit for lose_fat, surplus for build_muscle).
  /// Clamped to 1% BW/week max regardless of pace (medical upper bound).
  static const Map<String, double> _paceRates = {
    'slow': 0.0025,       // 0.25% BW/week
    'balanced': 0.005,    // 0.5% BW/week — evidence-based sweet spot
    'aggressive': 0.0075, // 0.75% BW/week — near upper safe limit
  };
  static const double _paceMaxRate = 0.01; // 1% BW/week hard clamp
  static const double _kcalPerKgBodyWeight = 7700; // Atwater conservative

  /// Resolves a TDEE activity level from lifestyle + weekly training frequency.
  ///
  /// More accurate than mapping training days alone. A desk-job engineer who
  /// trains 4x/week is "moderate", but a construction worker training 4x/week
  /// is "very_active". This function combines both signals.
  ///
  /// - [lifestyle]: "desk_job" | "lightly_active" | "very_active_job"
  /// - [daysPerWeek]: 3 | 4 | 5 | 6
  static String resolveActivityLevel(String lifestyle, int daysPerWeek) {
    switch (lifestyle) {
      case 'very_active_job':
        // Physical job already saturates the ceiling regardless of training.
        return 'very_active';
      case 'lightly_active':
        if (daysPerWeek <= 3) return 'moderate';
        if (daysPerWeek <= 5) return 'active';
        return 'very_active';
      case 'desk_job':
      default:
        if (daysPerWeek <= 3) return 'light';
        if (daysPerWeek <= 5) return 'moderate';
        return 'active';
    }
  }

  /// Maps the stats-screen `activity_level` (4 pills: sedentary/light/moderate/
  /// heavy) to the plan-engine `lifestyle_activity` bucket (desk_job/
  /// lightly_active/very_active_job). SINGLE SOURCE for this 1:1 mapping —
  /// onboarding's PREVIEW (plan_screen._computeTargets) AND COMMIT
  /// (_onReportForDuty → completeOnboarding) both call it, so the preview
  /// calories cannot drift from the saved daily_calories. Obs#6 / f1b6d4 (the
  /// Hermes E-pass caught the preview reading a never-written `lifestyle_activity`
  /// key while the commit derived the value here).
  static String lifestyleFromActivityLevel(String activityLevel) {
    switch (activityLevel) {
      case 'sedentary':
      case 'light':
        return 'desk_job';
      case 'moderate':
        return 'lightly_active';
      case 'heavy':
        return 'very_active_job';
      default:
        return 'desk_job';
    }
  }

  /// Activity level multipliers.
  static const Map<String, double> activityMultipliers = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'active': 1.725,
    'very_active': 1.9,
  };

  /// Calculates Basal Metabolic Rate.
  ///
  /// When [bodyFatPercent] is provided (and valid 1-69%), uses Katch-McArdle
  /// formula based on lean body mass (gender-neutral, more accurate).
  /// Otherwise falls back to Mifflin-St Jeor.
  ///
  /// The [_bmrOffset] (-50 kcal) is applied in both formulas.
  ///
  /// Returns BMR in kcal/day (rounded to nearest integer).
  static double calculateBmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
    double? bodyFatPercent,
  }) {
    // Guard against unrealistic inputs that would produce invalid BMR.
    if (weightKg <= 0 || weightKg > 500 ||
        heightCm <= 0 || heightCm > 300 ||
        age <= 0 || age > 120) {
      return 0;
    }

    double raw;
    if (bodyFatPercent != null && bodyFatPercent > 0 && bodyFatPercent < 70) {
      // Katch-McArdle: gender-neutral, based on lean mass.
      final leanMass = weightKg * (1 - bodyFatPercent / 100);
      raw = 370 + (21.6 * leanMass);
    } else {
      // Mifflin-St Jeor: uses gender, height, age.
      final base = (10 * weightKg) + (6.25 * heightCm) - (5 * age);
      raw = gender.toLowerCase() == 'male' ? base + 5 : base - 161;
    }

    return (raw + _bmrOffset).roundToDouble();
  }

  /// Calculates Total Daily Energy Expenditure.
  ///
  /// TDEE = BMR x activity multiplier.
  ///
  /// - [activityLevel]: One of "sedentary", "light", "moderate",
  ///   "active", "very_active".
  ///
  /// Returns TDEE in kcal/day (rounded to nearest integer).
  static double calculateTdee({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
    required String activityLevel,
    double? bodyFatPercent,
  }) {
    final bmr = calculateBmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
      bodyFatPercent: bodyFatPercent,
    );
    final multiplier = activityMultipliers[activityLevel] ?? 1.2;
    return (bmr * multiplier + _tdeeOffset).roundToDouble();
  }

  /// Returns a full breakdown: BMR, TDEE, and macros based on goal.
  ///
  /// - [goal]: "build_muscle" | "lose_fat" | "general_fitness" | "strength"
  /// - [targetWeightKg]: When provided and the goal is "lose_fat", protein is
  ///   calculated from target weight (not current weight) to avoid inflated
  ///   targets for users who are significantly overweight.
  static NutritionTargets calculateTargets({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
    required String activityLevel,
    required String goal,
    required String pacePreference, // Bug #24 — new required arg
    double? targetWeightKg,
    double? bodyFatPercent,
  }) {
    final bmr = calculateBmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
      bodyFatPercent: bodyFatPercent,
    );

    final tdee = bmr * (activityMultipliers[activityLevel] ?? 1.2) + _tdeeOffset;

    // Bug #24 — Back-compute daily kcal delta from pace-based weekly rate.
    // weekly_kg_delta = current_weight × pace_rate (clamped to 1% BW max)
    // daily_kcal_delta = weekly_kg_delta × 7700 / 7
    final rawPaceRate = _paceRates[pacePreference] ?? _paceRates['balanced']!;
    final paceRate = rawPaceRate.clamp(0.0, _paceMaxRate);
    final weeklyKgDelta = weightKg * paceRate;
    final dailyKcalDelta = (weeklyKgDelta * _kcalPerKgBodyWeight) / 7;

    // Goal-specific targets come from the canonical FitnessGoals SoT — no
    // `default` fallthrough (the F19 bug: 'recompose' silently hit maintenance
    // calories + 1.6 protein here). dailyCalories = tdee + deltaMult × pace delta.
    final goalSpec = FitnessGoals.of(goal);
    double dailyCalories = tdee + (goalSpec.deltaMult * dailyKcalDelta);
    final double proteinPerKg = goalSpec.proteinPerKg;
    final double fatPercentage = goalSpec.fatPercentage;

    // Physiological floor: male 1500 / female 1200 (overrides old 1200 flat).
    final minKcal = gender.toLowerCase() == 'male' ? 1500.0 : 1200.0;
    dailyCalories = dailyCalories.clamp(minKcal, 5000);

    // For lose_fat, use target weight (if provided and lower than current) so
    // that overweight users don't get inflated protein targets.
    final proteinBaseKg = (goal == 'lose_fat' &&
            targetWeightKg != null &&
            targetWeightKg > 0 &&
            targetWeightKg < weightKg)
        ? targetWeightKg
        : weightKg;

    // Cap protein so it never exceeds 40% of daily calories.
    // This prevents impossible macro splits when BMR inputs were out of range
    // (e.g. extremely high weight against a calories-clamped minimum).
    final rawProteinGrams = (proteinBaseKg * proteinPerKg).round();
    final maxProteinGrams = (dailyCalories * 0.40 / 4).round().clamp(50, 9999);
    final proteinGrams = rawProteinGrams.clamp(50, maxProteinGrams);

    final fatGrams = (dailyCalories * fatPercentage / 9).round();
    final proteinCalories = proteinGrams * 4;
    final fatCalories = fatGrams * 9;
    final carbCalories = dailyCalories - proteinCalories - fatCalories;
    final carbGrams = (carbCalories / 4).round();

    return NutritionTargets(
      bmr: bmr.round(),
      tdee: tdee.round(),
      dailyCalories: dailyCalories.round(),
      proteinGrams: proteinGrams,
      carbGrams: carbGrams.clamp(50, 800),
      fatGrams: fatGrams,
    );
  }

  /// Bug #24 — Project when the user will reach `targetKg` at their current
  /// `pacePreference`. Returns weeks + projected date.
  ///
  /// Edge cases:
  /// - target within 2 kg → clamped to 4-week floor regardless of pace
  ///   (no point picking aggressive to lose 1 kg).
  /// - current == target → 0 weeks (caller should hide projection).
  /// - weeks > 104 (2 years) → caller renders as ">2 years".
  static ({double weeks, DateTime date}) projectGoalDate({
    required double currentKg,
    required double targetKg,
    required String pacePreference,
  }) {
    final gap = (currentKg - targetKg).abs();
    if (gap == 0) {
      return (weeks: 0.0, date: DateTime.now());
    }

    // 2 kg or less → force slow pace with a 4-week floor.
    if (gap <= 2) {
      final effRate = _paceRates['slow']!;
      final weeklyKg = currentKg * effRate;
      final rawWeeks = gap / weeklyKg;
      final clampedWeeks = rawWeeks < 4 ? 4.0 : rawWeeks;
      return (
        weeks: clampedWeeks,
        date: DateTime.now().add(Duration(days: (clampedWeeks * 7).round())),
      );
    }

    final rate = (_paceRates[pacePreference] ?? _paceRates['balanced']!)
        .clamp(0.0, _paceMaxRate);
    final weeklyKg = currentKg * rate;
    final weeks = gap / weeklyKg;
    return (
      weeks: weeks,
      date: DateTime.now().add(Duration(days: (weeks * 7).round())),
    );
  }
}

/// Holds calculated nutrition targets.
class NutritionTargets {
  final int bmr;
  final int tdee;
  final int dailyCalories;
  final int proteinGrams;
  final int carbGrams;
  final int fatGrams;

  const NutritionTargets({
    required this.bmr,
    required this.tdee,
    required this.dailyCalories,
    required this.proteinGrams,
    required this.carbGrams,
    required this.fatGrams,
  });

  Map<String, dynamic> toMap() => {
        'bmr': bmr,
        'tdee': tdee,
        'daily_calories': dailyCalories,
        'protein_grams': proteinGrams,
        'carb_grams': carbGrams,
        'fat_grams': fatGrams,
      };

  @override
  String toString() =>
      'NutritionTargets(bmr: $bmr, tdee: $tdee, calories: $dailyCalories, '
      'protein: ${proteinGrams}g, carbs: ${carbGrams}g, fat: ${fatGrams}g)';
}
