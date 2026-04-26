// lib/features/nutrition/services/diet_plan_generator.dart
//
// Diet plan generator service. Extracted from diet_plan_screen.dart so the
// algorithm is testable without booting Flutter widgets.
//
// Algorithm: anchor-protein-per-meal (APK Test #3 / Obs 2, 2026-04-26).
// Three passes per generation:
//   1. Pick an anchor protein for each meal slot, filtered by diet_preference.
//   2. Add carb staples + fat sources to hit the per-slot calorie band.
//   3. Verify daily total protein >= 95% of target. If short, swap the
//      lowest-protein-density item for a higher alternative within the same
//      calorie band.
//
// Reads from FoodRepository.instance (Hive foodBox). Zero network.

import 'dart:math';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

/// One meal slot in a generated diet plan.
class DietMealPlan {
  final String name; // "Breakfast", "Lunch", etc.
  final String slotKey; // "breakfast" | "mid_morning" | "lunch" | "evening" | "dinner"
  final List<DietPlanFoodItem> items;
  final int targetCalories;
  final int targetProtein;

  DietMealPlan({
    required this.name,
    required this.slotKey,
    required this.items,
    required this.targetCalories,
    required this.targetProtein,
  });

  int get totalCalories => items.fold(0, (s, i) => s + i.calories);
  int get totalProtein => items.fold(0, (s, i) => s + i.protein);
}

/// One food item inside a meal slot.
class DietPlanFoodItem {
  final String foodId;
  final String name;
  final String servingDesc;
  final double servingG;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String category;
  final bool isAnchor; // true = the slot's anchor protein

  DietPlanFoodItem({
    required this.foodId,
    required this.name,
    required this.servingDesc,
    required this.servingG,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.category,
    this.isAnchor = false,
  });
}

/// Inputs to the generator.
class DietPlanInputs {
  final int calorieTarget;
  final int proteinTarget;
  final String dietPreference; // 'veg' | 'vegan' | 'non-veg'
  final int? seed; // optional override for deterministic test runs

  const DietPlanInputs({
    required this.calorieTarget,
    required this.proteinTarget,
    required this.dietPreference,
    this.seed,
  });
}

class DietPlanGenerator {
  DietPlanGenerator._({FoodRepository? foodRepo})
      : _foodRepo = foodRepo ?? FoodRepository.instance;

  /// Production singleton — wraps real FoodRepository (Hive).
  static final DietPlanGenerator instance = DietPlanGenerator._();

  /// Test-only constructor letting unit tests inject a fake FoodRepository
  /// that doesn't need Hive.
  factory DietPlanGenerator.forTest(FoodRepository repo) =>
      DietPlanGenerator._(foodRepo: repo);

  // ignore: unused_field
  final FoodRepository _foodRepo;

  /// Generates a 5-slot daily diet plan honoring the anchor-protein-per-meal
  /// rule. Returns [Breakfast, Mid-Morning, Lunch, Evening, Dinner].
  List<DietMealPlan> generate(DietPlanInputs inputs) {
    // Stub — populated in Task 3.
    // ignore: unused_local_variable
    final _ = Random(inputs.seed ?? DateTime.now().millisecondsSinceEpoch);
    return const [];
  }
}
