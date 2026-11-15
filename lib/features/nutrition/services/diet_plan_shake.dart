// lib/features/nutrition/services/diet_plan_shake.dart
//
// Diet plan Unit 4a (2026-11-15, docs/plans/diet-supplements.md section 3):
// the protein shake of a plan whose user turned Supplements on. A PURE
// post-process of the generator's plan: it never enters the generator's
// scoring, so every generator golden and test is untouched, and it is called
// only when `dietSupplementsActive` holds.
//
// The shake is identified by its food id ([isSupplementShake]), a pure
// function: nothing new is written to the saved plan JSON, so a saved or
// restored plan behaves exactly like a fresh one (the swap icon stays off,
// the PDF and the Nutrition hints treat it as an ordinary item).
import '../../../core/constants/food_types.dart';
import 'diet_plan_generator.dart';

/// Whey Isolate (Generic), `assets/data/food_database.json`.
const String kShakeWheyFoodId = 'F0823';

/// Plant Protein (Pea), the vegan row.
const String kShakePlantFoodId = 'F0831';

/// The two shake rows. Disjoint from the curated catalog (a test asserts it),
/// so a generated item can never look like a shake.
const Set<String> kSupplementShakeFoodIds = {kShakeWheyFoodId, kShakePlantFoodId};

/// No shake when the day is less than this many grams short of the protein
/// target (nothing to close).
const int kShakeMinProteinGapG = 15;

/// The day's calories may not pass this share of the calorie target because
/// of the shake (the curated generator's own upper band).
const double kShakeCalorieCeiling = 1.08;

/// When the shake only fits by taking snack items out, it is added only if the
/// day gains more than this many grams of protein net.
const int kShakeMinNetProteinGainG = 8;

bool isSupplementShake(String foodId) => kSupplementShakeFoodIds.contains(foodId);

/// Whey for every food type except vegan; the pea protein row for a vegan.
String shakeFoodIdFor(FoodType type) =>
    type == FoodType.vegan ? kShakePlantFoodId : kShakeWheyFoodId;

num _n(Object? v) => v is num ? v : 0;

/// One scoop of the shake row as a plan item (no catalog entry, no role).
DietPlanFoodItem shakeItem(Map<String, dynamic> row) {
  final g = _n(row['standard_serving_g']).toDouble();
  return DietPlanFoodItem(
    foodId: row['id'] as String,
    name: row['name'] as String? ?? 'Protein shake',
    servingDesc: row['standard_serving_desc'] as String? ?? '1 scoop',
    servingG: g,
    calories: _n(row['calories_std']).round(),
    protein: _n(row['protein_std']).round(),
    carbs: _n(row['carbs_std']).round(),
    fat: _n(row['fat_std']).round(),
    fiber: (_n(row['fiber_per_100g']) * g / 100).round(),
    category: row['category'] as String? ?? 'supplements',
  );
}

/// [meals] with one scoop of the shake added to the evening slot when the day
/// is [kShakeMinProteinGapG] or more short of [proteinTarget].
///
/// If the shake fits under [kShakeCalorieCeiling] of [calorieTarget] it is
/// simply appended. If not, the evening slot's items are taken out in
/// ascending protein-per-kcal order until it fits, and the shake is added only
/// when that gains more than [kShakeMinNetProteinGainG] g of protein net. A
/// missing [row] (a stale food box), a missing evening slot, or a plan that
/// already holds a shake returns [meals] itself. The input is never mutated.
List<DietMealPlan> addProteinShake({
  required List<DietMealPlan> meals,
  required int proteinTarget,
  required int calorieTarget,
  required Map<String, dynamic>? row,
}) {
  if (row == null || row['id'] is! String) return meals;
  final eveningAt = meals.indexWhere((m) => m.slotKey == 'evening');
  if (eveningAt < 0) return meals;
  if (meals.any((m) => m.items.any((i) => isSupplementShake(i.foodId)))) {
    return meals;
  }
  final dayCal = meals.fold<int>(0, (s, m) => s + m.totalCalories);
  final dayProt = meals.fold<int>(0, (s, m) => s + m.totalProtein);
  if (proteinTarget - dayProt < kShakeMinProteinGapG) return meals;

  final shake = shakeItem(row);
  final ceiling = calorieTarget * kShakeCalorieCeiling;
  final evening = meals[eveningAt];

  var keep = [...evening.items];
  var cal = dayCal;
  var prot = dayProt;
  if (cal + shake.calories > ceiling) {
    final order = [for (var i = 0; i < keep.length; i++) i]..sort((a, b) {
        double dens(DietPlanFoodItem x) =>
            x.protein / (x.calories <= 0 ? 1 : x.calories);
        final c = dens(keep[a]).compareTo(dens(keep[b]));
        return c != 0 ? c : a.compareTo(b);
      });
    final removed = <int>{};
    for (final i in order) {
      if (cal + shake.calories <= ceiling) break;
      // An item with no calories frees nothing: never take it out.
      if (keep[i].calories <= 0) continue;
      removed.add(i);
      cal -= keep[i].calories;
      prot -= keep[i].protein;
    }
    if (cal + shake.calories > ceiling ||
        prot + shake.protein - dayProt <= kShakeMinNetProteinGainG) {
      return meals;
    }
    keep = [
      for (var i = 0; i < keep.length; i++)
        if (!removed.contains(i)) keep[i],
    ];
  }

  final next = DietMealPlan(
    name: evening.name,
    slotKey: evening.slotKey,
    items: [...keep, shake],
    targetCalories: evening.targetCalories,
    targetProtein: evening.targetProtein,
  );
  return [
    for (var i = 0; i < meals.length; i++) i == eveningAt ? next : meals[i],
  ];
}
