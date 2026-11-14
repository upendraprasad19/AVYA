// lib/features/nutrition/screens/diet_plan_screen_models.dart
//
// The Diet Plan screen's private plan models, moved out unchanged (diet plan
// Unit 2a: the screen crossed the 800-line ceiling,
// scripts/check_god_screen_max_lines.dart).
part of 'diet_plan_screen.dart';

class _MealPlan {
  final String name;
  final String? slotKey; // generator slot key; derived from name on load
  final List<_PlanFoodItem> items;
  final int targetCalories;
  final int targetProtein;

  _MealPlan({
    required this.name,
    this.slotKey,
    required this.items,
    required this.targetCalories,
    required this.targetProtein,
  });
}

class _PlanFoodItem {
  final String foodId;
  final String name;
  final String servingDesc;
  final double servingG;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String category;
  /// Curated catalog role (`DietRole.name`); null for a loaded saved plan
  /// (re-derived by the swap sheet). Never written to the saved JSON.
  final String? role;

  _PlanFoodItem({
    required this.foodId,
    required this.name,
    required this.servingDesc,
    required this.servingG,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.category,
    this.role,
  });
}
