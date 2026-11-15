// lib/features/nutrition/services/diet_plan_catalog_rules.dart
//
// The two strategy-aware readings of the catalog, used by the generator and
// the swap sheet. They live here, not in diet_plan_catalog.dart, because that
// file must import nothing (scripts/patch_food_database_v4.dart loads it).
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'diet_plan_catalog.dart';

/// The most items of [family] one day of a [strategy] plan may hold; null =
/// uncapped. ONE function for the generator and the swap sheet.
int? dietFamilyCapFor(DietFamily family, DietStrategy strategy) =>
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
