// lib/features/nutrition/services/diet_plan_supplements_state.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 3): the two pure
// guards of the Diet Plan screen's Supplements handling, next to
// diet_plan_strategy_state.dart.
library;

/// True when a saved plan was built under the same Supplements state as the
/// current one. The stamp `diet_supplements: true` is written ONLY for a plan
/// built with Supplements active; a plan without it (every plan saved before
/// Unit 4, and every plan of a user who never switched it on) was built
/// without. A plan whose state differs is not loaded: the screen generates a
/// fresh one (no hints, no notice), like a plan of another strategy.
bool savedPlanMatchesSupplements(Map<dynamic, dynamic> plan, bool active) =>
    (plan['diet_supplements'] == true) == active;

/// True when a change of the Supplements state calls for one regeneration:
/// never before the first plan ([planEpoch] 0), and only when the plan on
/// screen was built under another state.
bool dietPlanNeedsRegenerationForSupplements({
  required int planEpoch,
  required bool planActive,
  required bool active,
}) =>
    planEpoch > 0 && planActive != active;
