/// Mifflin-St Jeor BMR formula with activity multipliers.
///
/// Male:   BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) + 5
/// Female: BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) - 161
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

  /// Activity level multipliers.
  static const Map<String, double> activityMultipliers = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'active': 1.725,
    'very_active': 1.9,
  };

  /// Calculates Basal Metabolic Rate using Mifflin-St Jeor formula.
  ///
  /// - [weightKg]: Body weight in kilograms.
  /// - [heightCm]: Height in centimetres.
  /// - [age]: Age in years.
  /// - [gender]: "male" or "female".
  ///
  /// Returns BMR in kcal/day (rounded to nearest integer).
  static double calculateBmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
  }) {
    final base = (10 * weightKg) + (6.25 * heightCm) - (5 * age);
    final raw = gender.toLowerCase() == 'male' ? base + 5 : base - 161;
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
  }) {
    final bmr = calculateBmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
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
    double? targetWeightKg,
  }) {
    final bmr = calculateBmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
    );

    final tdee = bmr * (activityMultipliers[activityLevel] ?? 1.2) + _tdeeOffset;

    // Calorie adjustment based on goal.
    double dailyCalories;
    double proteinPerKg;
    double fatPercentage;

    switch (goal) {
      case 'build_muscle':
        dailyCalories = tdee + 300; // Surplus
        proteinPerKg = 1.8;
        fatPercentage = 0.25;
        break;
      case 'lose_fat':
        dailyCalories = tdee - 500; // Deficit
        proteinPerKg = 2.0; // Higher protein during cut
        fatPercentage = 0.25;
        break;
      case 'strength':
        dailyCalories = tdee + 200; // Slight surplus
        proteinPerKg = 1.8;
        fatPercentage = 0.30;
        break;
      case 'general_fitness':
      default:
        dailyCalories = tdee; // Maintenance
        proteinPerKg = 1.6;
        fatPercentage = 0.25;
        break;
    }

    // Ensure minimum calories.
    dailyCalories = dailyCalories.clamp(1200, 5000);

    // For lose_fat, use target weight (if provided and lower than current) so
    // that overweight users don't get inflated protein targets.
    final proteinBaseKg = (goal == 'lose_fat' &&
            targetWeightKg != null &&
            targetWeightKg > 0 &&
            targetWeightKg < weightKg)
        ? targetWeightKg
        : weightKg;
    final proteinGrams = (proteinBaseKg * proteinPerKg).round();
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
