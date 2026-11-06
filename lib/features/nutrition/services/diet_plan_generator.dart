// lib/features/nutrition/services/diet_plan_generator.dart
//
// Diet plan generator service. Extracted from diet_plan_screen.dart so the
// algorithm is testable without booting Flutter widgets.
//
// Algorithm: anchor-protein-per-meal (APK Test #3 / Obs 2, 2026-04-26).
// Four passes per generation (Pass 4 added APK Test #3 / Option D, 2026-04-26):
//   1. Pick an anchor protein for each meal slot, filtered by diet_preference.
//   2. Add carb staples + fat sources to hit the per-slot calorie band. When
//      a slot's anchor already meets >=90% of its protein share, smart filler
//      exclusion drops 'pulses' (lunch/dinner) or 'dairy' (breakfast if anchor
//      was dairy) from the candidate pool to prevent double-dipping protein.
//   3. Verify daily total protein >= 95% of target. If short, swap the
//      lowest-protein-density item for a higher alternative within the same
//      calorie band.
//   4. Verify daily total protein <= 115% of target. If over, swap the
//      highest-protein non-anchor item for a lower-protein filler in the same
//      calorie band (±20%). Anchors are protected from swap.
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
  int get totalFiber => items.fold(0, (s, i) => s + i.fiber);
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
  final int fiber;
  final String category;
  final bool isAnchor; // true = the slot's anchor protein
  final bool isQuotaLocked; // true = Pass 0 group-quota item; Pass 3/4 must not swap it out

  DietPlanFoodItem({
    required this.foodId,
    required this.name,
    required this.servingDesc,
    required this.servingG,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0,
    required this.category,
    this.isAnchor = false,
    this.isQuotaLocked = false,
  });
}

/// Inputs to the generator.
class DietPlanInputs {
  final int calorieTarget;
  final int proteinTarget;
  final String dietPreference; // 'veg' | 'vegan' | 'non-veg'
  final int fiberTarget; // from profile['fiber_grams'] ?? 30 (nutrition_provider.dart)
  final int? seed; // optional override for deterministic test runs

  const DietPlanInputs({
    required this.calorieTarget,
    required this.proteinTarget,
    required this.dietPreference,
    this.fiberTarget = 30,
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

  // ── Lazily-built indices (O(N) build, O(1) lookup afterwards) ────
  //
  // Built once on the first generate() call. Nulled by clearCache() when
  // the food database changes (e.g. user adds a custom food).
  //
  // _allFoodsCache    — snapshot of _foodRepo.getAll() so we don't rebuild
  //                     the Hive list on every lookup within a single call.
  // _byNameIndex      — lower(name) → food row; covers _findFoodByName.
  // _byCategoryIndex  — category → food rows; covers _pickFiller + swaps.
  List<Map<String, dynamic>>? _allFoodsCache;
  Map<String, Map<String, dynamic>>? _byNameIndex;
  Map<String, List<Map<String, dynamic>>>? _byCategoryIndex;

  /// Rebuilds indices if not yet initialised.
  void _ensureIndices() {
    if (_byNameIndex != null) return; // already built

    final all = _foodRepo.getAll();
    _allFoodsCache = all;

    final nameIdx = <String, Map<String, dynamic>>{};
    final catIdx = <String, List<Map<String, dynamic>>>{};
    for (final f in all) {
      final name = (f['name'] as String?)?.toLowerCase();
      if (name != null) nameIdx[name] = f;
      final cat = (f['category'] as String?)?.toLowerCase();
      if (cat != null) catIdx.putIfAbsent(cat, () => []).add(f);
    }
    _byNameIndex = nameIdx;
    _byCategoryIndex = catIdx;
  }

  /// O(1) lookup by exact name (case-insensitive).
  Map<String, dynamic>? _findFoodByNameIndexed(String name) =>
      _byNameIndex?[name.toLowerCase()];

  /// O(K) access to all foods in [category] (K = category size).
  List<Map<String, dynamic>> _foodsByCategory(String category) =>
      _byCategoryIndex?[category.toLowerCase()] ?? const [];

  /// Call whenever the food list changes (custom food added/deleted).
  /// Next generate() will rebuild indices from the new snapshot.
  void clearCache() {
    _allFoodsCache = null;
    _byNameIndex = null;
    _byCategoryIndex = null;
  }


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
    // vegan-density additions (2026-09 batch): the vegan breakfast pool was
    // Tofu(8g)/Sprouts(7g) only — every other breakfast anchor is dairy/egg
    'Soya Chunks (Nutrela, dry)',
    'Soy Chunks (cooked)',
    'Tofu (Firm)',
    'Tempeh (cooked)',
    'Seitan (cooked)',
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
    // Vegan density additions (2026-09 meal-quality batch): the vegan
    // archetype's only in-band main anchor was Soybean (boiled); day-
    // uniqueness then forced dinner down to a ~17g dal. These rows exist
    // in the DB (F0373/F0374/F1014) with 21-27g protein per serving.
    'Soy Chunks (cooked)',
    'Soya Chaap',
    'Tofu (Firm)',
    // appended real-DB rows (F1432/F1439/F1440 — scripts/
    // append_vegan_protein_rows.dart): vegan archetype on the real 1431-
    // row DB landed 116-148g against the 142.5g floor without them
    'Soya Chunks (Nutrela, dry)',
    'Tempeh (cooked)',
    'Seitan (cooked)',
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
    // founder's own diet charts put soya chunks in the snack slot
    'Soya Chunks (Nutrela, dry)',
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

  // Foods that are vegetarian but NOT vegan (filtered out for vegan).
  // Paneer-dish rows living in the 'vegetables' category (Saag Paneer,
  // Palak Paneer, Matar Paneer, Methi Malai Matar, Paneer Bhurji) are
  // listed by name here — plan-review round 3 found they bypass the
  // category-based filter and leak into vegan plans via the lunch/dinner
  // vegetables filler pool.
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
    'Saag Paneer',
    'Palak Paneer',
    'Matar Paneer',
    'Methi Malai Matar',
    'Paneer Bhurji',
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
    _ensureIndices(); // O(N) once; O(1) on subsequent calls
    final rng = Random(inputs.seed ?? DateTime.now().day);

    // Day-level food uniqueness (2026-09 meal-quality batch). Hard in
    // Pass 1 (anchors) + Pass 0 quotas + Pass 2 (fillers); Pass 3/4
    // recovery swaps are EXEMPT — protein correctness outranks variety,
    // and the vegan archetype's recovery path depends on cross-meal
    // freedom (plan-review rounds 2-3). Swap helpers still PREFER
    // not-yet-used candidates where one exists.
    final usedIds = <String>{};

    final meals = <DietMealPlan>[];

    // ── PASS 1: anchor protein + group-quota items per slot ──────
    for (final def in _slotDefs) {
      final slotCals = (inputs.calorieTarget * def.calorieShare).round();
      final slotProt = (inputs.proteinTarget * def.proteinShare).round();

      final items = <DietPlanFoodItem>[];

      final anchor = _pickAnchor(
        def,
        inputs.dietPreference,
        rng,
        slotProteinTarget: slotProt,
        usedIds: usedIds,
      );
      if (anchor != null) {
        items.add(anchor);
        usedIds.add(anchor.foodId);
      } else if (!def.anchorOptional) {
        // Last-ditch fallback: take the highest-protein food we can find in
        // the user's diet_preference. Prevents an empty slot if pool is bare.
        final fallback = _highestProteinFallback(inputs.dietPreference);
        if (fallback != null) items.add(fallback);
      }

      // ── PASS 0 group quotas (compose-then-fill) ────────────────
      // Mandatory volume foods placed BEFORE calorie filling so the
      // staple-first filler order can no longer starve them out.
      //   lunch/dinner → 1 vegetables item
      //   breakfast    → 1 dairy-or-fruit item
      // Quota items are isQuotaLocked: Pass 3/4 may not swap them out
      // (they are the lowest-protein items by construction — without the
      // lock, deficit recovery would undo this batch's own quota).
      // Empty pool ⇒ quota skipped for that slot (counted by tests; the
      // real 1431-row DB never hits it for veg-pref diets).
      final quota = _pickQuotaItem(def, inputs.dietPreference, rng, usedIds);
      if (quota != null) {
        items.add(quota);
        usedIds.add(quota.foodId);
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
      var safety = 6; // hard cap to avoid runaway loops (raised 4→6: quota
      // items consume one iteration before filling starts — review F2)

      // Threshold 80 -> 50 (2026-09 batch): the fit filter bounds filler
      // size, so slots with a 50-80 kcal gap no longer stay under-filled
      // (observed: dinner left 72 kcal / ~5g protein on the table at the
      // old threshold, busting the veg-cut archetype's floor on the real DB).
      while (remainingCals > 50 && safety-- > 0) {
        // Recompute avoidIds each iteration so newly added fillers aren't
        // picked again (otherwise we get "Brown Rice × 3" in one slot).
        // Smart exclusion: when slot's current protein already meets >=90%
        // of slot protein target, drop 'pulses' (lunch/dinner) and 'dairy'
        // (breakfast w/ dairy anchor) from the filler pool to prevent
        // double-dipping protein on top of the meat/paneer anchor.
        final filler = _pickFiller(
          def,
          inputs.dietPreference,
          rng,
          meal: meal,
          remainingCals: remainingCals,
          avoidIds: meal.items.map((it) => it.foodId).toSet(),
          usedIds: usedIds,
          slotProteinSoFar: meal.totalProtein,
          slotProteinTarget: meal.targetProtein,
          anchorCategory: meal.items.isNotEmpty && meal.items.first.isAnchor
              ? meal.items.first.category
              : null,
        );
        if (filler == null) break;
        meal.items.add(filler);
        usedIds.add(filler.foodId);
        remainingCals = meal.targetCalories - meal.totalCalories;
      }
    }

    // ── PASS 3: protein-deficit recovery ──────────────────────────
    final deficit95 = (inputs.proteinTarget * 0.95).floor();
    var totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    var swapTries = 12;

    while (totalProtein < deficit95 && swapTries-- > 0) {
      if (_upgradeWeakAnchors(
        meals,
        inputs.dietPreference,
        usedIds,
        currentTotal: totalProtein,
        dailyCeiling: (inputs.proteinTarget * 1.15).ceil(),
      )) {
        totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
        continue;
      }
      final swapped = _swapLowestForHigherProtein(
        meals,
        inputs.dietPreference,
        rng,
        usedIds: usedIds,
        neededProtein: deficit95 - totalProtein,
      );
      if (!swapped) break;
      totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    }

    // ── PASS 4: protein-surplus trim (APK Test #3 / Option D) ─────
    // Mirror of Pass 3 inverted. If total protein > 115% target, swap
    // the highest-protein non-anchor item for a lower-protein filler in
    // the same calorie band (±20%). Anchors are protected (except
    // optional snack anchors — see _swapHighestForLowerProtein).
    //
    // Target window: daily total in [105%, 115%]. If a single trim would
    // push total below 105% of target (under-correction), skip and try
    // another over-shooting meal. Prevents the trim from dropping the
    // daily total below the deficit floor when one big snack-anchor
    // removal alone over-corrects.
    final ceiling115 = (inputs.proteinTarget * 1.15).ceil();
    final softFloor105 = (inputs.proteinTarget * 1.05).floor();
    totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    var trimTries = 12;

    while (totalProtein > ceiling115 && trimTries-- > 0) {
      final trimmed = _swapHighestForLowerProtein(
        meals,
        inputs.dietPreference,
        rng,
        usedIds: usedIds,
        softFloor: softFloor105,
        dailyFloor: deficit95,
        currentTotal: totalProtein,
      );
      if (!trimmed) break;
      totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    }

    // ── PASS 5: fiber floor (2026-09 meal-quality batch) ──────────
    // The original four passes never read the profile's fiber target —
    // the observed plan delivered ~12g against a 30g target. If the daily
    // total is under 70% of [inputs.fiberTarget], swap the lowest-fiber
    // staple for a whole-grain alternative in the same calorie band.
    // Bounded tries, no-op when no candidate exists (mirrors swapTries).
    final fiberFloor = (inputs.fiberTarget * 0.7).floor();
    var totalFiber = meals.fold<int>(0, (s, m) => s + m.totalFiber);
    var fiberTries = 6;

    while (totalFiber < fiberFloor && fiberTries-- > 0) {
      final swapped = _swapLowestFiberStaple(meals, inputs.dietPreference, rng, usedIds);
      if (!swapped) break;
      totalFiber = meals.fold<int>(0, (s, m) => s + m.totalFiber);
    }

    return meals;
  }

  // ── Group-quota helpers (Pass 0) ───────────────────────────────

  /// Mandatory volume item for [def]'s slot: 1 vegetables item for
  /// lunch/dinner, 1 dairy-or-fruit item for breakfast, none for snacks.
  /// Returns null when the slot has no quota or the filtered pool is empty.
  DietPlanFoodItem? _pickQuotaItem(
    _SlotDef def,
    String dietPref,
    Random rng,
    Set<String> usedIds,
  ) {
    final List<String> quotaCategories;
    switch (def.slotKey) {
      case 'lunch':
      case 'dinner':
        quotaCategories = const ['vegetables'];
        break;
      case 'breakfast':
        quotaCategories = const ['dairy', 'fruits'];
        break;
      default:
        return null; // snack slots: fillers are already fruit/nut/dairy
    }

    for (final cat in quotaCategories) {
      final pool = _foodsByCategory(cat).where((f) =>
          !_isUpf(f) &&
          _passesDiet(f, dietPref) &&
          _matchesMeal(f, def.slotKey) &&
          !usedIds.contains(f['id'] as String?));
      if (pool.isEmpty) continue;
      final list = pool.toList()..shuffle(rng);
      return _toItem(list.first, isQuotaLocked: true);
    }
    return null;
  }

  /// Per-category filler caps (plan-review round 1, finding 6: with
  /// staples capped, pulses stacked "Rajma + Chana Dal + Masoor Dal" in
  /// one slot through the back door — the same complaint class the batch
  /// set out to fix).
  int _categoryCap(String category) {
    switch (category) {
      case 'staples':
        return 1; // soft: the >20%-under-target exception may add a 2nd
      case 'pulses':
        return 1;
      case 'vegetables':
        return 2;
      default:
        return 99; // fruits/dairy/nuts/beverages: bounded by safety + fit filter
    }
  }

  int _countCategory(DietMealPlan meal, String category) =>
      meal.items.where((it) => it.category == category).length;

  /// True when replacing [current] with a [replacement] of [replacementCat]
  /// keeps the meal inside the per-category caps (Pass 3/4 must not
  /// re-stack a category through a swap — the cap counts the ANCHOR too:
  /// a dal anchor IS category 'pulses', so a pulses filler next to it is
  /// exactly the double-dip the cap exists to prevent).
  bool _swapRespectsCap(DietMealPlan meal, DietPlanFoodItem current,
      String replacementCat) {
    final after = _countCategory(meal, replacementCat) -
        (current.category == replacementCat ? 1 : 0) +
        1;
    if (replacementCat == 'staples') {
      // Same re-entrant exception as Pass 2: a 2nd staple is allowed only
      // while the slot is >20% under its calorie target.
      final count = after;
      if (count >= 1) {
        final under = meal.targetCalories - meal.totalCalories;
        return count <= 1 || under > (meal.targetCalories * 0.2).round();
      }
      return true;
    }
    if (replacementCat == 'pulses') {
      // Mirrored pulses exception: 2nd pulses only while the slot is >20%
      // under its protein target (Pass 2's rule, applied to recovery swaps).
      if (meal.targetProtein > 0) {
        final under = meal.targetProtein - meal.totalProtein;
        final cap = under > (meal.targetProtein * 0.2).round() ? 2 : 1;
        return after <= cap;
      }
      return after <= 1;
    }
    return after <= _categoryCap(replacementCat);
  }

  // ── Helpers ─────────────────────────────────────────────────────

  DietPlanFoodItem? _pickAnchor(
    _SlotDef def,
    String dietPref,
    Random rng, {
    required int slotProteinTarget,
    required Set<String> usedIds,
  }) {
    final candidates = <Map<String, dynamic>>[];
    for (final name in def.anchorPoolNames) {
      final f = _findFoodByNameIndexed(name);
      if (f == null) continue;
      if (_isUpf(f)) continue; // "never UPF" holds on the anchor path too (B-pass finding 5)
      if (_passesDiet(f, dietPref)) candidates.add(f);
    }
    if (candidates.isEmpty) return null;

    // Hard day-uniqueness on anchors (plan-review round 3, finding 1):
    // Greek Yogurt sits in BOTH the breakfast and snack anchor pools, so
    // the two snack slots could independently anchor it — the observed
    // Greek-yogurt-twice bug. For OPTIONAL-anchor slots (snacks) an
    // exhausted pool means NO anchor this time — the slot legitimately
    // becomes a filler-only snack (Pass 3 recovers any protein gap; a
    // repeat here is precisely the dupe this pass exists to kill). For
    // REQUIRED slots we allow a repeat as the last resort — an empty
    // mandatory slot is worse than a repeat.
    var pool =
        candidates.where((f) => !usedIds.contains(f['id'] as String?)).toList();
    if (pool.isEmpty) {
      if (def.anchorOptional) return null;
      pool = candidates;
    }

    // APK Test #3 / Option D Part C — anchor protein cap.
    //
    // Without a cap, Pass 1 picked the highest-protein anchor in the pool
    // (e.g. Protein Shake at 90g protein for a 30g-target breakfast slot).
    // That alone could blow past the 115% daily ceiling before any fillers
    // were added — leaving Pass 4's surplus-trim helpless because anchors
    // are protected from swap.
    //
    // Rule: filter anchors to those whose protein is in
    //   [anchorMinProtein, slotProteinTarget * 1.5]
    // and randomly pick from the in-band set (preserves diversity across
    // plan regenerations). If nothing falls in-band (rare — e.g. a slot
    // whose pool only contains very-high-protein items), fall back to the
    // smallest anchor in the unfiltered pool that meets the floor; if
    // even that fails, accept the smallest available anchor outright.
    final slotProtCap = (slotProteinTarget * 1.5).round();

    final inBand = pool.where((f) {
      final p = (f['protein_std'] as num?)?.toDouble() ?? 0.0;
      return p >= def.anchorMinProtein && p <= slotProtCap;
    }).toList();

    if (inBand.isNotEmpty) {
      inBand.shuffle(rng);
      return _toItem(inBand.first, isAnchor: true);
    }

    // Fallback — no anchor falls in [floor, cap]. Pick the highest-protein
    // anchor that's still <= cap (preserves "hit slot target" intent without
    // exceeding the cap). If every candidate exceeds the cap, accept the
    // smallest one (least bad over-shoot — Pass 4 surplus-trim is the only
    // safety net since anchors are protected). If every candidate is below
    // floor (rare — weak veg pool), use the highest available so the slot
    // still has a meaningful protein anchor.
    pool.sort((a, b) {
      final aP = (a['protein_std'] as num?)?.toDouble() ?? 0.0;
      final bP = (b['protein_std'] as num?)?.toDouble() ?? 0.0;
      return bP.compareTo(aP); // descending
    });

    // Try: highest-protein anchor <= cap (regardless of floor)
    for (final f in pool) {
      final p = (f['protein_std'] as num?)?.toDouble() ?? 0.0;
      if (p <= slotProtCap) {
        return _toItem(f, isAnchor: true);
      }
    }

    // Every anchor exceeds cap — accept the smallest (least over-shoot).
    final pick = pool.last;
    return _toItem(pick, isAnchor: true);
  }

  /// Per-serving kcal of a food row (mirrors _toItem math).
  static int _servingKcal(Map<String, dynamic> f) =>
      (((f['calories_per_100g'] as num?)?.toDouble() ?? 0.0) *
              ((f['standard_serving_g'] as num?)?.toDouble() ?? 100.0) /
              100.0)
          .round();

  DietPlanFoodItem? _pickFiller(
    _SlotDef def,
    String dietPref,
    Random rng, {
    required DietMealPlan meal,
    required int remainingCals,
    required Set<String> avoidIds,
    required Set<String> usedIds,
    int slotProteinSoFar = 0,
    int slotProteinTarget = 0,
    String? anchorCategory,
  }) {
    // Smart Pass 2 filler exclusion (APK Test #3 / Option D Part A):
    // when the slot's anchor already covers >=90% of the slot's protein
    // target, exclude high-protein filler categories so we don't
    // double-dip protein on top of the anchor.
    var categories = def.fillerCategories;
    final anchorMeetsShare = slotProteinTarget > 0 &&
        slotProteinSoFar >= (slotProteinTarget * 0.9).round();
    if (anchorMeetsShare) {
      categories = categories.where((cat) {
        if ((def.slotKey == 'lunch' || def.slotKey == 'dinner') &&
            cat == 'pulses') {
          return false;
        }
        if (def.slotKey == 'breakfast' &&
            cat == 'dairy' &&
            anchorCategory == 'dairy') {
          return false;
        }
        return true;
      }).toList();
    }

    // Hard invariants that NEVER yield (plan-review rounds 1-3):
    //  - is_ultra_processed rows are never generated
    //  - per-meal dedupe (avoidIds)
    // Degradation order for the ELASTIC constraints, tried in stages:
    //   stage 1: meal_fit + fit-filter(serving ≤ remainingCals+50) + day-unique
    //   stage 2: relax meal_fit
    //   stage 3: relax fit-filter (nuts_seeds keep their hard ≤300 kcal/serving cap)
    //   stage 4: relax day-uniqueness
    // Category caps + the re-entrant staples exception are applied by the
    // caller-side loop below, before stage relaxation is reached.
    for (final cat in categories) {
      // Category caps. The staples cap YIELDS BEFORE THE CALORIE BAND does
      // (review F2): a 2nd staple is allowed while the slot is >20% under
      // its calorie target (re-entrant — no fixed addition count). Pulses
      // get the mirrored rule on the PROTEIN band: a 2nd pulses while the
      // slot is >20% under its protein target (the 3-way rajma+chana+masoor
      // stacking that motivated the cap stays banned).
      final count = _countCategory(meal, cat);
      if (cat == 'staples') {
        final under = meal.targetCalories - meal.totalCalories;
        if (count >= 2) continue;
        if (count >= 1 &&
            under <= (meal.targetCalories * 0.2).round()) {
          continue;
        }
      } else if (cat == 'pulses' && slotProteinTarget > 0) {
        final under = slotProteinTarget - slotProteinSoFar;
        if (count >= 2) continue;
        if (count >= 1 && under <= (slotProteinTarget * 0.2).round()) {
          continue;
        }
      } else if (count >= _categoryCap(cat)) {
        continue;
      }

      // Stage relaxation per category, strictest first.
      for (var stage = 1; stage <= 4; stage++) {
        final respectMealFit = stage < 2;
        final respectFit = stage < 3;
        final respectDayUnique = stage < 4;

        final pool = _foodsByCategory(cat).where((f) {
          final id = f['id'] as String?;
          if (id == null || avoidIds.contains(id)) return false;
          if (_isUpf(f)) return false;
          if (!_passesDiet(f, dietPref)) return false;
          if (respectMealFit && !_matchesMeal(f, def.slotKey)) return false;
          if (respectFit) {
            final limit = cat == 'nuts_seeds' ? 300 : remainingCals + 50;
            if (_servingKcal(f) > limit) return false;
          } else if (cat == 'nuts_seeds' && _servingKcal(f) > 300) {
            // nuts_seeds serving cap never relaxes away entirely —
            // it is the anti-Pringles guard for the only fat-dense
            // filler pool (review F3: per-serving, not kcal/g).
            return false;
          }
          if (respectDayUnique && usedIds.contains(id)) return false;
          return true;
        }).toList();

        if (pool.isEmpty) continue;
        pool.shuffle(rng);
        return _toItem(pool.first);
      }
    }
    return null;
  }

  /// Walks every meal's items, finds the lowest-protein non-anchor item, and
  /// swaps it for a higher-protein alternative. First tries the slot's
  /// anchor-pool curated set (cross-category, hand-picked high-protein
  /// foods). Falls back to same-category swap if no anchor-pool candidate
  /// is available or all are already in the meal. Returns true if any swap
  /// happened.
  /// Gap-aware recovery pick (2026-09 meal-quality batch). Two failure
  /// shapes to avoid:
  ///  - the OLD "highest-protein candidate" grab: a 90g Protein Shake to
  ///    close an 8g gap — Pass 4 then trimmed it straight back out and
  ///    the deficit survived unchanged (oscillation);
  ///  - "smallest SINGLE swap that closes the whole gap": when only a
  ///    sledgehammer is sufficient, that rule picks it too — same
  ///    oscillation.
  /// The working rule is GRADUAL CONVERGENCE: take the smallest unused
  /// candidate that still increases protein and let the bounded swap
  /// loop iterate (each iteration upgrades the day's next-lowest item);
  /// a used candidate is taken only when nothing is unused (variety
  /// soft-preference, review rounds 2-3), largest first.
  static double _protStd(Map<String, dynamic> f) =>
      (f['protein_std'] as num?)?.toDouble() ?? 0.0;

  /// Recovery headroom: the slot's protein ceiling for swap-in candidates
  /// (1.5× its target — more room than Pass 4's 1.2× trim threshold, so a
  /// gradual recovery never creates a slot Pass 4 must violently trim).
  static double _recoveryHeadroom(_SlotDef slotDef, DietMealPlan meal) =>
      slotDef.anchorOptional || meal.targetProtein <= 0
          ? double.infinity
          : meal.targetProtein * 1.5;

  Map<String, dynamic>? _pickRecoveryCandidate(
    List<Map<String, dynamic>> candidates, {
    required double currentProtein,
    required int neededProtein,
    required Set<String> usedIds,
    required double maxSlotProtein,
  }) {
    if (candidates.isEmpty) return null;
    final sorted = candidates.toList()
      ..sort((a, b) => _protStd(a).compareTo(_protStd(b)));
    var unused = sorted
        .where((f) => !usedIds.contains(f['id'] as String?))
        .toList();
    // Slot-headroom constraint: never stuff a single slot past
    // [maxSlotProtein] (1.5× its protein target) — a swap that overshoots
    // the slot by 60g only hands Pass 4 an untrimmable problem and nets
    // the daily total BELOW the deficit floor. When no headroom-fitting
    // candidate exists, degrade to unconstrained (never stall recovery).
    final fitting = unused
        .where((f) => _protStd(f) <= maxSlotProtein)
        .toList();
    if (fitting.isNotEmpty) unused = fitting;
    if (unused.isEmpty) {
      final fittingAll =
          sorted.where((f) => _protStd(f) <= maxSlotProtein).toList();
      return fittingAll.isNotEmpty ? fittingAll.last : sorted.last;
    }
    return unused.first;
  }

  /// Recovery anchor-upgrade (2026-09 batch): when a slot's ANCHOR itself
  /// under-delivers (< 60% of the slot protein target — the vegan
  /// breakfast pool's best was Tofu at 8g of a 37.5g target), swap it for
  /// the highest-protein unused anchor-pool candidate within the 1.5x
  /// headroom. The upgrade keeps isAnchor=true so Pass 4 protection and
  /// day-uniqueness bookkeeping stay intact. One upgrade per call
  /// (bounded by the caller's swapTries loop).
  bool _upgradeWeakAnchors(
    List<DietMealPlan> meals,
    String dietPref,
    Set<String> usedIds, {
    required int currentTotal,
    required int dailyCeiling,
  }) {
    for (var mi = 0; mi < meals.length; mi++) {
      final meal = meals[mi];
      final def = _slotDefs[mi];
      if (meal.items.isEmpty || !meal.items.first.isAnchor) continue;
      final anchor = meal.items.first;
      if (meal.targetProtein <= 0) continue;
      // 65% (not 60%): the veg-cut evening anchor (Peanuts 7.8g of a 13g
      // target) sat EXACTLY at 60% and never upgraded — real-DB seeds 4/7
      // missed the floor by <4g as a result.
      if (anchor.protein >= meal.targetProtein * 0.65) continue;

      Map<String, dynamic>? best;
      // Snack slots (optional anchors) carry unlimited slot headroom
      // elsewhere (_recoveryHeadroom) — the upgrade path must agree, else
      // the veg-cut evening slot could never upgrade to Whey 24g.
      final headroom =
          def.anchorOptional ? double.infinity : meal.targetProtein * 1.5;
      for (final name in def.anchorPoolNames) {
        final f = _findFoodByNameIndexed(name);
        if (f == null) continue;
        if (!_passesDiet(f, dietPref)) continue;
        if (_isUpf(f)) continue;
        if ((f['id'] as String?) == anchor.foodId) continue;
        if (usedIds.contains(f['id'] as String?)) continue;
        final p = _protStd(f);
        if (p <= anchor.protein) continue;
        if (p > headroom) continue; // slot headroom
        // DAY-ceiling guard: the upgrade must never push the daily total
        // past 115% of target — an upgraded anchor is isAnchor-protected
        // and Pass 4 cannot trim it back out (the maintain-surplus leak).
        if (currentTotal - anchor.protein + p > dailyCeiling) continue;
        if (best == null || p > _protStd(best)) best = f;
      }
      if (best == null) continue;

      usedIds.remove(anchor.foodId);
      meal.items[0] = _toItem(best, isAnchor: true);
      usedIds.add(best['id'] as String);
      return true;
    }
    return false;
  }

  bool _swapLowestForHigherProtein(
    List<DietMealPlan> meals,
    String dietPref,
    Random rng, {
    required Set<String> usedIds,
    required int neededProtein,
  }) {
    DietMealPlan? targetMeal;
    int? targetIdx;
    int? targetMealIdx;
    int lowestProtein = 1000;

    for (var mi = 0; mi < meals.length; mi++) {
      final m = meals[mi];
      for (var idx = 0; idx < m.items.length; idx++) {
        final item = m.items[idx];
        if (item.isAnchor) continue;
        // Pass 0 quota items are the lowest-protein items by construction —
        // skipping them here is what keeps the mandatory vegetables in the
        // plan through deficit recovery (plan-review round 2, finding 4).
        if (item.isQuotaLocked) continue;
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
    // UPF rows are never swap candidates. Day-uniqueness is a SOFT
    // preference here (Pass 3 is exempt from it — round 2, finding 3 —
    // because the vegan archetype's recovery needs cross-meal freedom):
    // prefer a not-yet-used candidate; fall back to a repeat only when no
    // unique candidate is higher-protein.
    final slotDef = _slotDefs[targetMealIdx];
    final anchorCandidates = <Map<String, dynamic>>[];
    for (final name in slotDef.anchorPoolNames) {
      final f = _findFoodByNameIndexed(name);
      if (f == null) continue;
      if (existingIds.contains(f['id'])) continue;
      if (!_passesDiet(f, dietPref)) continue;
      if (_isUpf(f)) continue;
      if (!_swapRespectsCap(
          targetMeal, current, f['category'] as String? ?? '')) {
        continue;
      }
      final p = (f['protein_std'] as num?)?.toDouble() ?? 0.0;
      if (p > current.protein) anchorCandidates.add(f);
    }
    if (anchorCandidates.isNotEmpty) {
      final pick = _pickRecoveryCandidate(
        anchorCandidates,
        currentProtein: current.protein.toDouble(),
        neededProtein: neededProtein,
        usedIds: usedIds,
        maxSlotProtein: _recoveryHeadroom(slotDef, targetMeal),
      )!;
      targetMeal.items[targetIdx] = _toItem(pick);
      usedIds.add(pick['id'] as String); // register swap-in (B-pass finding 4)
      return true;
    }

    // Strategy B: same-category swap (original behavior). The swap must
    // keep the meal inside the per-category caps — with an anchor already
    // occupying the category's cap, a same-category swap is refused here
    // and Pass 3 falls through to Strategy C.
    final swapMeal = targetMeal;
    final samePool = _foodsByCategory(current.category)
        .where((f) =>
            f['id'] != current.foodId &&
            !existingIds.contains(f['id']) &&
            !_isUpf(f) &&
            _swapRespectsCap(swapMeal, current, current.category) &&
            _passesDiet(f, dietPref) &&
            ((f['protein_std'] as num?)?.toDouble() ?? 0.0) > current.protein)
        .toList();
    if (samePool.isNotEmpty) {
      final pick = _pickRecoveryCandidate(
        samePool,
        currentProtein: current.protein.toDouble(),
        neededProtein: neededProtein,
        usedIds: usedIds,
        maxSlotProtein: _recoveryHeadroom(slotDef, targetMeal),
      )!;
      targetMeal.items[targetIdx] = _toItem(pick);
      usedIds.add(pick['id'] as String); // register swap-in (B-pass finding 4)
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
      if (!_swapRespectsCap(targetMeal, current, cat)) continue;
      crossPool.addAll(_foodsByCategory(cat).where((f) =>
          !existingIds.contains(f['id']) &&
          !_isUpf(f) &&
          _passesDiet(f, dietPref) &&
          ((f['protein_std'] as num?)?.toDouble() ?? 0.0) > current.protein));
    }
    if (crossPool.isEmpty) return false;
    final pick = _pickRecoveryCandidate(
      crossPool,
      currentProtein: current.protein.toDouble(),
      neededProtein: neededProtein,
      usedIds: usedIds,
        maxSlotProtein: _recoveryHeadroom(slotDef, targetMeal),
      )!;
      targetMeal.items[targetIdx] = _toItem(pick);
      // Register the swap-in (B-pass finding 4): recovery additions become
      // "used" so later prefer-unused picks look elsewhere. The swapped-OUT
      // id is deliberately left burned — re-adding it is the conservative
      // direction for variety.
      usedIds.add(pick['id'] as String);
      return true;
    }

  /// Walks every meal, finds the highest-protein item that's inflating an
  /// over-target meal, and swaps it for a lower-protein filler in the same
  /// calorie band (±20%).
  ///
  /// Anchor protection: REQUIRED anchors (lunch/dinner/breakfast — slots
  /// where `anchorOptional == false`) are protected from swap. OPTIONAL
  /// anchors (snack slots — `anchorOptional == true`) are eligible because
  /// they are by-design optional and dropping them is the only way to
  /// reach the 115% ceiling when the snack anchor pool itself is
  /// disproportionately protein-dense (e.g. Protein Shake at 90g/serving).
  /// Snack-anchor swaps must still find a lower-protein filler from the
  /// slot's `fillerCategories` (NOT the anchor pool), so the slot
  /// effectively becomes a fruit/nut/beverage snack rather than a protein
  /// shot.
  ///
  /// "Over-target meal" = `meal.totalProtein > meal.targetProtein * 1.2`.
  /// Replacement requirements: protein strictly less than the item being
  /// replaced, calories within ±20% of replaced item, diet-pref compatible,
  /// different foodId, and not already in the meal.
  ///
  /// Returns true if any swap happened.
  bool _swapHighestForLowerProtein(
    List<DietMealPlan> meals,
    String dietPref,
    Random rng, {
    required Set<String> usedIds,
    int softFloor = 0,
    required int dailyFloor,
    int currentTotal = 0,
  }) {
    // Iterate meals from highest-over to lowest-over so we trim where the
    // surplus is most concentrated first. DAY-LEVEL FALLBACK (2026-09
    // batch): when the DAY total busts the ceiling, remaining non-over
    // slots are APPENDED after the over-shooters — the over slots may hold
    // nothing trimmable (anchors + quota items only) while a non-over slot
    // does. The replacement rules below still require a protein REDUCTION
    // landing above the daily floor, so appending cannot over-trim.
    final overShooters = <int>[];
    for (var mi = 0; mi < meals.length; mi++) {
      final m = meals[mi];
      if (m.targetProtein <= 0) continue;
      if (m.totalProtein > (m.targetProtein * 1.2).round()) {
        overShooters.add(mi);
      }
    }
    for (var mi = 0; mi < meals.length; mi++) {
      if (meals[mi].targetProtein > 0 && !overShooters.contains(mi)) {
        overShooters.add(mi);
      }
    }
    overShooters.sort((a, b) {
      final da = meals[a].totalProtein - meals[a].targetProtein;
      final db = meals[b].totalProtein - meals[b].targetProtein;
      return db.compareTo(da);
    });

    for (final mi in overShooters) {
      final meal = meals[mi];
      final def = _slotDefs[mi];
      // Required anchors are protected; optional-anchor slots (snacks)
      // allow anchor swap.
      final canSwapAnchor = def.anchorOptional;

      // Find the highest-protein item in this meal that's eligible for swap.
      // Quota items are never eligible (zero-cost hardening, round 3 Q4:
      // quota veg is never the highest-protein item while an anchor exists,
      // but the guard makes the invariant explicit and survives future
      // slot-def changes).
      int? targetIdx;
      int highestProtein = -1;
      for (var idx = 0; idx < meal.items.length; idx++) {
        final item = meal.items[idx];
        if (item.isAnchor && !canSwapAnchor) continue;
        if (item.isQuotaLocked) continue;
        if (item.protein > highestProtein) {
          highestProtein = item.protein;
          targetIdx = idx;
        }
      }
      if (targetIdx == null) continue;

      final current = meal.items[targetIdx];
      final existingIds = meal.items.map((it) => it.foodId).toSet();
      final calLow = (current.calories * 0.8).floor();
      final calHigh = (current.calories * 1.2).ceil();

      // Tier 1 — strict: lower-protein filler within ±20% calorie band.
      // Tier 2 — relaxed: any lower-protein filler in slot's filler
      //   categories (calorie band dropped). Pass 2 already filled the
      //   slot's calorie target; Pass 4 only trims protein, calorie
      //   balance is best-effort. Used when the strict in-band pool is
      //   empty (typical for snack slots whose only in-band option is
      //   the protein-dense anchor itself).
      final inBand = <Map<String, dynamic>>[];
      final relaxed = <Map<String, dynamic>>[];
      for (final cat in def.fillerCategories) {
        if (!_swapRespectsCap(meal, current, cat)) continue;
        for (final f in _foodsByCategory(cat)) {
          final id = f['id'] as String?;
          if (id == null || id == current.foodId) continue;
          if (existingIds.contains(id)) continue;
          if (_isUpf(f)) continue;
          if (!_passesDiet(f, dietPref)) continue;

          // Compute per-serving cal + protein (mirror _toItem math).
          final servingG =
              (f['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
          final factor = servingG / 100.0;
          final fCal =
              (((f['calories_per_100g'] as num?)?.toDouble() ?? 0.0) * factor)
                  .round();
          final fProt =
              (((f['protein_per_100g'] as num?)?.toDouble() ?? 0.0) * factor)
                  .round();

          if (fProt >= current.protein) continue; // must REDUCE protein
          if (fCal >= calLow && fCal <= calHigh) {
            inBand.add(f);
          } else {
            relaxed.add(f);
          }
        }
      }

      final candidates = inBand.isNotEmpty ? inBand : relaxed;

      if (candidates.isNotEmpty) {
        int protOf(Map<String, dynamic> f) =>
            (((f['protein_per_100g'] as num?)?.toDouble() ?? 0.0) *
                    (((f['standard_serving_g'] as num?)?.toDouble() ??
                            100.0) /
                        100.0))
                .round();
        bool landsAbove(Map<String, dynamic> f, int floor) =>
            currentTotal - current.protein + protOf(f) >= floor;

        // Tier 1: gentlest trim — the LOWEST-protein unused candidate that
        // keeps the daily total above the soft floor (105%).
        // Tier 2: any candidate (unused preferred) that still lands at or
        // above the daily deficit floor (95%) — when every swap
        // under-corrects the soft floor, staying above the deficit floor
        // still beats busting the daily ceiling.
        // Tier 3: highest-protein candidate overall (smallest cut) —
        // better a few grams over ceiling than under floor.
        final sortedUnused = candidates
            .where((f) => !usedIds.contains(f['id'] as String?))
            .toList()
          ..sort((a, b) => protOf(a).compareTo(protOf(b)));
        final sortedAll = candidates.toList()
          ..sort((a, b) => protOf(a).compareTo(protOf(b)));

        Map<String, dynamic>? best;
        best = sortedUnused.cast<Map<String, dynamic>?>().firstWhere(
              (f) => landsAbove(f!, softFloor),
              orElse: () => null,
            );
        best ??= sortedUnused.cast<Map<String, dynamic>?>().firstWhere(
              (f) => landsAbove(f!, dailyFloor),
              orElse: () => null,
            );
        best ??= sortedAll.cast<Map<String, dynamic>?>().firstWhere(
              (f) => landsAbove(f!, dailyFloor),
              orElse: () => null,
            );
        best ??= sortedAll.last;
        meal.items[targetIdx] = _toItem(best);
        usedIds.add(best['id'] as String); // register swap-in (B-pass finding 4)
        return true;
      }

      // Fallback: if the over-protein item is an optional-slot anchor
      // (snacks) and no calorie-band-compatible filler exists in the
      // slot's filler categories — typical for snack slots whose anchors
      // are protein-dense beverages with no fruit/nut equivalent in the
      // ±20% calorie band — REMOVE the item entirely BUT only if the
      // resulting daily total stays above the soft floor. Otherwise we
      // over-correct and break the deficit guard.
      if (canSwapAnchor && current.isAnchor) {
        if (softFloor > 0 && (currentTotal - current.protein) < softFloor) {
          continue; // would over-correct; try next over-shooting meal
        }
        meal.items.removeAt(targetIdx);
        return true;
      }
    }
    return false;
  }

  DietPlanFoodItem? _highestProteinFallback(String dietPref) {
    Map<String, dynamic>? best;
    double bestP = 0.0;
    // Use the already-snapshotted list (_ensureIndices called before generate).
    for (final f in _allFoodsCache ?? _foodRepo.getAll()) {
      if (_isUpf(f)) continue; // "never UPF" holds on the fallback path too (round 2, finding 7)
      if (!_passesDiet(f, dietPref)) continue;
      final p = (f['protein_std'] as num?)?.toDouble() ?? 0.0;
      if (p > bestP) {
        bestP = p;
        best = f;
      }
    }
    return best == null ? null : _toItem(best, isAnchor: true);
  }

  /// Pass 5: finds the lowest-fiber staple across all meals (skipping
  /// anchors and quota-locked items) and swaps it for a higher-fiber,
  /// UPF-clean, diet-compatible staple in the same ±20% calorie band.
  /// Day-uniqueness is a soft preference. Returns true if a swap happened;
  /// bounded-tries caller + empty-candidate no-op mirror the Pass 3/4
  /// pattern so this can never loop (round 2, finding 6).
  bool _swapLowestFiberStaple(
    List<DietMealPlan> meals,
    String dietPref,
    Random rng,
    Set<String> usedIds,
  ) {
    DietMealPlan? targetMeal;
    int? targetIdx;
    int lowestFiber = 1 << 30;

    for (final m in meals) {
      for (var idx = 0; idx < m.items.length; idx++) {
        final item = m.items[idx];
        if (item.isAnchor || item.isQuotaLocked) continue;
        if (item.category != 'staples') continue;
        if (item.fiber < lowestFiber) {
          lowestFiber = item.fiber;
          targetMeal = m;
          targetIdx = idx;
        }
      }
    }
    if (targetMeal == null || targetIdx == null) return false;

    final current = targetMeal.items[targetIdx];
    final existingIds = targetMeal.items.map((it) => it.foodId).toSet();
    final calLow = (current.calories * 0.8).floor();
    final calHigh = (current.calories * 1.2).ceil();

    final candidates = <Map<String, dynamic>>[];
    for (final f in _foodsByCategory('staples')) {
      final id = f['id'] as String?;
      if (id == null || id == current.foodId) continue;
      if (existingIds.contains(id)) continue;
      if (_isUpf(f)) continue;
      if (!_passesDiet(f, dietPref)) continue;

      final servingG = (f['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
      final factor = servingG / 100.0;
      final fCal = (((f['calories_per_100g'] as num?)?.toDouble() ?? 0.0) * factor).round();
      final fFiber = (((f['fiber_per_100g'] as num?)?.toDouble() ?? 0.0) * factor).round();
      if (fFiber <= current.fiber) continue; // must RAISE fiber
      if (fCal >= calLow && fCal <= calHigh) candidates.add(f);
    }
    if (candidates.isEmpty) return false;

    // Highest fiber wins; prefer not-yet-used candidates.
    candidates.sort((a, b) {
      final aF = ((a['fiber_per_100g'] as num?)?.toDouble() ?? 0.0);
      final bF = ((b['fiber_per_100g'] as num?)?.toDouble() ?? 0.0);
      return bF.compareTo(aF);
    });
    Map<String, dynamic>? pick;
    for (final f in candidates) {
      if (!usedIds.contains(f['id'] as String?)) {
        pick = f;
        break;
      }
    }
    pick ??= candidates.first;
    targetMeal.items[targetIdx] = _toItem(pick);
    usedIds.add(pick['id'] as String); // register swap-in (B-pass finding 4)
    return true;
  }

  bool _passesDiet(Map<String, dynamic> food, String dietPref) => passesDiet(food, dietPref);

  /// Public so the manual swap UI (diet_plan_screen._swapItem) applies the
  /// SAME diet-preference rule as generation — plan-review round 2, finding 5:
  /// a veg user could be offered Chicken Breast in the swap sheet.
  static bool passesDiet(Map<String, dynamic> food, String dietPref) {
    final name = food['name'] as String? ?? '';
    final pref = dietPref.toLowerCase();
    if (pref == 'vegan') {
      if (_nonVegNames.contains(name)) return false;
      // The DB's own is_vegan field is AUTHORITATIVE on the 1431-row real
      // data (all dals/pulses vegan=true; every dairy/paneer/whey row
      // vegan=false). The name blocklists below were built against the
      // curated fixture and MISSED real rows ('1% Milk', 'Greek Yogurt
      // Plain (2%)', 'Jaouda Perly', 'Nestle Milkybar Moosha' all leaked
      // into real vegan plans — caught by the real-DB vegan-purity test).
      // Blocklists remain as the fallback for untagged rows only.
      if (food['is_vegan'] == false) return false;
      if (_dairyOrEggNames.contains(name)) return false;
      // Plant-based pulses, grains, legumes, nuts, fruits, vegetables are
      // all vegan-eligible by default. Only honor `is_vegan == true` as a
      // positive signal (already implied by passing the checks above).
      return true;
    }
    if (pref == 'veg' || pref == 'vegetarian') {
      // is_veg authoritative on real data (B-pass finding 2 — the 9-name
      // blocklist leaked 187 is_veg=false rows, 117 generator-reachable:
      // 'Anda Paratha' into staples fillers, chicken variants via
      // Strategy C / _highestProteinFallback). Blocklist remains as the
      // untagged-row fallback.
      if (food['is_veg'] == false) return false;
      return !_nonVegNames.contains(name);
    }
    return true; // non-veg: everything passes
  }

  // ── Generation-time quality filters (2026-09 meal-quality batch) ──
  //
  // Missing-field semantics are deliberate (plan-review round 1, finding 5):
  // absent `is_ultra_processed` ⇒ false, absent/empty `meal_fit` ⇒ matches
  // every slot. This keeps untagged v2 boxes and the test fixture generating
  // safely, and keeps generation alive if a re-seed throws partway.

  static bool _isUpf(Map<String, dynamic> food) =>
      (food['is_ultra_processed'] as bool?) ?? false;

  static bool _matchesMeal(Map<String, dynamic> food, String slotKey) {
    final fit = food['meal_fit'];
    // ABSENT field (v2 box mid-reseed / untagged fixture row) => matches
    // every slot, so untagged boxes generate exactly like pre-batch.
    // PRESENT-but-EMPTY list is a deliberate founder/editorial choice =
    // NEVER generated (e.g. the five alcohol rows cleared in the HTML
    // review). A non-empty list must contain the slot.
    if (fit == null) return true;
    return (fit as List).contains(slotKey);
  }

  DietPlanFoodItem _toItem(
    Map<String, dynamic> f, {
    bool isAnchor = false,
    bool isQuotaLocked = false,
  }) {
    final servingG =
        (f['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
    final factor = servingG / 100.0;
    final cal = ((f['calories_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final prot = ((f['protein_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final carb = ((f['carbs_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final fat = ((f['fat_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    final fiber = ((f['fiber_per_100g'] as num?)?.toDouble() ?? 0.0) * factor;
    return DietPlanFoodItem(
      foodId: f['id'] as String? ?? '',
      name: f['name'] as String? ?? 'Unknown',
      servingDesc: f['standard_serving_desc'] as String? ?? '100g',
      servingG: servingG,
      calories: cal.round(),
      protein: prot.round(),
      carbs: carb.round(),
      fat: fat.round(),
      fiber: fiber.round(),
      category: f['category'] as String? ?? 'unknown',
      isAnchor: isAnchor,
      isQuotaLocked: isQuotaLocked,
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
