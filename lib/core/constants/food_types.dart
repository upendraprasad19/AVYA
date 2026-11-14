// lib/core/constants/food_types.dart
//
// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md §2.1): the ONE
// food-type vocabulary. Stored as the profile key `diet_preference` (name kept
// for the cloud column); shown to the user as "Food type".
//
// Before this file the value had three vocabularies: onboarding wrote `veg`,
// Edit Profile wrote `non_veg|vegetarian|vegan|pescatarian|keto`, the coach's
// extraction wrote `vegetarian|vegan|non_veg|keto|pescatarian`, and every
// reader matched a different subset (OI-257, diagnose a2b2f1).
//
// Fail-safe direction: a value that was never chosen (null, '') is the
// founder's default, Non-veg. A NON-EMPTY value this table does not know is
// read as Veg: an unknown deliberate choice must never be served meat.
//
// The table is pinned by the shared fixture
// supabase/functions/_shared/testdata/food_type_vocabulary.json, which the
// server mirror (_shared/food_types.ts, Unit 2b) reads too.
library;

enum FoodType {
  veg('veg', 'Veg', 'VEG'),
  nonVeg('non_veg', 'Non-veg', 'NON-VEG'),
  eggetarian('eggetarian', 'Eggetarian', 'EGGETARIAN'),
  pescatarian('pescatarian', 'Pescatarian', 'PESCATARIAN'),
  vegan('vegan', 'Vegan', 'VEGAN');

  const FoodType(this.storageKey, this.label, this.shortLabel);

  /// The value written to `diet_preference` (Hive profile and cloud).
  final String storageKey;

  /// Chip label.
  final String label;

  /// Upper-case tag (Nutrition calorie card, Diet Plan header, PDF).
  final String shortLabel;
}

/// The food type assumed when none was ever chosen (founder, 2026-11-14).
const FoodType kDefaultFoodType = FoodType.nonVeg;

const Map<String, FoodType> _spellings = {
  'veg': FoodType.veg,
  'vegetarian': FoodType.veg,
  'lacto_vegetarian': FoodType.veg,
  'jain': FoodType.veg, // Jain's root-vegetable rule is not modelled
  'sattvic': FoodType.veg,
  'non_veg': FoodType.nonVeg,
  'nonveg': FoodType.nonVeg,
  'non_vegetarian': FoodType.nonVeg,
  'nonvegetarian': FoodType.nonVeg,
  'omnivore': FoodType.nonVeg,
  'anything': FoodType.nonVeg,
  'everything': FoodType.nonVeg,
  'egg': FoodType.eggetarian,
  'eggetarian': FoodType.eggetarian,
  'eggitarian': FoodType.eggetarian,
  'ovo_vegetarian': FoodType.eggetarian,
  'lacto_ovo_vegetarian': FoodType.eggetarian,
  'vegetarian_eggs': FoodType.eggetarian,
  'pescatarian': FoodType.pescatarian,
  'pescetarian': FoodType.pescatarian,
  'vegan': FoodType.vegan,
  'plant_based': FoodType.vegan,
  // Diet STRATEGIES stored as a food type before Unit 2 (Edit Profile's Keto
  // chip, the coach extraction prompt). A keto eater eats everything.
  'keto': FoodType.nonVeg,
  'low_carb': FoodType.nonVeg,
};

/// Lower-case, trimmed, `-` and runs of spaces turned into `_`.
String _canon(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

/// Tolerant read of any stored or legacy value.
FoodType foodTypeOf(Object? raw) {
  if (raw is! String) return kDefaultFoodType;
  final key = _canon(raw);
  if (key.isEmpty) return kDefaultFoodType;
  return _spellings[key] ?? FoodType.veg;
}

/// The profile's food type (`diet_preference`).
FoodType foodTypeOfProfile(Map<dynamic, dynamic>? profile) =>
    foodTypeOf(profile?['diet_preference']);
