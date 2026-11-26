// lib/features/nutrition/services/diet_plan_catalog_rules.dart
//
// The two strategy-aware readings of the catalog, used by the generator and
// the swap sheet. They live here, not in diet_plan_catalog.dart, because that
// file must import nothing (scripts/patch_food_database_v4.dart loads it).
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'diet_plan_catalog.dart';

/// Diet protein rules (2026-11-18): an eggetarian plan may hold 2 egg items a
/// day and a pescatarian plan 2 fish items (their protein is those foods;
/// every other food type keeps the catalog cap of 1). Checked before the
/// strategy overrides; neither override map holds egg or fish today, so the
/// order is a no-op now and matters only for a future overlap.
int? dietFamilyFoodTypeCapOverride(DietFamily family, FoodType? foodType) =>
    switch (foodType) {
      FoodType.eggetarian when family == DietFamily.egg => 2,
      FoodType.pescatarian when family == DietFamily.fish => 2,
      _ => null,
    };

/// The most items of [family] one day of a [strategy] plan may hold; null =
/// uncapped. ONE function for the generator and the swap sheet. [foodType]
/// is optional: without it the cap is exactly what it was before the diet
/// protein rules.
int? dietFamilyCapFor(
  DietFamily family,
  DietStrategy strategy, {
  FoodType? foodType,
}) =>
    dietFamilyFoodTypeCapOverride(family, foodType) ??
    (strategy == DietStrategy.lowCarb
        ? dietFamilyLowCarbPlanCapOverride[family]
        : null) ??
    (strategy == DietStrategy.balanced
        ? null
        : dietFamilyLowCarbCapOverride[family]) ??
    dietFamilyDailyCap[family];

/// Whether a plan of [strategy] may use [e] (generator and swap sheet).
bool catalogEntryOffered(CatalogEntry e, DietStrategy strategy) =>
    switch (strategy) {
      DietStrategy.balanced => !e.lowCarbOnly,
      DietStrategy.keto => !e.lowCarbPlansOnly,
      DietStrategy.lowCarb => true,
    };

/// Whether the GENERATOR may pick [e] for a [strategy] plan: offered, and not a
/// swap-only entry (Diet chart v3). The swap sheet keeps [catalogEntryOffered].
bool generatorOffered(CatalogEntry e, DietStrategy strategy) =>
    !e.swapOnly && catalogEntryOffered(e, strategy);
