# APK Test #3 — Plan C — Diet Plan Anchor + AI Snapshot Expansion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the diet plan protein deficit (Obs 2 — anchor-protein-per-meal algorithm hitting ≥95% of target) and expand the AI coach snapshot with `meals_today` + `nutrition_trend_7d` (Q6.3) so the coach can reference what the user actually ate today and across the last week.

**Architecture:** Two independent additions sharing only the nutrition domain. (1) The existing diet plan generator — currently inlined in `diet_plan_screen.dart:43-153` — gets extracted into a new `DietPlanGenerator` service and rewritten as a 3-pass algorithm: Pass 1 picks an anchor protein per slot (filtered by `diet_preference`), Pass 2 fills carb staples + fat sources to hit the calorie band, Pass 3 verifies daily protein ≥95% of target and swaps for higher-density alternatives if short. (2) `AiCoachRepository.buildAiContext()` gains two new keys, fed by new `_getMealsToday()` and `_getNutritionTrend7d()` helpers that read directly from `nutritionBox` (Hive-first, no network). `_compactContext` trim order in `ai_service.dart` learns about the new keys so they drop early under pressure.

**Tech Stack:** Flutter (Dart 3.4+), Riverpod for state, Hive offline storage for `nutritionBox` + `foodBox`, no Edge Function changes (snapshot lives client-side, server reads it as JSON-stringified payload).

**Spec:** `docs/superpowers/specs/2026-04-26-apk-test-3-batch-design.md` — sections "🟢 Diet Plan Protein Anchor (Obs 2)" and "🟫 AI Snapshot Expansion (Q6.3)".

---

## File Structure

| File | Responsibility | New / Modified |
|---|---|---|
| `lib/features/nutrition/services/diet_plan_generator.dart` | Pure-Dart, testable diet plan generator. Three-pass algorithm: anchor protein → carbs/fats → protein-deficit recovery. Reads `FoodRepository.instance.getByCategory()`. Filters anchors by `diet_preference` (veg / vegan / non-veg). Returns `List<DietMealPlan>` (public model; replaces private `_MealPlan` in diet_plan_screen). | New |
| `lib/features/nutrition/screens/diet_plan_screen.dart` | Drop the inline `_generateMeal` / `_generateFreshPlan` (~110 lines, lines 43-153). Replace with a single call into `DietPlanGenerator.instance.generate(...)`. Keep the swap UI, save UI, PDF export untouched. Remove now-private `_MealPlan` / `_PlanFoodItem` classes, switch to public ones from the service. | Modified |
| `lib/features/ai_coach/repositories/ai_coach_repository.dart` (lines 41-89, 766-816) | Add `meals_today` + `nutrition_trend_7d` keys to `buildAiContext()`. Add `_getMealsToday()` (groups today's `nlog_*` rows by `meal_type`) and `_getNutritionTrend7d()` (iterates last 7 days, sums totals per day). | Modified |
| `lib/core/services/ai_service.dart` (lines 106-144) | Update `_compactContext` `trimSteps` list to include `meals_today` and `nutrition_trend_7d` after `step_history_7d`. They drop in the same priority lane (least load-bearing first). | Modified |
| `test/nutrition/diet_plan_generator_test.dart` | Four-archetype test: low-cal cut (1500 kcal / 130 g / vegetarian), balanced maintain (2400 / 130 / non-veg), surplus build (3000 / 200 / non-veg), vegan high-protein (2200 / 150 / vegan). Each asserts (a) total protein ≥ 95% of target, (b) every meal slot has an anchor from the appropriate set, (c) anchor honors `diet_preference`. | New |
| `test/ai_coach/meals_today_snapshot_test.dart` | Builds a fake `nutritionBox` via Hive's in-memory init, writes 3 today rows (breakfast oats + lunch chicken + snack whey), calls `AiCoachRepository._getMealsToday()` via a public test seam, asserts the grouped shape. | New |
| `test/ai_coach/nutrition_trend_7d_snapshot_test.dart` | Builds a `nutritionBox` with rows spanning 7 days (some empty days), calls `_getNutritionTrend7d()`, asserts 7 entries returned in newest-first order with zero-fill on empty days. | New |
| `test/ai_coach/snapshot_compaction_test.dart` | Builds a realistic full snapshot including `meals_today` + `nutrition_trend_7d` for a typical user (3 meals today, 7 days of trend), asserts JSON-encoded byte size stays ≤ 9500 bytes WITHOUT trimming. Then padded test asserts both new keys drop in the right order under pressure. | New |

---

## Task 1: Scaffold `DietPlanGenerator` service skeleton + public models

**Files:**
- Create: `lib/features/nutrition/services/diet_plan_generator.dart`

This task only stands up the file with public models + a no-op `generate(...)` so subsequent TDD tasks have a target to import. Algorithm content lands in Task 3.

- [ ] **Step 1: Create the service file with public models and a stub `generate` method**

```dart
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

  /// Generates a 5-slot daily diet plan honoring the anchor-protein-per-meal
  /// rule. Returns [Breakfast, Mid-Morning, Lunch, Evening, Dinner].
  List<DietMealPlan> generate(DietPlanInputs inputs) {
    // Stub — populated in Task 3.
    return const [];
  }
}
```

- [ ] **Step 2: Verify the file compiles**

```bash
flutter analyze lib/features/nutrition/services/diet_plan_generator.dart
```
Expected: zero errors. (Warnings about unused fields like `_foodRepo` are fine for now — Task 3 will use them.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/nutrition/services/diet_plan_generator.dart
git commit -m "feat(nutrition): scaffold DietPlanGenerator service + public models

Stand up lib/features/nutrition/services/diet_plan_generator.dart with
DietMealPlan / DietPlanFoodItem / DietPlanInputs public models and a
stub generate() method. The anchor-protein-per-meal algorithm lands in
the next commit.

Service singleton wraps FoodRepository.instance for production; a
forTest factory accepts an injected repo so unit tests don't need Hive.

Plan C / Obs 2 (APK Test #3, 2026-04-26)."
```

---

## Task 2: Write failing unit test for the anchor-protein-per-meal algorithm

**Files:**
- Create: `test/nutrition/diet_plan_generator_test.dart`

TDD: write the four-archetype test against the stub from Task 1, watch it fail, then implement in Task 3.

- [ ] **Step 1: Create the test file**

```dart
// test/nutrition/diet_plan_generator_test.dart
//
// Four-archetype validation that the anchor-protein-per-meal algorithm
// hits >= 95% of the daily protein target across realistic user shapes.
// Each archetype also asserts that every slot has an anchor protein from
// the appropriate set and that diet_preference is honored.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

/// Fake FoodRepository that returns a hand-curated subset of the bundled
/// food_database.json so tests don't need Hive.
class _FakeFoodRepo implements FoodRepository {
  final List<Map<String, dynamic>> _foods;
  _FakeFoodRepo(this._foods);

  @override
  List<Map<String, dynamic>> getAll() => _foods;

  @override
  List<Map<String, dynamic>> getByCategory(String category) => _foods
      .where((f) =>
          (f['category'] as String?)?.toLowerCase() == category.toLowerCase())
      .toList();

  @override
  Map<String, dynamic>? getById(String id) =>
      _foods.firstWhere((f) => f['id'] == id, orElse: () => <String, dynamic>{});

  @override
  List<String> getCategories() =>
      _foods.map((f) => f['category'] as String).toSet().toList();

  @override
  List<Map<String, dynamic>> search(String query, {int limit = 50}) =>
      _foods.where((f) => (f['name'] as String).contains(query)).take(limit).toList();

  @override
  List<Map<String, dynamic>> getIndianFoods({int limit = 50}) =>
      _foods.where((f) => f['is_indian'] == true).take(limit).toList();
}

/// Builds a small but realistic food universe. Mirrors actual rows from
/// assets/data/food_database.json (verified 2026-04-26).
List<Map<String, dynamic>> _seedFoods() => [
      // staples
      _f('F0001', 'White Rice (cooked)', 'staples', 130, 2.7, 28, 0.3, 158, '1 cup'),
      _f('F0002', 'Brown Rice (cooked)', 'staples', 112, 2.6, 24, 0.9, 195, '1 cup'),
      _f('F0003', 'Roti (Whole Wheat)', 'staples', 297, 9.8, 59, 3.7, 40, '1 roti'),
      _f('F0007', 'Poha (Flattened Rice)', 'staples', 130, 2.6, 27, 1.5, 180, '1 plate'),
      // pulses
      _f('F0011', 'Toor Dal (cooked)', 'pulses', 116, 7.5, 20, 0.4, 200, '1 bowl'),
      _f('F0014', 'Rajma (cooked)', 'pulses', 127, 8.7, 23, 0.5, 200, '1 bowl'),
      _f('F0016', 'Masoor Dal (cooked)', 'pulses', 116, 9.0, 20, 0.4, 200, '1 bowl'),
      _f('F0017', 'Sprouts (Mixed)', 'pulses', 70, 7.0, 12, 0.5, 100, '1 cup'),
      _f('F0018', 'Soybean (boiled)', 'pulses', 173, 17.0, 10, 9.0, 100, '1 cup'),
      // protein (non-veg + paneer + tofu)
      _f('F0021', 'Chicken Breast (grilled)', 'protein', 165, 31.0, 0, 3.6, 100, '100g', isVeg: false),
      _f('F0023', 'Egg (Whole, boiled)', 'protein', 130, 13.0, 1.1, 8.7, 50, '1 egg', isVeg: true),
      _f('F0025', 'Paneer', 'protein', 265, 18.0, 1.2, 21.0, 100, '100g', isVeg: true),
      _f('F0026', 'Fish Curry', 'protein', 160, 16.0, 6, 8, 200, '1 bowl', isVeg: false),
      _f('F0027', 'Mutton Curry', 'protein', 235, 18.0, 4, 17, 200, '1 bowl', isVeg: false),
      _f('F0028', 'Tandoori Chicken', 'protein', 175, 25.0, 1, 7, 120, '1 leg piece', isVeg: false),
      _f('F0029', 'Tofu', 'protein', 76, 8.0, 1.9, 4.8, 100, '100g', isVeg: true, isVegan: true),
      // supplements
      _f('F0031', 'Whey Protein (scoop)', 'supplements', 380, 75.0, 8, 4, 32, '1 scoop', isVeg: true),
      // dairy
      _f('F0032', 'Curd (Dahi)', 'dairy', 60, 3.5, 4.7, 3.3, 200, '1 cup', isVeg: true),
      _f('F0033', 'Greek Yogurt', 'dairy', 85, 9.0, 5, 4, 170, '1 cup', isVeg: true),
      _f('F0034', 'Milk (Toned)', 'dairy', 56, 3.1, 4.7, 3.0, 250, '1 glass', isVeg: true),
      // nuts_seeds
      _f('F0050', 'Almonds', 'nuts_seeds', 580, 21.0, 22, 50, 14, '10 almonds', isVeg: true, isVegan: true),
      _f('F0051', 'Peanuts (Roasted)', 'nuts_seeds', 580, 26.0, 16, 49, 30, '1 handful', isVeg: true, isVegan: true),
      _f('F0056', 'Peanut Butter', 'nuts_seeds', 590, 25.0, 20, 50, 16, '1 tbsp', isVeg: true, isVegan: true),
      // beverages
      _f('F0046', 'Protein Shake (Whey + Milk)', 'beverages', 100, 30.0, 7, 2, 300, '1 glass', isVeg: true),
      // fruits
      _f('F0040', 'Banana', 'fruits', 89, 1.1, 23, 0.3, 118, '1 medium', isVeg: true, isVegan: true),
      _f('F0041', 'Apple', 'fruits', 52, 0.3, 14, 0.2, 180, '1 medium', isVeg: true, isVegan: true),
      // vegetables
      _f('F0061', 'Mixed Sabzi', 'vegetables', 80, 3.0, 10, 4, 150, '1 bowl', isVeg: true, isVegan: true),
    ];

Map<String, dynamic> _f(String id, String name, String cat, num cal, num prot,
    num carb, num fat, num servingG, String servingDesc,
    {bool isVeg = true, bool isVegan = false}) {
  final factor = servingG / 100.0;
  return {
    'id': id,
    'name': name,
    'category': cat,
    'calories_per_100g': cal,
    'protein_per_100g': prot,
    'carbs_per_100g': carb,
    'fat_per_100g': fat,
    'standard_serving_g': servingG,
    'standard_serving_desc': servingDesc,
    'calories_std': (cal * factor).toDouble(),
    'protein_std': (prot * factor).toDouble(),
    'carbs_std': (carb * factor).toDouble(),
    'fat_std': (fat * factor).toDouble(),
    'is_indian': true,
    'is_veg': isVeg,
    'is_vegan': isVegan,
  };
}

const _breakfastAnchors = {
  'Egg (Whole, boiled)',
  'Whey Protein (scoop)',
  'Greek Yogurt',
  'Paneer',
  'Sprouts (Mixed)',
  'Tofu',
  'Protein Shake (Whey + Milk)',
};
const _mainAnchors = {
  'Chicken Breast (grilled)',
  'Mutton Curry',
  'Fish Curry',
  'Tandoori Chicken',
  'Paneer',
  'Toor Dal (cooked)',
  'Rajma (cooked)',
  'Masoor Dal (cooked)',
  'Soybean (boiled)',
  'Tofu',
};
const _snackAnchors = {
  'Whey Protein (scoop)',
  'Almonds',
  'Peanuts (Roasted)',
  'Peanut Butter',
  'Sprouts (Mixed)',
  'Greek Yogurt',
  'Protein Shake (Whey + Milk)',
};

void main() {
  final repo = _FakeFoodRepo(_seedFoods());
  final gen = DietPlanGenerator.forTest(repo);

  void runArchetype({
    required String label,
    required int calories,
    required int protein,
    required String diet,
  }) {
    test('$label: protein hits >=95% of target with anchor in every meal', () {
      final plan = gen.generate(DietPlanInputs(
        calorieTarget: calories,
        proteinTarget: protein,
        dietPreference: diet,
        seed: 42,
      ));

      // (a) total protein >= 95% of target
      final totalProtein = plan.fold<int>(0, (s, m) => s + m.totalProtein);
      expect(
        totalProtein,
        greaterThanOrEqualTo((protein * 0.95).floor()),
        reason: '$label: total protein ${totalProtein}g must hit >= 95% of '
            '${protein}g target',
      );

      // (b) every NON-snack slot has at least one anchor item; snack is optional
      for (final meal in plan) {
        final isSnack = meal.slotKey == 'mid_morning' || meal.slotKey == 'evening';
        final anchors = isSnack
            ? _snackAnchors
            : (meal.slotKey == 'breakfast' ? _breakfastAnchors : _mainAnchors);
        final hasAnchor =
            meal.items.any((i) => anchors.contains(i.name) && i.isAnchor);
        if (!isSnack) {
          expect(hasAnchor, isTrue,
              reason:
                  '$label / ${meal.slotKey}: must contain an anchor protein '
                  'from $anchors. Got: ${meal.items.map((i) => i.name).toList()}');
        }
      }

      // (c) diet_preference honored — no non-veg in veg/vegan plans
      if (diet == 'veg' || diet == 'vegan') {
        for (final meal in plan) {
          for (final item in meal.items) {
            expect(
              {'Chicken Breast (grilled)', 'Mutton Curry', 'Fish Curry',
                  'Tandoori Chicken'}.contains(item.name),
              isFalse,
              reason: '$label ($diet): non-veg item ${item.name} leaked into '
                  '${meal.slotKey}',
            );
          }
        }
      }
      if (diet == 'vegan') {
        for (final meal in plan) {
          for (final item in meal.items) {
            expect(
              {'Egg (Whole, boiled)', 'Paneer', 'Greek Yogurt', 'Curd (Dahi)',
                  'Milk (Toned)', 'Whey Protein (scoop)',
                  'Protein Shake (Whey + Milk)'}.contains(item.name),
              isFalse,
              reason:
                  '$label (vegan): dairy/egg item ${item.name} leaked into '
                  '${meal.slotKey}',
            );
          }
        }
      }
    });
  }

  runArchetype(
    label: 'low-cal cut (1500 / 130 / vegetarian)',
    calories: 1500,
    protein: 130,
    diet: 'veg',
  );
  runArchetype(
    label: 'balanced maintain (2400 / 130 / non-veg)',
    calories: 2400,
    protein: 130,
    diet: 'non-veg',
  );
  runArchetype(
    label: 'surplus build (3000 / 200 / non-veg)',
    calories: 3000,
    protein: 200,
    diet: 'non-veg',
  );
  runArchetype(
    label: 'vegan high-protein (2200 / 150 / vegan)',
    calories: 2200,
    protein: 150,
    diet: 'vegan',
  );
}
```

- [ ] **Step 2: Run the test, expect failures**

```bash
flutter test test/nutrition/diet_plan_generator_test.dart
```

Expected: all 4 cases FAIL. The stub `generate()` returns `[]`, so `totalProtein = 0` and the anchor-presence check trips immediately.

- [ ] **Step 3: Commit the failing test**

```bash
git add test/nutrition/diet_plan_generator_test.dart
git commit -m "test(nutrition): four-archetype diet plan generator contract

TDD red phase. Asserts:
  (a) total protein >= 95% of daily target,
  (b) every breakfast/lunch/dinner slot has an anchor protein from the
      appropriate set,
  (c) diet_preference is honored (no non-veg in veg/vegan, no dairy/egg
      in vegan).

Four archetypes:
  - low-cal cut       1500 kcal / 130 g / vegetarian
  - balanced maintain 2400 kcal / 130 g / non-veg
  - surplus build     3000 kcal / 200 g / non-veg
  - vegan high-prot.  2200 kcal / 150 g / vegan

Currently RED — DietPlanGenerator.generate() returns [] (stub). Algorithm
implementation lands in the next commit (Task 3).

Plan C / Obs 2 (APK Test #3, 2026-04-26)."
```

---

## Task 3: Implement the anchor-protein-per-meal algorithm

**Files:**
- Modify: `lib/features/nutrition/services/diet_plan_generator.dart`

- [ ] **Step 1: Replace the stub `generate(...)` with the three-pass algorithm**

In `lib/features/nutrition/services/diet_plan_generator.dart`, replace the stub method body and add private helpers. The full revised file body (after the public model classes, no other changes) is:

```dart
class DietPlanGenerator {
  DietPlanGenerator._({FoodRepository? foodRepo})
      : _foodRepo = foodRepo ?? FoodRepository.instance;

  static final DietPlanGenerator instance = DietPlanGenerator._();

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
        final filler = _pickFiller(def, inputs.dietPreference, rng,
            avoidIds: meal.items.map((i) => i.foodId).toSet());
        if (filler == null) break;
        meal.items.add(filler);
        remainingCals = meal.targetCalories - meal.totalCalories;
      }
    }

    // ── PASS 3: protein-deficit recovery ──────────────────────────
    final deficit95 = (inputs.proteinTarget * 0.95).floor();
    var totalProtein = meals.fold<int>(0, (s, m) => s + m.totalProtein);
    var swapTries = 6;

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
  /// swaps it for a same-category food with higher protein_std. Returns
  /// true if any swap happened.
  bool _swapLowestForHigherProtein(
    List<DietMealPlan> meals,
    String dietPref,
    Random rng,
  ) {
    DietMealPlan? targetMeal;
    int? targetIdx;
    int lowestProtein = 1000;

    for (final m in meals) {
      for (var idx = 0; idx < m.items.length; idx++) {
        final item = m.items[idx];
        if (item.isAnchor) continue;
        if (item.protein < lowestProtein) {
          lowestProtein = item.protein;
          targetMeal = m;
          targetIdx = idx;
        }
      }
    }
    if (targetMeal == null || targetIdx == null) return false;

    final current = targetMeal.items[targetIdx];
    final pool = _foodRepo
        .getByCategory(current.category)
        .where((f) =>
            f['id'] != current.foodId &&
            _passesDiet(f, dietPref) &&
            ((f['protein_std'] as num?)?.toDouble() ?? 0.0) > current.protein)
        .toList();
    if (pool.isEmpty) return false;
    pool.sort((a, b) {
      final aP = (a['protein_std'] as num?)?.toDouble() ?? 0.0;
      final bP = (b['protein_std'] as num?)?.toDouble() ?? 0.0;
      return bP.compareTo(aP);
    });
    targetMeal.items[targetIdx] = _toItem(pool.first);
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
      // Honor explicit field if present
      final isVegan = food['is_vegan'];
      if (isVegan == false) return false;
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
```

- [ ] **Step 2: Run the test suite, expect green**

```bash
flutter test test/nutrition/diet_plan_generator_test.dart
```

Expected: all 4 archetypes PASS. If the vegan case fails on protein, double-check Whey is correctly excluded and Soybean / Tofu / Almonds anchors are pulling their weight.

- [ ] **Step 3: Sanity-check protein distribution per archetype manually**

Add a one-shot debug helper at the bottom of the test file (under `// ignore: unused_element` or wrap it in a `test` block with `, skip: true`) that prints `total_protein / target` for each archetype. Confirm visually that the surplus-build case clears 200 g comfortably (Whey + Chicken + Mutton + Tofu all hit easily).

```bash
flutter test test/nutrition/diet_plan_generator_test.dart --reporter expanded
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/nutrition/services/diet_plan_generator.dart
git commit -m "feat(nutrition): anchor-protein-per-meal diet plan algorithm

Implements the three-pass algorithm spec'd in APK Test #3 / Obs 2:
  Pass 1 — pick an anchor protein per slot (filtered by diet_preference).
  Pass 2 — fill carb staples + fat sources to hit each slot's calorie band.
  Pass 3 — verify daily total protein >= 95% of target; swap lowest-protein
           non-anchor items for higher-density alternatives in the same
           category until the deficit closes (max 6 swaps).

Indian-first DB skews carb-heavy (138 g target → 94 g delivered before
the rule). Anchor sets:
  Breakfast: Egg / Whey / Greek Yogurt / Paneer / Sprouts / Tofu (>= 20 g)
  Lunch+Dinner: Chicken / Mutton / Fish / Paneer / Dal / Rajma / Tofu (>= 30 g)
  Snacks: Whey / nuts / sprouts / yogurt (>= 15 g, optional)

Diet filter rules:
  veg     -> drop _nonVegNames
  vegan   -> drop _nonVegNames + _dairyOrEggNames + check is_vegan field
  non-veg -> everything passes

Four-archetype contract test green: low-cal cut / balanced maintain /
surplus build / vegan high-protein all clear 95% protein adherence."
```

---

## Task 4: Wire `diet_plan_screen.dart` to use `DietPlanGenerator`

**Files:**
- Modify: `lib/features/nutrition/screens/diet_plan_screen.dart` (lines 28-153, 729-765)

- [ ] **Step 1: Add the new import and remove the inline algorithm**

At the top of the file, add the import:
```dart
import '../services/diet_plan_generator.dart';
```

Then in `lib/features/nutrition/screens/diet_plan_screen.dart`, replace `_generateFreshPlan()` (lines 57-95) and `_generateMeal(...)` (lines 97-153) with a single call into the service. The new body of `_generateFreshPlan()`:

```dart
  void _generateFreshPlan() {
    final targets = ref.read(macroTargetsProvider);
    final calorieTarget = targets['calories']?.round() ?? 2400;
    final proteinTarget = targets['protein']?.round() ?? 184;

    // Read diet_preference from Hive profile so the generator filters
    // anchor proteins correctly. Fallback to 'veg' (matches onboarding default).
    final profile = UserRepository.instance.getProfile() ?? const {};
    final dietPref =
        (profile['diet_preference'] as String?)?.toLowerCase() ?? 'veg';

    final now = DateTime.now();
    final seed = DateTime(now.year, now.month, now.day).hashCode;

    final servicePlans = DietPlanGenerator.instance.generate(
      DietPlanInputs(
        calorieTarget: calorieTarget,
        proteinTarget: proteinTarget,
        dietPreference: dietPref,
        seed: seed,
      ),
    );

    _mealPlans = servicePlans.map(_servicePlanToScreenPlan).toList();
    if (mounted) setState(() => _saved = false);
  }

  /// Adapts the public DietMealPlan into the screen's private _MealPlan so
  /// the rest of the screen (swap UI, save UI, PDF export) keeps working.
  _MealPlan _servicePlanToScreenPlan(DietMealPlan svc) => _MealPlan(
        name: svc.name,
        items: svc.items
            .map((i) => _PlanFoodItem(
                  foodId: i.foodId,
                  name: i.name,
                  servingDesc: i.servingDesc,
                  servingG: i.servingG,
                  calories: i.calories,
                  protein: i.protein,
                  carbs: i.carbs,
                  fat: i.fat,
                  category: i.category,
                ))
            .toList(),
        targetCalories: svc.targetCalories,
        targetProtein: svc.targetProtein,
      );
```

The deleted `_generateMeal(...)` is no longer needed — its job moved into `DietPlanGenerator`.

Also delete the `import 'dart:math';` line at the top **only if** no other site in the file uses `Random` after the change. Quick check: `grep "Random(" lib/features/nutrition/screens/diet_plan_screen.dart` should return nothing after the edit.

- [ ] **Step 2: Verify the screen still compiles**

```bash
flutter analyze lib/features/nutrition/screens/diet_plan_screen.dart
```
Expected: zero errors. (One warning may surface for `dart:math` if not removed — fix per Step 1.)

- [ ] **Step 3: Boot the screen via the smoke test**

```bash
flutter test test/nutrition/diet_plan_generator_test.dart
```

This still exercises the new service. There's no widget-level test for `diet_plan_screen.dart`; manual verification on APK happens in Plan A's verification round.

- [ ] **Step 4: Commit**

```bash
git add lib/features/nutrition/screens/diet_plan_screen.dart
git commit -m "refactor(nutrition): diet_plan_screen delegates to DietPlanGenerator

Drops the inline _generateFreshPlan / _generateMeal (~110 LOC) in favor
of a single DietPlanGenerator.instance.generate(...) call. The new
service runs the anchor-protein-per-meal algorithm and returns
DietMealPlan rows, which a tiny adapter (_servicePlanToScreenPlan) maps
back into the screen's private _MealPlan / _PlanFoodItem.

diet_preference is now read from the Hive profile (fallback 'veg' per
onboarding default) so vegan users no longer see Chicken / Whey
appearing as anchors.

The swap UI, save UI, and PDF export are untouched — they consume the
same _MealPlan shape they always did.

Plan C / Obs 2 (APK Test #3, 2026-04-26)."
```

---

## Task 5: Write failing test for `_getMealsToday()` snapshot helper

**Files:**
- Create: `test/ai_coach/meals_today_snapshot_test.dart`

The test reads from a real `nutritionBox` (Hive in-memory mode) and asserts the new `meals_today` shape. To keep `_getMealsToday` testable without exposing it via a public API change, we use Dart's `@visibleForTesting` annotation in Task 6.

- [ ] **Step 1: Create the failing test**

```dart
// test/ai_coach/meals_today_snapshot_test.dart
//
// Validates the new _getMealsToday snapshot helper added to
// AiCoachRepository in APK Test #3 / Q6.3. Builds an in-memory Hive
// nutritionBox with three nlog_* rows for today (one per slot), invokes
// the helper via its @visibleForTesting public seam, and asserts the
// grouped shape.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('aicoach_test_');
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.nutritionBox.clear();
  });

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, "0")}-'
        '${now.day.toString().padLeft(2, "0")}';
  }

  test('_getMealsToday groups today nlog_ rows by meal_type', () async {
    final box = HiveService.instance.nutritionBox;
    final today = _todayStr();

    await box.put('nlog_1', {
      'id': 'nlog_1',
      'date': today,
      'meal_type': 'breakfast',
      'food_name': 'Oats',
      'total_calories': 152,
      'total_protein': 5,
      'total_carbs': 27,
      'total_fat': 3,
    });
    await box.put('nlog_2', {
      'id': 'nlog_2',
      'date': today,
      'meal_type': 'breakfast',
      'food_name': 'Milk (Toned)',
      'total_calories': 140,
      'total_protein': 8,
      'total_carbs': 12,
      'total_fat': 8,
    });
    await box.put('nlog_3', {
      'id': 'nlog_3',
      'date': today,
      'meal_type': 'lunch',
      'food_name': 'Chicken Breast',
      'total_calories': 165,
      'total_protein': 31,
      'total_carbs': 0,
      'total_fat': 4,
    });

    final meals = AiCoachRepository.instance.mealsTodayForTest();

    // Should have at most 4 slots (breakfast / lunch / dinner / snacks)
    expect(meals.length, lessThanOrEqualTo(4));

    final breakfast = meals.firstWhere((m) => m['slot'] == 'breakfast',
        orElse: () => <String, dynamic>{});
    expect(breakfast.isNotEmpty, isTrue, reason: 'breakfast slot must exist');
    expect(breakfast['total_kcal'], equals(292));
    expect(breakfast['total_protein_g'], equals(13));
    expect((breakfast['items'] as List).length, equals(2));
    final names =
        (breakfast['items'] as List).map((i) => i['name'] as String).toList();
    expect(names, containsAll(['Oats', 'Milk (Toned)']));

    final lunch = meals.firstWhere((m) => m['slot'] == 'lunch',
        orElse: () => <String, dynamic>{});
    expect(lunch.isNotEmpty, isTrue, reason: 'lunch slot must exist');
    expect(lunch['total_protein_g'], equals(31));

    // No dinner / snacks rows written → those slots must NOT appear.
    expect(meals.any((m) => m['slot'] == 'dinner'), isFalse);
    expect(meals.any((m) => m['slot'] == 'snacks'), isFalse);
  });

  test('_getMealsToday item shape contains name + macros', () async {
    final box = HiveService.instance.nutritionBox;
    final today = _todayStr();
    await box.put('nlog_1', {
      'id': 'nlog_1',
      'date': today,
      'meal_type': 'lunch',
      'food_name': 'Paneer',
      'total_calories': 265,
      'total_protein': 18,
      'total_carbs': 1,
      'total_fat': 21,
    });

    final meals = AiCoachRepository.instance.mealsTodayForTest();
    final item = (meals.first['items'] as List).first as Map;

    expect(item['name'], equals('Paneer'));
    expect(item['kcal'], equals(265));
    expect(item['protein_g'], equals(18));
    expect(item['carbs_g'], equals(1));
    expect(item['fat_g'], equals(21));
  });

  test('_getMealsToday excludes rows from other dates', () async {
    final box = HiveService.instance.nutritionBox;
    await box.put('nlog_yesterday', {
      'id': 'nlog_yesterday',
      'date': '2020-01-01', // far past
      'meal_type': 'breakfast',
      'food_name': 'Old log',
      'total_calories': 100,
      'total_protein': 5,
    });
    final meals = AiCoachRepository.instance.mealsTodayForTest();
    expect(meals, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test, expect failures**

```bash
flutter test test/ai_coach/meals_today_snapshot_test.dart
```

Expected: FAIL with `NoSuchMethodError: ... 'mealsTodayForTest'` (the public test seam doesn't exist yet).

- [ ] **Step 3: Commit failing test**

```bash
git add test/ai_coach/meals_today_snapshot_test.dart
git commit -m "test(ai_coach): meals_today snapshot grouping (failing)

TDD red phase for the new _getMealsToday helper. Uses an in-memory Hive
nutritionBox + 3 nlog_* rows (breakfast oats + breakfast milk + lunch
chicken) and asserts the helper emits a list of slot-keyed maps with
items[] + total_kcal + total_protein_g.

Currently RED — AiCoachRepository.mealsTodayForTest() doesn't exist.
Implementation lands in Task 7.

Plan C / Q6.3 (APK Test #3, 2026-04-26)."
```

---

## Task 6: Write failing test for `_getNutritionTrend7d()` snapshot helper

**Files:**
- Create: `test/ai_coach/nutrition_trend_7d_snapshot_test.dart`

- [ ] **Step 1: Create the failing test**

```dart
// test/ai_coach/nutrition_trend_7d_snapshot_test.dart
//
// Validates the new _getNutritionTrend7d snapshot helper. Writes nlog_*
// rows spanning 7 days (with one empty day in the middle) and asserts
// the helper returns 7 entries newest-first with zero-fill on the empty
// day.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('aicoach_trend_test_');
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.nutritionBox.clear();
  });

  test('_getNutritionTrend7d returns 7 entries newest-first', () async {
    final box = HiveService.instance.nutritionBox;
    final now = DateTime.now();

    // Day 0 (today): two rows
    await box.put('nlog_today_1', {
      'id': 'nlog_today_1',
      'date': _ymd(now),
      'meal_type': 'breakfast',
      'total_calories': 300,
      'total_protein': 12,
      'total_carbs': 50,
      'total_fat': 10,
      'total_fiber': 5,
    });
    await box.put('nlog_today_2', {
      'id': 'nlog_today_2',
      'date': _ymd(now),
      'meal_type': 'lunch',
      'total_calories': 600,
      'total_protein': 35,
      'total_carbs': 70,
      'total_fat': 15,
      'total_fiber': 8,
    });

    // Day 1 (yesterday): one row
    await box.put('nlog_yest', {
      'id': 'nlog_yest',
      'date': _ymd(now.subtract(const Duration(days: 1))),
      'meal_type': 'dinner',
      'total_calories': 800,
      'total_protein': 40,
      'total_carbs': 90,
      'total_fat': 20,
      'total_fiber': 10,
    });

    // Day 3: nothing (gap)
    // Day 6 (oldest in window): one row
    await box.put('nlog_old', {
      'id': 'nlog_old',
      'date': _ymd(now.subtract(const Duration(days: 6))),
      'meal_type': 'lunch',
      'total_calories': 500,
      'total_protein': 25,
      'total_carbs': 60,
      'total_fat': 12,
      'total_fiber': 7,
    });

    final trend = AiCoachRepository.instance.nutritionTrend7dForTest();

    expect(trend.length, equals(7), reason: 'must return 7 days');
    // Newest first: trend[0].date == today
    expect(trend[0]['date'], equals(_ymd(now)));
    expect(trend[0]['calories'], equals(900));
    expect(trend[0]['protein_g'], equals(47));

    // Day 1 sums correctly
    expect(trend[1]['date'], equals(_ymd(now.subtract(const Duration(days: 1)))));
    expect(trend[1]['calories'], equals(800));

    // Gap day (index 3) zero-filled
    expect(trend[3]['calories'], equals(0));
    expect(trend[3]['protein_g'], equals(0));

    // Oldest entry
    expect(trend[6]['date'], equals(_ymd(now.subtract(const Duration(days: 6)))));
    expect(trend[6]['calories'], equals(500));
  });
}
```

- [ ] **Step 2: Run the test, expect failures**

```bash
flutter test test/ai_coach/nutrition_trend_7d_snapshot_test.dart
```

Expected: FAIL — `nutritionTrend7dForTest` does not exist yet.

- [ ] **Step 3: Commit failing test**

```bash
git add test/ai_coach/nutrition_trend_7d_snapshot_test.dart
git commit -m "test(ai_coach): nutrition_trend_7d snapshot shape (failing)

TDD red phase for _getNutritionTrend7d. Asserts:
  - 7 entries returned (one per day)
  - Newest-first ordering (trend[0] = today)
  - Multi-row days sum correctly (today: 300+600 kcal)
  - Empty days zero-fill (no nlog rows -> calories: 0, protein_g: 0)

Currently RED. Implementation lands in Task 7.

Plan C / Q6.3 (APK Test #3, 2026-04-26)."
```

---

## Task 7: Implement `_getMealsToday` + `_getNutritionTrend7d` and wire into the snapshot

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart` (lines 41-89, 766-816)

- [ ] **Step 1: Add the new helpers and public test seams**

At the top of `ai_coach_repository.dart`, add this import alongside the existing ones if not already present:
```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```
(the file already imports `package:flutter/foundation.dart`; just confirm `visibleForTesting` is reachable).

Inside `buildAiContext()` (around line 89, just before the closing `};`), add:

```dart
      // APK Test #3 / Q6.3 (2026-04-26): expand snapshot so the AI coach
      // can reference what the user actually ate today and across the
      // last 7 days. Per-turn cost ~500-700 bytes; both keys drop early
      // in _compactContext so they never push past the 9.5 KB ceiling.
      'meals_today': _getMealsToday(),
      'nutrition_trend_7d': _getNutritionTrend7d(),
```

Then add these methods (place them right after `_getTodayNutrition()` at line 816):

```dart
  /// Reads today's nlog_* rows from nutritionBox, groups by meal_type,
  /// and returns a list of {slot, items, total_kcal, total_protein_g}
  /// maps. Up to 4 slots (breakfast/lunch/dinner/snacks). Slot order
  /// follows insertion order — slots without rows are omitted entirely
  /// (rather than zero-filled) so the AI sees only meals the user
  /// actually logged.
  List<Map<String, dynamic>> _getMealsToday() {
    final nutritionBox = _hive.nutritionBox;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, "0")}-'
        '${now.day.toString().padLeft(2, "0")}';

    // Preserve canonical slot order: breakfast → lunch → dinner → snacks.
    const slotOrder = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final bySlot = <String, List<Map<String, dynamic>>>{};

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != todayStr) continue;
      // Only group rows with the standard nlog_* shape (skip saved-meal
      // template rows etc. — they don't carry meal_type at log time).
      final id = log['id'] as String? ?? '';
      if (!id.startsWith('nlog_')) continue;
      final mealType = (log['meal_type'] as String?)?.toLowerCase();
      if (mealType == null || mealType.isEmpty) continue;
      // Snap the various aliases the app uses to canonical slot keys.
      final slot = _canonicalSlot(mealType);

      bySlot.putIfAbsent(slot, () => []).add({
        'name': log['food_name'] ?? 'Unknown',
        'kcal': (log['total_calories'] as num?)?.toInt() ?? 0,
        'protein_g': (log['total_protein'] as num?)?.toInt() ?? 0,
        'carbs_g': (log['total_carbs'] as num?)?.toInt() ?? 0,
        'fat_g': (log['total_fat'] as num?)?.toInt() ?? 0,
      });
    }

    final result = <Map<String, dynamic>>[];
    for (final slot in slotOrder) {
      final rows = bySlot[slot];
      if (rows == null || rows.isEmpty) continue;
      var totalK = 0;
      var totalP = 0;
      for (final r in rows) {
        totalK += (r['kcal'] as int);
        totalP += (r['protein_g'] as int);
      }
      result.add({
        'slot': slot,
        'items': rows,
        'total_kcal': totalK,
        'total_protein_g': totalP,
      });
    }
    return result;
  }

  String _canonicalSlot(String raw) {
    final s = raw.toLowerCase();
    if (s == 'snack' || s == 'snacks' || s == 'mid_morning' ||
        s == 'evening' || s == 'mid-morning' || s == 'evening_snack') {
      return 'snacks';
    }
    if (s == 'breakfast') return 'breakfast';
    if (s == 'lunch') return 'lunch';
    if (s == 'dinner') return 'dinner';
    return 'snacks'; // unknown → bucket into snacks
  }

  /// Returns the last 7 days of daily totals, newest-first.
  /// Days without any nlog_* row are zero-filled so the model sees a
  /// stable 7-element timeline (and can detect the difference between
  /// "logged 0" and "didn't log").
  List<Map<String, dynamic>> _getNutritionTrend7d() {
    final nutritionBox = _hive.nutritionBox;
    final result = <Map<String, dynamic>>[];

    for (var i = 0; i < 7; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      final dateStr =
          '${d.year}-${d.month.toString().padLeft(2, "0")}-'
          '${d.day.toString().padLeft(2, "0")}';

      var calories = 0, protein = 0, carbs = 0, fat = 0, fiber = 0;
      for (final raw in nutritionBox.values) {
        if (raw is! Map) continue;
        final log = Map<String, dynamic>.from(raw);
        if (log['date'] != dateStr) continue;
        final id = log['id'] as String? ?? '';
        if (!id.startsWith('nlog_')) continue;
        calories += (log['total_calories'] as num?)?.toInt() ?? 0;
        protein += (log['total_protein'] as num?)?.toInt() ?? 0;
        carbs += (log['total_carbs'] as num?)?.toInt() ?? 0;
        fat += (log['total_fat'] as num?)?.toInt() ?? 0;
        fiber += (log['total_fiber'] as num?)?.toInt() ?? 0;
      }
      result.add({
        'date': dateStr,
        'calories': calories,
        'protein_g': protein,
        'carbs_g': carbs,
        'fat_g': fat,
        'fiber_g': fiber,
      });
    }
    return result;
  }

  /// Test-only seam exposing _getMealsToday for unit tests that don't
  /// want to construct the entire snapshot.
  @visibleForTesting
  List<Map<String, dynamic>> mealsTodayForTest() => _getMealsToday();

  /// Test-only seam exposing _getNutritionTrend7d.
  @visibleForTesting
  List<Map<String, dynamic>> nutritionTrend7dForTest() =>
      _getNutritionTrend7d();
```

- [ ] **Step 2: Run both helper tests, expect green**

```bash
flutter test test/ai_coach/meals_today_snapshot_test.dart
flutter test test/ai_coach/nutrition_trend_7d_snapshot_test.dart
```

Expected: both PASS. If `meals_today` fails on slot order, double-check the `slotOrder` list and `_canonicalSlot` mapping — `mid_morning` and `evening` from diet_plan_screen log naming get bucketed into `snacks`.

- [ ] **Step 3: Commit**

```bash
git add lib/features/ai_coach/repositories/ai_coach_repository.dart
git commit -m "feat(ai_coach): add meals_today + nutrition_trend_7d to snapshot

APK Test #3 / Q6.3. AiCoachRepository.buildAiContext() now includes:

  meals_today: list of {slot, items, total_kcal, total_protein_g}
    for slots actually logged today (breakfast/lunch/dinner/snacks).
    Slot aliases (mid_morning, evening, snack, snacks) collapse to
    'snacks' via _canonicalSlot.

  nutrition_trend_7d: list of 7 daily totals newest-first
    (calories/protein_g/carbs_g/fat_g/fiber_g). Empty days zero-fill so
    the model can detect 'logged 0' vs 'didn't log'.

Both helpers read from nutritionBox (Hive) only — zero network. Per-turn
cost ~500-700 bytes typical. Wired into compaction trim order in the
next commit.

@visibleForTesting seams (mealsTodayForTest / nutritionTrend7dForTest)
let unit tests exercise the helpers without constructing the full
snapshot map."
```

---

## Task 8: Update `_compactContext` trim order in `ai_service.dart`

**Files:**
- Modify: `lib/core/services/ai_service.dart` (lines 110-123)

- [ ] **Step 1: Slot the new keys into `trimSteps`**

In `lib/core/services/ai_service.dart`, the `trimSteps` constant (line 112) currently reads:

```dart
    const trimSteps = [
      'step_history_7d',
      'weight_trend',
      'nutrition_trend',
      'exercise_history',
      'personal_records',
      'coach_notices',
    ];
```

Replace with:

```dart
    const trimSteps = [
      'step_history_7d',
      // APK Test #3 / Q6.3 (2026-04-26): the new meals_today /
      // nutrition_trend_7d keys live in the same priority lane as
      // step_history_7d — they're high-value when present but cheap to
      // drop because they're a verbose timeline-of-logs view that the
      // model can usually infer from today_nutrition + recent_logs.
      'meals_today',
      'nutrition_trend_7d',
      'weight_trend',
      'nutrition_trend',
      'exercise_history',
      'personal_records',
      'coach_notices',
    ];
```

- [ ] **Step 2: Run the existing compaction test to make sure nothing regresses**

```bash
flutter test test/ai_coach/coach_memory_compaction_test.dart
```
Expected: PASS (the test pads the snapshot heavily and checks `coach_memory` survives — neither new key is asserted there, but the trim list still removes everything down to coach_memory).

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/ai_service.dart
git commit -m "feat(ai): teach _compactContext about meals_today + nutrition_trend_7d

Both new snapshot keys live in the same priority lane as step_history_7d
(least load-bearing first). Drop order now:

  step_history_7d -> meals_today -> nutrition_trend_7d -> weight_trend
  -> nutrition_trend -> exercise_history -> personal_records ->
  coach_notices -> truncate(coaching_notes) -> drop(fitness_summary)

This keeps the snapshot under the 9.5 KB ceiling for users with rich
nutrition history (7-day trend + 4 meal slots * 5 items ≈ 600 bytes
that drop first under pressure).

Plan C / Q6.3 (APK Test #3, 2026-04-26)."
```

---

## Task 9: Snapshot byte-budget regression test

**Files:**
- Create: `test/ai_coach/snapshot_compaction_test.dart`

The expansion in Q6.3 must NOT push a typical user's snapshot past 9500 bytes uncompressed. This test pins that contract.

- [ ] **Step 1: Create the test**

```dart
// test/ai_coach/snapshot_compaction_test.dart
//
// Pins the contract that adding meals_today + nutrition_trend_7d to the
// AI snapshot did not push a TYPICAL user's payload past the 9.5 KB
// compaction ceiling. The compactContext trim order must also drop both
// new keys before older keys when under pressure.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

Map<String, dynamic> _typicalSnapshot() {
  // Mirror the shape of buildAiContext() for a typical user:
  //   - 4 today meal slots, ~3 items each
  //   - 7-day trend
  //   - moderate coach_memory + coaching_notes
  return {
    'is_first_ever_message': false,
    'profile': {
      'name': 'Test User',
      'age': 30,
      'gender': 'male',
      'height_cm': 175,
      'current_weight_kg': 80,
      'target_weight_kg': 75,
      'primary_goal': 'lose_fat',
      'fitness_experience': 'intermediate',
      'equipment_access': 'basic_gym',
      'activity_level': 'moderately_active',
      'diet_preference': 'non-veg',
      'injuries': ['none'],
      'bmr': 1750,
      'tdee': 2700,
      'city': 'Bengaluru',
    },
    'progress': {
      'current_phase': 1,
      'current_week': 3,
      'total_workouts_done': 8,
      'current_streak_weeks': 2,
      'detected_experience': 'intermediate',
    },
    'this_week_workouts': List.generate(
        4, (i) => {'date': '2026-04-2$i', 'status': 'completed', 'name': 'Push'}),
    'today_nutrition': {
      'calories_logged': 1820,
      'protein_g': 92,
      'carbs_g': 220,
      'fat_g': 65,
      'fiber_g': 24,
      'fiber_target_g': 30,
      'water_ml': 1500,
    },
    'today_steps': 6500,
    'step_history_7d': List.generate(
        7, (i) => {'date': '2026-04-2$i', 'steps': 5000 + i * 500}),
    'latest_weight': {'date': '2026-04-25', 'weight_kg': 80, 'delta': -0.4},
    'personal_records': List.generate(
        5, (i) => {'exercise': 'Bench $i', 'weight_kg': 60 + i * 5, 'reps': 5}),
    'coaching_notes':
        'User prefers morning workouts. Hates cardio. Crushing protein targets. ' *
            6,
    'coach_memory': {
      'preferred_name': 'Test',
      'communication_style': 'direct',
      'plateau_risk_score': 0.2,
    },
    'fitness_summary': 'Intermediate lifter. 8 workouts, 60% adherence.',
    'motivational_style': 'encouraging',
    'coach_notices': List.generate(
        3, (i) => {'type': 'streak', 'message': 'Keep it up #$i'}),
    'custom_exercises': [],
    'saved_templates': [],
    // The two new APK Test #3 / Q6.3 keys
    'meals_today': [
      {
        'slot': 'breakfast',
        'items': [
          {'name': 'Oats', 'kcal': 152, 'protein_g': 5, 'carbs_g': 27, 'fat_g': 3},
          {'name': 'Milk (Toned)', 'kcal': 140, 'protein_g': 8, 'carbs_g': 12, 'fat_g': 8},
        ],
        'total_kcal': 292,
        'total_protein_g': 13,
      },
      {
        'slot': 'lunch',
        'items': [
          {'name': 'Chicken Breast (grilled)', 'kcal': 165, 'protein_g': 31, 'carbs_g': 0, 'fat_g': 4},
          {'name': 'Brown Rice (cooked)', 'kcal': 218, 'protein_g': 5, 'carbs_g': 47, 'fat_g': 2},
        ],
        'total_kcal': 383,
        'total_protein_g': 36,
      },
      {
        'slot': 'snacks',
        'items': [
          {'name': 'Whey Protein (scoop)', 'kcal': 122, 'protein_g': 24, 'carbs_g': 3, 'fat_g': 1},
        ],
        'total_kcal': 122,
        'total_protein_g': 24,
      },
    ],
    'nutrition_trend_7d': List.generate(
        7,
        (i) => {
              'date': '2026-04-2${i + 1}',
              'calories': 1800 - i * 50,
              'protein_g': 90 - i * 3,
              'carbs_g': 220 - i * 10,
              'fat_g': 65,
              'fiber_g': 24,
            }),
  };
}

void main() {
  test('typical-user snapshot fits under 9.5 KB compaction ceiling', () {
    final snapshot = _typicalSnapshot();
    final bytes = json.encode(snapshot).length;
    expect(
      bytes,
      lessThanOrEqualTo(9500),
      reason: 'typical-user snapshot must fit pre-compaction. Got '
          '$bytes bytes. If this fails, audit which key grew and add it '
          'higher in the _compactContext trim list.',
    );
  });

  test('_compactContext drops meals_today before weight_trend', () {
    // Force the snapshot over budget by adding heavy padding to a key
    // that's listed AFTER meals_today / nutrition_trend_7d in trimSteps.
    final ctx = _typicalSnapshot();
    final padding = List.generate(150, (i) => {'k$i': 'v$i' * 30});
    ctx['weight_trend'] = padding;
    ctx['exercise_history'] = padding;

    expect(json.encode(ctx).length, greaterThan(9500),
        reason: 'sanity: padded snapshot exceeds ceiling');

    final compact = AiService.compactForTest(ctx);

    // step_history_7d / meals_today / nutrition_trend_7d should drop
    // before weight_trend / exercise_history if the trim list does its
    // job. Either ordering surface works as long as the size is met.
    expect(json.encode(compact).length, lessThanOrEqualTo(9500),
        reason: 'compaction must hit the ceiling');
    expect(compact.containsKey('meals_today'), isFalse,
        reason: 'meals_today is in the early trim lane and should be the '
            'first nutrition key dropped under pressure');
    expect(compact.containsKey('nutrition_trend_7d'), isFalse,
        reason: 'nutrition_trend_7d is in the early trim lane');
  });
}
```

- [ ] **Step 2: Run the test, expect green**

```bash
flutter test test/ai_coach/snapshot_compaction_test.dart
```
Expected: both cases PASS. If the typical-user case fails, the new keys padded the snapshot more than estimated — re-run and check `print(json.encode(snapshot).length)` to see the actual size, then trim either `coaching_notes` repetition factor or accept the new size and bump `_maxSnapshotBytes` upstream (DO NOT bump silently — that's a separate decision).

- [ ] **Step 3: Commit**

```bash
git add test/ai_coach/snapshot_compaction_test.dart
git commit -m "test(ai_coach): pin snapshot byte budget after Q6.3 expansion

Two assertions:

  1. A realistic typical-user snapshot (4 today meals * 2-3 items, 7-day
     trend, moderate coaching_notes, full profile + progress + custom
     exercises etc.) stays under 9500 bytes uncompressed. Guards against
     accidentally bloating buildAiContext() in future without updating
     the compaction ceiling.

  2. Under pressure (forced-padded weight_trend + exercise_history),
     _compactContext drops meals_today + nutrition_trend_7d FIRST per
     the updated trim order in ai_service.dart. Pins the trim contract.

Plan C / Q6.3 (APK Test #3, 2026-04-26)."
```

---

## Task 10: Final integration — run the full nutrition + AI test suites

**Files:** None (verification only).

- [ ] **Step 1: Run all Plan C tests in one shot**

```bash
flutter test test/nutrition/diet_plan_generator_test.dart \
             test/ai_coach/meals_today_snapshot_test.dart \
             test/ai_coach/nutrition_trend_7d_snapshot_test.dart \
             test/ai_coach/snapshot_compaction_test.dart \
             test/ai_coach/coach_memory_compaction_test.dart
```
Expected: all green.

- [ ] **Step 2: Run the broader AI coach suite to catch indirect regressions**

```bash
flutter test test/ai_coach/
```
Expected: all green. If `coach_memory_backfill_test.dart` or `prediction_sanitiser_test.dart` regress, neither is touched in this plan — file a separate investigation ticket.

- [ ] **Step 3: Run analyze to catch compile drift**

```bash
flutter analyze lib/features/nutrition/services/diet_plan_generator.dart \
                lib/features/nutrition/screens/diet_plan_screen.dart \
                lib/features/ai_coach/repositories/ai_coach_repository.dart \
                lib/core/services/ai_service.dart
```
Expected: zero errors, zero warnings (info-level lints are tolerable).

- [ ] **Step 4: Document the rollout note**

This task has no commit. Plan C is complete when all tests in Steps 1-3 are green. Plan D's verification task includes manual on-device APK checks for the diet plan output (open Diet Plan, confirm protein hits target) and the AI snapshot (ask "what did I eat today?", confirm the coach lists oats/milk/chicken by name not totals).

---

## Self-Review

**Spec coverage:**
- Diet Plan Protein Anchor (Obs 2) — anchor sets per slot → Task 3 (`_breakfastAnchorNames`, `_mainAnchorNames`, `_snackAnchorNames`)
- Algorithm Pass 1 (anchor pick) → Task 3 (`_pickAnchor`)
- Algorithm Pass 2 (carbs + fats to hit calorie band) → Task 3 (`_pickFiller` loop in `generate`)
- Algorithm Pass 3 (≥95% protein recovery) → Task 3 (`_swapLowestForHigherProtein` loop)
- Filter by `diet_preference` → Task 3 (`_passesDiet`, `_nonVegNames`, `_dairyOrEggNames`)
- Extract into testable service → Task 1 (scaffold) + Task 4 (call site)
- Unit tests for 4 archetypes → Task 2 (red) + Task 3 (green)
- `meals_today` snapshot key → Task 7 (`_getMealsToday`)
- `nutrition_trend_7d` snapshot key → Task 7 (`_getNutritionTrend7d`)
- `_compactContext` updated trim order → Task 8
- Unit tests for both new helpers → Task 5 (meals red) + Task 6 (trend red) + Task 7 (green)
- Snapshot byte-budget regression → Task 9
- Final integration verification → Task 10

**Placeholder scan:** None. Every step contains concrete Dart code, a runnable command, or a HEREDOC commit message.

**Type consistency:**
- `DietMealPlan.slotKey` (string `'breakfast' | 'mid_morning' | 'lunch' | 'evening' | 'dinner'`) is set in `_slotDefs` (Task 3) and read in the test (Task 2). They use the same string literals.
- `meals_today` `slot` values (`'breakfast' | 'lunch' | 'dinner' | 'snacks'`) are produced by `_canonicalSlot` (Task 7) and asserted in the test (Task 5). Both use the same canonical strings; the test does NOT assert presence of `mid_morning` / `evening` because `_canonicalSlot` collapses them into `snacks`.
- `nutrition_trend_7d` map keys (`date`, `calories`, `protein_g`, `carbs_g`, `fat_g`, `fiber_g`) match between Task 6 (test) and Task 7 (impl).
- Hive read shape (`total_calories`, `total_protein`, `total_carbs`, `total_fat`, `total_fiber`) matches the actual `nlog_*` writer in `nutrition_provider.dart:813-826` (verified during investigation).
- `_compactContext` `trimSteps` keys (`'meals_today'`, `'nutrition_trend_7d'`) are spelled identically in `buildAiContext()` (Task 7), the trim list (Task 8), and the byte-budget regression test (Task 9).

**Cross-plan dependency:** Plan C is independent of Plan A (DB) and Plan B (rank UI). It can land in any order relative to them — no shared file outside the diet plan / AI snapshot domain. Final APK verification rolls up across all four plans in the test #3 round.

**Verified file paths (read directly during planning):**
- `lib/features/nutrition/screens/diet_plan_screen.dart` — 765 lines, `_generateMeal` at line 97, `_MealPlan` at line 729.
- `lib/features/ai_coach/repositories/ai_coach_repository.dart` — `buildAiContext` at line 29, `_getTodayNutrition` at line 766.
- `lib/core/services/ai_service.dart` — `_compactContext` at line 106, `_maxSnapshotBytes = 9500` at line 98.
- `lib/shared/repositories/food_repository.dart` — `getByCategory` at line 52, `getAll` at line 15.
- `lib/features/nutrition/providers/nutrition_provider.dart` — `nlog_*` write shape at line 813-826 (single `food_name`, no `items[]`).
- `assets/data/food_database.json` — 12 categories (staples, pulses, protein, supplements, dairy, vegetables, fruits, street_food, beverages, restaurant, nuts_seeds, packaged, sweets); anchor candidates verified by name + protein_std.
