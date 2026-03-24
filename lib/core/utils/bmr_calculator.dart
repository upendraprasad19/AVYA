/// Mifflin-St Jeor BMR formula with activity multipliers.
///
/// Male:   BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) + 5
/// Female: BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) - 161
///
/// TDEE = BMR x activity multiplier
class BmrCalculator {
  BmrCalculator._();

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
    if (gender.toLowerCase() == 'male') {
      return (base + 5).roundToDouble();
    } else {
      return (base - 161).roundToDouble();
    }
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
    return (bmr * multiplier).roundToDouble();
  }

  /// Returns a full breakdown: BMR, TDEE, and macros based on goal.
  ///
  /// - [goal]: "build_muscle" | "lose_fat" | "general_fitness" | "strength"
  static NutritionTargets calculateTargets({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
    required String activityLevel,
    required String goal,
  }) {
    final bmr = calculateBmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
    );

    final tdee = bmr * (activityMultipliers[activityLevel] ?? 1.2);

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

    final proteinGrams = (weightKg * proteinPerKg).round();
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
