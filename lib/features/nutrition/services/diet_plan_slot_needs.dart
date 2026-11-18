// lib/features/nutrition/services/diet_plan_slot_needs.dart
//
// Diet protein rules (2026-11-18, docs/plans/diet-protein-rules.md §A2): a
// Non-veg, eggetarian or pescatarian plan must actually contain its protein.
// Before this a "Non-veg" plan drew its main protein at random from the whole
// vegetarian pool plus the meat entries, so about a quarter of Maintain and
// Build plans had a vegetarian lunch AND dinner (measured, 300 seeds).
//
// `slotNeedsFor` is PURE and is the whole rule: for a food type it returns,
// per slot key, the catalog families the slot's protein role must be filled
// from. The generator calls it ONCE per plan, from the plan's own random
// stream and BEFORE the sampling loop (drawing per sample would let the day
// score choose the combination), and filters the required protein role of
// each slot named here: `breakfastProtein` at breakfast, `mainProtein` at
// lunch and dinner. A slot that is not named picks freely, as before.
//
// Draw order (fixed; a test replays it by hand):
//   Non-veg      nextInt(4): 0 = B+L, 1 = B+D, 2 = L+D, 3 = B+L+D; then one
//                nextBool() per L / D need, lunch first: true puts `mutton`
//                in that need's set (the lower mutton weight).
//   Eggetarian   nextBool(): true = the second egg meal is lunch, else dinner.
//   Pescatarian  no draw (lunch and dinner both need fish).
//   Veg, Vegan   no draw and an empty map, so their random stream, and their
//                plans, are byte-identical to before.
//
// Keto and Low carb use the same needs (no strategy parameter).
import 'dart:math';

import 'package:icanbefitter/core/constants/food_types.dart';

import 'diet_plan_catalog.dart';

/// Slot key -> the families its protein role must be filled from.
typedef SlotNeeds = Map<String, Set<DietFamily>>;

/// The slot keys the needs are expressed in (the template keys).
const String kNeedBreakfast = 'breakfast';
const String kNeedLunch = 'lunch';
const String kNeedDinner = 'dinner';

/// Breakfast can only hold egg: its protein role has no chicken, fish or
/// mutton entry.
const Set<DietFamily> _breakfastNeed = {DietFamily.egg};

/// Lunch / dinner for Non-veg: any meat family or egg; `mutton` joins by coin.
Set<DietFamily> _meatNeed({required bool withMutton}) => {
  DietFamily.chicken,
  DietFamily.fish,
  DietFamily.egg,
  if (withMutton) DietFamily.mutton,
};

/// The needs for one plan of [foodType]; draws from [rng] exactly as the
/// header says.
SlotNeeds slotNeedsFor(FoodType foodType, Random rng) {
  switch (foodType) {
    case FoodType.nonVeg:
      final combination = rng.nextInt(4);
      final wantBreakfast = combination != 2;
      final wantLunch = combination != 1;
      final wantDinner = combination != 0;
      final needs = <String, Set<DietFamily>>{};
      if (wantBreakfast) needs[kNeedBreakfast] = _breakfastNeed;
      if (wantLunch) {
        needs[kNeedLunch] = _meatNeed(withMutton: rng.nextBool());
      }
      if (wantDinner) {
        needs[kNeedDinner] = _meatNeed(withMutton: rng.nextBool());
      }
      return needs;
    case FoodType.eggetarian:
      final lunch = rng.nextBool();
      return {
        kNeedBreakfast: _breakfastNeed,
        (lunch ? kNeedLunch : kNeedDinner): const {DietFamily.egg},
      };
    case FoodType.pescatarian:
      return const {
        kNeedLunch: {DietFamily.fish},
        kNeedDinner: {DietFamily.fish},
      };
    case FoodType.veg:
    case FoodType.vegan:
      return const {};
  }
}
