// lib/features/nutrition/services/diet_plan_swap.dart
//
// The Diet Plan swap sheet's alternatives (diet plan Unit 1, 2026-11-14,
// docs/plans/diet-food-quality.md §3.4). Pure, so it is testable without the
// sheet. CATALOG-ONLY: the old pool (the first five rows of the replaced
// item's whole DB category) is what offered Brie, kimchi and branded rows.
//
// Rules: alternatives are catalog entries of the replaced item's ROLE (its own
// role, or one derived from the catalog / its category for a saved plan) that
// pass the diet preference, are not UPF, whose row is not retired
// (`is_everyday == false`), are not already in the plan, keep their family
// under the daily cap and share no key-ingredient word with the meal's other
// items. Each is offered at the portion closest to the replaced item's
// calories; ordered by that closeness, ties by catalog order.

import 'package:icanbefitter/shared/repositories/food_repository.dart';

import 'curated_diet_plan_generator.dart';
import 'diet_plan_catalog.dart';
import 'diet_plan_generator.dart';

/// Meal name (as saved) → generator slot key. The saved plan JSON stores only
/// the meal name.
const Map<String, String> kDietMealNameToSlotKey = {
  'Breakfast': 'breakfast',
  'Mid-Morning Snack': 'mid_morning',
  'Lunch': 'lunch',
  'Evening Snack': 'evening',
  'Dinner': 'dinner',
};

/// Roles a legacy (non-catalog) item's DB category may stand in for.
const Map<String, List<DietRole>> _categoryRoles = {
  'staples': [DietRole.breakfastMain, DietRole.grain],
  'vegetables': [DietRole.sabzi],
  'pulses': [DietRole.breakfastProtein, DietRole.mainProtein],
  'protein': [DietRole.breakfastProtein, DietRole.mainProtein],
  'dairy': [DietRole.breakfastProtein, DietRole.side],
  'fruits': [DietRole.fruit],
  'nuts_seeds': [DietRole.snack],
};

/// The role a plan item fills, or null when no role fits its slot.
///
/// Order of evidence: the item's own role (a fresh or swapped item) → the
/// catalog entry's roles allowed in the slot (first in [DietRole] enum order,
/// so curd/sprouts/boiled egg resolve deterministically) → the item's DB
/// category mapped onto the slot's roles (a plan saved before Unit 1).
DietRole? resolveSwapRole({
  required String foodId,
  required String category,
  required String? role,
  required String slotKey,
  List<CatalogEntry> catalog = kDietPlanCatalog,
}) {
  if (role != null) {
    for (final r in DietRole.values) {
      if (r.name == role) return r;
    }
  }
  final template = curatedTemplateForSlot(slotKey);
  if (template == null) return null;
  final allowed = template.roles.toSet();
  for (final e in catalog) {
    if (e.foodId != foodId) continue;
    for (final r in DietRole.values) {
      if (e.roles.contains(r) && allowed.contains(r)) return r;
    }
  }
  final mapped = _categoryRoles[category] ?? const <DietRole>[];
  for (final r in DietRole.values) {
    if (mapped.contains(r) && allowed.contains(r)) return r;
  }
  return null;
}

/// Up to [limit] ready-to-use replacement items (portion-sized, role set).
List<DietPlanFoodItem> swapAlternatives({
  required String foodId,
  required String category,
  required int calories,
  required String? role,
  required String slotKey,
  required String dietPreference,
  required List<String> planFoodIds,
  required List<String> slotOtherNames,
  required FoodRepository repo,
  List<CatalogEntry> catalog = kDietPlanCatalog,
  int limit = 6,
}) {
  final resolved = resolveSwapRole(
    foodId: foodId,
    category: category,
    role: role,
    slotKey: slotKey,
    catalog: catalog,
  );
  if (resolved == null) return const [];

  final familyOf = {for (final e in catalog) e.foodId: e.family};
  final familyCount = <DietFamily, int>{};
  var replacedSeen = false;
  for (final id in planFoodIds) {
    if (id == foodId && !replacedSeen) {
      replacedSeen = true; // the item being replaced leaves the plan
      continue;
    }
    final f = familyOf[id];
    if (f != null) familyCount[f] = (familyCount[f] ?? 0) + 1;
  }
  final mealTokens = <String>{
    for (final n in slotOtherNames) ...coherenceTokensOf(n),
  };
  final inPlan = planFoodIds.toSet();

  final scored = <({double diff, int index, DietPlanFoodItem item})>[];
  for (var i = 0; i < catalog.length; i++) {
    final e = catalog[i];
    if (!e.roles.contains(resolved)) continue;
    if (inPlan.contains(e.foodId)) continue;
    final row = repo.getById(e.foodId);
    if (row == null || row.isEmpty) continue;
    if (row['is_everyday'] == false) continue; // retired by the asset
    if (row['is_ultra_processed'] == true) continue;
    if (!DietPlanGenerator.passesDiet(row, dietPreference, family: e.family)) {
      continue;
    }
    final cap = dietFamilyDailyCap[e.family];
    if (cap != null && (familyCount[e.family] ?? 0) >= cap) {
      continue;
    }
    final cand = CuratedCandidate(e, row, i);
    if (cand.tokens.intersection(mealTokens).isNotEmpty) continue;

    var bestM = e.portions.first;
    var bestDiff = double.infinity;
    for (final m in e.portions) {
      final d = (cand.kcal * m - calories).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestM = m;
      }
    }
    scored.add((diff: bestDiff, index: i, item: cand.toItem(bestM, resolved)));
  }
  scored.sort((a, b) {
    final c = a.diff.compareTo(b.diff);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
  return [for (final s in scored.take(limit)) s.item];
}
