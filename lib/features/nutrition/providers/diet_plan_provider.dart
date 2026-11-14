import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../services/diet_plan_catalog.dart';
import '../services/diet_plan_generator.dart';
import '../services/diet_strategy_flags.dart';
import 'nutrition_provider.dart';

/// Whether a saved diet plan was built for [current], the strategy the Diet
/// Plan screen would request now (`planStrategyFor(effective, foodType)`;
/// Unit 3b, docs/plans/diet-strategy-3b.md §3.7). A plan stamped with
/// `diet_strategy` matches only that strategy; an unstamped plan (saved with
/// the flag off, or before Unit 3a) matches Balanced only. Callers consult it
/// ONLY with [DietStrategyFlags.enabled]: with the flag off a stamped plan
/// still loads (today's behaviour).
bool savedPlanMatchesStrategy(Map<dynamic, dynamic> plan, DietStrategy current) {
  final stamp = plan['diet_strategy'];
  if (stamp == null) return current == DietStrategy.balanced;
  return dietStrategyOf(stamp) == current;
}

/// Whether a saved diet plan may be shown for [current] (diet plan Unit 2a,
/// docs/plans/diet-food-type.md §2.4). A plan saved with a `food_type` of
/// another type is not shown: its foods would be off-diet (a saved chicken
/// plan after the user picked Veg).
///
/// A plan saved before Unit 2a has no `food_type`. It is shown when its
/// FOODS fit [current] (every item's food row passes `passesDiet`, with its
/// catalog family; a row the food box does not hold does not fit), and
/// always for Non-veg. B-pass finding 3: showing such a plan unconditionally
/// let a re-save stamp a chicken plan with the user's Veg type, after which
/// it matched forever. [rowOf] is a test seam (default: the food box).
bool savedPlanMatchesFoodType(
  Map<dynamic, dynamic> plan,
  FoodType current, {
  Map<String, dynamic>? Function(String foodId)? rowOf,
}) {
  final saved = plan['food_type'];
  if (saved != null) return foodTypeOf(saved) == current;
  if (current == FoodType.nonVeg) return true;
  final lookup = rowOf ?? FoodRepository.instance.getById;
  final meals = plan['meals'];
  if (meals is! List) return true; // nothing to judge
  for (final m in meals) {
    final items = m is Map ? m['items'] : null;
    if (items is! List) continue;
    for (final it in items) {
      final id = it is Map ? it['food_id'] : null;
      if (id is! String) return false;
      final row = lookup(id);
      if (row == null ||
          !DietPlanGenerator.passesDiet(row, current.storageKey,
              family: dietCatalogFamily(id))) {
        return false;
      }
    }
  }
  return true;
}

/// One planned meal slot derived from the saved diet plan
/// (`userBox['saved_diet_plan']`, written by `DietPlanScreen._savePlan` —
/// migrated from configBox in Test #11.1).
///
/// Used by [TodaysMealsCard] to render a "From Your Diet Plan" hint on
/// any empty slot — BREAKFAST / LUNCH / DINNER / SNACK — so the user can
/// tap `+ LOG` and have the food search pre-filtered for the planned
/// first food.
class PlannedSlot {
  /// Normalised slot key: `breakfast` / `lunch` / `dinner` / `snack`.
  final String slot;

  /// One-line summary of planned foods joined by ` · `
  /// (e.g. "Oats · Boiled eggs · Banana").
  final String summary;

  /// Total kcal summed across items in this planned meal.
  final double calories;

  /// Total protein (g) summed across items.
  final double protein;

  /// First item's `name` (display hint) — used to pre-fill the food
  /// search query when the user taps `+ LOG` on an empty slot.
  final String? firstFoodName;

  const PlannedSlot({
    required this.slot,
    required this.summary,
    required this.calories,
    required this.protein,
    required this.firstFoodName,
  });
}

/// Returns the planned meal for each slot keyed by lowercase slot name.
/// Empty map when no diet plan is saved. Invalidate after save/clear.
///
/// Maps the free-form `name` field on each saved-meal entry to a
/// canonical slot key:
///   Breakfast → breakfast
///   Lunch     → lunch
///   Dinner    → dinner
///   Snack(s)  → snack
/// Unknown names fall back to `snack` so the plan is never silently
/// dropped.
class DietPlanNotifier extends Notifier<Map<String, PlannedSlot>> {
  @override
  Map<String, PlannedSlot> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // Unit 2a: rebuild on a food-type change from ANY writer (the Diet Plan
    // selector or Edit Profile). An enum, so a profile write that keeps the
    // food type does not rebuild.
    final foodType =
        ref.watch(userProfileProvider.select((p) => foodTypeOfProfile(p)));
    // Unit 3b §3.7: with the flag on, rebuild on a change of the EFFECTIVE
    // strategy and give no hints for a plan built for another one. No new
    // watch with the flag off (the 3a flag-off dependency rule).
    final DietStrategy? effective = DietStrategyFlags.enabled
        ? ref.watch(macroTargetsProvider.select(dietStrategyOfTargets))
        : null;
    final raw = UserRepository.instance.getSavedDietPlan();
    if (raw == null) return const {};
    if (!savedPlanMatchesFoodType(raw, foodType)) return const {};
    if (effective != null &&
        !savedPlanMatchesStrategy(raw, planStrategyFor(effective, foodType))) {
      return const {};
    }

    final meals = raw['meals'];
    if (meals is! List || meals.isEmpty) return const {};

    final result = <String, PlannedSlot>{};
    for (final m in meals) {
      if (m is! Map) continue;
      final name = (m['name'] as String? ?? '').trim().toLowerCase();
      final slot = switch (name) {
        'breakfast' => 'breakfast',
        'lunch' => 'lunch',
        'dinner' => 'dinner',
        'snack' || 'snacks' => 'snack',
        _ => 'snack',
      };

      final items = (m['items'] as List?) ?? const [];
      if (items.isEmpty) continue;

      double cals = 0;
      double protein = 0;
      final names = <String>[];
      String? firstFoodName;
      for (final item in items) {
        if (item is! Map) continue;
        cals += (item['calories'] as num?)?.toDouble() ?? 0;
        protein += (item['protein'] as num?)?.toDouble() ?? 0;
        final itemName = (item['name'] as String? ?? '').trim();
        if (itemName.isEmpty) continue;
        firstFoodName ??= itemName;
        names.add(itemName);
      }
      if (names.isEmpty) continue;

      // Multi-items per slot is rare in the current diet-plan screen but
      // possible; last one wins so a user who tweaked the plan sees the
      // most recent version.
      result[slot] = PlannedSlot(
        slot: slot,
        summary: names.join(' \u00B7 '),
        calories: cals,
        protein: protein,
        firstFoodName: firstFoodName,
      );
    }
    return result;
  }
}

final dietPlanProvider =
    NotifierProvider<DietPlanNotifier, Map<String, PlannedSlot>>(
        DietPlanNotifier.new);
