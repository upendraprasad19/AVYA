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

  final FoodRepository _foodRepo;

  // ── Anchor protein sets, by meal slot. Names match food_database.json
  //    rows. Filtered against diet_preference downstream.
  static const _breakfastAnchorNames = {
    'Egg (Whole, boiled)',
    'Whey Protein (scoop)',
    'Greek Yogurt',
    'Paneer',
    'Sprouts (Mixed)',
    'Tofu',
    'Protein Shake (Whey + Milk)',
  };
  static const _mainAnchorNames = {
    'Chicken Breast (grilled)',
    'Mutton Curry',
    'Fish Curry',
    'Tandoori Chicken',
    'Paneer',
    'Toor Dal (cooked)',
    'Rajma (cooked)',
    'Masoor Dal (cooked)',
    'Chana Dal (cooked)',
    'Moong Dal (cooked)',
    'Soybean (boiled)',
    'Tofu',
  };
  static const _snackAnchorNames = {
    'Whey Protein (scoop)',
    'Almonds',
    'Peanuts (Roasted)',
    'Peanut Butter',
    'Sprouts (Mixed)',
    'Greek Yogurt',
    'Protein Shake (Whey + Milk)',
  };

  // Foods that are not vegetarian (filtered out for veg/vegan)
  static const _nonVegNames = {
    'Chicken Breast (grilled)',
    'Chicken Curry',
    'Mutton Curry',
    'Fish Curry',
    'Tandoori Chicken',
    'Egg (Whole, boiled)',
    'Egg White (boiled)',
    'Butter Chicken',
    'Biryani (Chicken)',
  };

  // Foods that are vegetarian but NOT vegan (filtered out for vegan)
  static const _dairyOrEggNames = {
    'Egg (Whole, boiled)',
    'Egg White (boiled)',
    'Paneer',
    'Greek Yogurt',
    'Curd (Dahi)',
    'Milk (Toned)',
    'Milk (Full Cream)',
    'Buttermilk (Chaas)',
    'Lassi (Sweet)',
    'Cheese Slice',
    'Whey Protein (scoop)',
    'Protein Shake (Whey + Milk)',
    'Paneer Butter Masala',
    'Dal Makhani',
    'Butter Chicken',
  };

  /// Slot definitions. Each slot has its calorie share, protein share,
  /// anchor pool, and the carb / fat fillers it accepts.
  static const _slotDefs = [
    _SlotDef(
      name: 'Breakfast',
      slotKey: 'breakfast',
      calorieShare: 0.25,
      proteinShare: 0.25,
      anchorMinProtein: 20,
      anchorPoolNames: _breakfastAnchorNames,
      fillerCategories: ['staples', 'dairy', 'fruits'],
    ),
    _SlotDef(
      name: 'Mid-Morning Snack',
      slotKey: 'mid_morning',
      calorieShare: 0.10,
      proteinShare: 0.10,
      anchorMinProtein: 15,
      anchorPoolNames: _snackAnchorNames,
      fillerCategories: ['fruits', 'nuts_seeds'],
      anchorOptional: true,
    ),
    _SlotDef(
      name: 'Lunch',
      slotKey: 'lunch',
      calorieShare: 0.30,
      proteinShare: 0.30,
      anchorMinProtein: 30,
      anchorPoolNames: _mainAnchorNames,
      fillerCategories: ['staples', 'pulses', 'vegetables'],
    ),
    _SlotDef(
      name: 'Evening Snack',
      slotKey: 'evening',
      calorieShare: 0.10,
      proteinShare: 0.10,
      anchorMinProtein: 15,
      anchorPoolNames: _snackAnchorNames,
      fillerCategories: ['nuts_seeds', 'beverages'],
      anchorOptional: true,
    ),
    _SlotDef(
      name: 'Dinner',
      slotKey: 'dinner',
      calorieShare: 0.25,
      proteinShare: 0.25,
      anchorMinProtein: 30,
      anchorPoolNames: _mainAnchorNames,
      fillerCategories: ['staples', 'pulses', 'vegetables'],
    ),
  ];

  List<DietMealPlan> generate(DietPlanInputs inputs) {
    final rng = Random(inputs.seed ?? DateTime.now().day);

    final meals = <DietMealPlan>[];

    // ── PASS 1: anchor protein per slot ───────────────────────────
    for (final def in _slotDefs) {
      final slotCals = (inputs.calorieTarget * def.calorieShare).round();
      final slotProt = (inputs.proteinTarget * def.proteinShare).round();

      final items = <DietPlanFoodItem>[];

      final anchor = _pickAnchor(def, inputs.dietPreference, rng);
      if (anchor != null) {
        items.add(anchor);
      } else if (!def.anchorOptional) {
        // Last-ditch fallback: take the highest-protein food we can find in
        // the user's diet_preference. Prevents an empty slot if pool is bare.
        final fallback = _highestProteinFallback(inputs.dietPreference);
        if (fallback != null) items.add(fallback);
      }

      meals.add(DietMealPlan(
        name: def.name,
        slotKey: def.slotKey,
        items: items,
        targetCalories: slotCals,
        targetProtein: slotProt,
      ));
    }

    // ── PASS 2: carb staples + fat sources to hit calorie band ────
    for (var i = 0; i < meals.length; i++) {
      final def = _slotDefs[i];
      final meal = meals[i];

      var remainingCals = meal.targetCalories - meal.totalCalories;
      var safety = 4; // hard cap to avoid runaway loops

      while (remainingCals > 80 && safety-- > 0) {
        // Recompute avoidIds each iteration so newly added fillers aren't
        // picked again (otherwise we get "Brown Rice × 3" in one slot).
        final filler = _pickFiller(def, inputs.dietPreference, rng,
            avoidIds: meal.items.map((it) => it.foodId).toSet());
        if (filler == null) break;
        meal.items.add(filler);
        remainingCals = meal.targetCalories - meal.totalCalories;
      }
    }

    // ── PASS 3: protein-deficit recovery ──────────────────────────
    final deficit95 = (inputs.proteinTarget * 0.95).floor();
    var totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    var swapTries = 12;

    while (totalProtein < deficit95 && swapTries-- > 0) {
      final swapped = _swapLowestForHigherProtein(
        meals,
        inputs.dietPreference,
        rng,
      );
      if (!swapped) break;
      totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    }

    return meals;
  }

  // ── Helpers ─────────────────────────────────────────────────────

  DietPlanFoodItem? _pickAnchor(
    _SlotDef def,
    String dietPref,
    Random rng,
  ) {
    final candidates = <Map<String, dynamic>>[];
    for (final name in def.anchorPoolNames) {
      final f = _findFoodByName(name);
      if (f != null && _passesDiet(f, dietPref)) candidates.add(f);
    }
    if (candidates.isEmpty) return null;

    candidates.shuffle(rng);
    // Prefer items whose standard serving already delivers >= anchorMinProtein.
    candidates.sort((a, b) {
      final aP = (a['protein_std'] as num?)?.toDouble() ?? 0.0;
      final bP = (b['protein_std'] as num?)?.toDouble() ?? 0.0;
      return bP.compareTo(aP);
    });

    final pick = candidates.first;
    return _toItem(pick, isAnchor: true);
  }

  DietPlanFoodItem? _pickFiller(
    _SlotDef def,
    String dietPref,
    Random rng, {
    required Set<String> avoidIds,
  }) {
    for (final cat in def.fillerCategories) {
      final pool = _foodRepo
          .getByCategory(cat)
          .where((f) =>
              !avoidIds.contains(f['id']) && _passesDiet(f, dietPref))
          .toList();
      if (pool.isEmpty) continue;
      pool.shuffle(rng);
      return _toItem(pool.first);
    }
    return null;
  }

  /// Walks every meal's items, finds the lowest-protein non-anchor item, and
  /// swaps it for a higher-protein alternative. First tries the slot's
  /// anchor-pool curated set (cross-category, hand-picked high-protein
  /// foods). Falls back to same-category swap if no anchor-pool candidate
  /// is available or all are already in the meal. Returns true if any swap
  /// happened.
  bool _swapLowestForHigherProtein(
    List<DietMealPlan> meals,
    String dietPref,
    Random rng,
  ) {
    DietMealPlan? targetMeal;
    int? targetIdx;
    int? targetMealIdx;
    int lowestProtein = 1000;

    for (var mi = 0; mi < meals.length; mi++) {
      final m = meals[mi];
      for (var idx = 0; idx < m.items.length; idx++) {
        final item = m.items[idx];
        if (item.isAnchor) continue;
        if (item.protein < lowestProtein) {
          lowestProtein = item.protein;
          targetMeal = m;
          targetIdx = idx;
          targetMealIdx = mi;
        }
      }
    }
    if (targetMeal == null || targetIdx == null || targetMealIdx == null) {
      return false;
    }

    final current = targetMeal.items[targetIdx];
    final existingIds = targetMeal.items.map((it) => it.foodId).toSet();

    // Strategy A: try the slot's anchor pool first (highest curated protein).
    // For vegan/limited-pool plans this is what closes the deficit because
    // intra-category swap saturates quickly.
    final slotDef = _slotDefs[targetMealIdx];
    final anchorCandidates = <Map<String, dynamic>>[];
    for (final name in slotDef.anchorPoolNames) {
      final f = _findFoodByName(name);
      if (f == null) continue;
      if (existingIds.contains(f['id'])) continue;
      if (!_passesDiet(f, dietPref)) continue;
      final p = (f['protein_std'] as num?)?.toDouble() ?? 0.0;
      if (p > current.protein) anchorCandidates.add(f);
    }
    if (anchorCandidates.isNotEmpty) {
      anchorCandidates.sort((a, b) {
        final aP = (a['protein_std'] as num?)?.toDouble() ?? 0.0;
        final bP = (b['protein_std'] as num?)?.toDouble() ?? 0.0;
        return bP.compareTo(aP);
      });
      targetMeal.items[targetIdx] = _toItem(anchorCandidates.first);
      return true;
    }

    // Strategy B: same-category swap (original behavior).
    final samePool = _foodRepo
        .getByCategory(current.category)
        .where((f) =>
            f['id'] != current.foodId &&
            !existingIds.contains(f['id']) &&
            _passesDiet(f, dietPref) &&
            ((f['protein_std'] as num?)?.toDouble() ?? 0.0) > current.protein)
        .toList();
    if (samePool.isNotEmpty) {
      samePool.sort((a, b) {
        final aP = (a['protein_std'] as num?)?.toDouble() ?? 0.0;
        final bP = (b['protein_std'] as num?)?.toDouble() ?? 0.0;
        return bP.compareTo(aP);
      });
      targetMeal.items[targetIdx] = _toItem(samePool.first);
      return true;
    }

    // Strategy C: cross-category swap into any protein-bearing category.
    // Used when same-category is saturated (e.g. vegan staples already at
    // Brown Rice) and the slot's anchor pool is exhausted. Pulls in
    // higher-protein dense foods from pulses / nuts_seeds / protein /
    // supplements / dairy regardless of slot definition.
    const proteinBearingCats = [
      'pulses',
      'nuts_seeds',
      'protein',
      'supplements',
      'dairy',
    ];
    final crossPool = <Map<String, dynamic>>[];
    for (final cat in proteinBearingCats) {
      if (cat == current.category) continue; // already tried in B
      crossPool.addAll(_foodRepo.getByCategory(cat).where((f) =>
          !existingIds.contains(f['id']) &&
          _passesDiet(f, dietPref) &&
          ((f['protein_std'] as num?)?.toDouble() ?? 0.0) > current.protein));
    }
    if (crossPool.isEmpty) return false;
    crossPool.sort((a, b) {
      final aP = (a['protein_std'] as num?)?.toDouble() ?? 0.0;
      final bP = (b['protein_std'] as num?)?.toDouble() ?? 0.0;
      return bP.compareTo(aP);
    });
    targetMeal.items[targetIdx] = _toItem(crossPool.first);
    return true;
  }

  DietPlanFoodItem? _highestProteinFallback(String dietPref) {
    Map<String, dynamic>? best;
    double bestP = 0.0;
    for (final f in _foodRepo.getAll()) {
      if (!_passesDiet(f, dietPref)) continue;
      final p = (f['protein_std'] as num?)?.toDouble() ?? 0.0;
      if (p > bestP) {
        bestP = p;
        best = f;
      }
    }
    return best == null ? null : _toItem(best, isAnchor: true);
  }

  Map<String, dynamic>? _findFoodByName(String name) {
    for (final f in _foodRepo.getAll()) {
      if ((f['name'] as String?) == name) return f;
    }
    return null;
  }

  bool _passesDiet(Map<String, dynamic> food, String dietPref) {
    final name = food['name'] as String? ?? '';
    final pref = dietPref.toLowerCase();
    if (pref == 'vegan') {
      if (_nonVegNames.contains(name)) return false;
      if (_dairyOrEggNames.contains(name)) return false;
      // Plant-based pulses, grains, legumes, nuts, fruits, vegetables are
      // all vegan-eligible by default. The exclusion lists above are the
      // authoritative source — honoring `is_vegan: false` would reject
      // foods like dal/rajma/sprouts that aren't explicitly tagged but are
      // perfectly vegan. Only honor `is_vegan == true` as a positive signal
      // (already implied by passing both blocklists).
      return true;
    }
    if (pref == 'veg' || pref == 'vegetarian') {
      return !_nonVegNames.contains(name);
    }
    return true; // non-veg: everything passes
  }

  DietPlanFoodItem _toItem(Map<String, dynamic> f, {bool isAnchor = false}) {
    final servingG =
        (f['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
    final factor = servingG / 100.0;
    final cal = ((f['calories_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final prot = ((f['protein_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final carb = ((f['carbs_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final fat = ((f['fat_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    return DietPlanFoodItem(
      foodId: f['id'] as String? ?? '',
      name: f['name'] as String? ?? 'Unknown',
      servingDesc: f['standard_serving_desc'] as String? ?? '100g',
      servingG: servingG,
      calories: cal.round(),
      protein: prot.round(),
      carbs: carb.round(),
      fat: fat.round(),
      category: f['category'] as String? ?? 'unknown',
      isAnchor: isAnchor,
    );
  }
}

class _SlotDef {
  final String name;
  final String slotKey;
  final double calorieShare;
  final double proteinShare;
  final int anchorMinProtein;
  final Set<String> anchorPoolNames;
  final List<String> fillerCategories;
  final bool anchorOptional;

  const _SlotDef({
    required this.name,
    required this.slotKey,
    required this.calorieShare,
    required this.proteinShare,
    required this.anchorMinProtein,
    required this.anchorPoolNames,
    required this.fillerCategories,
    this.anchorOptional = false,
  });
}
