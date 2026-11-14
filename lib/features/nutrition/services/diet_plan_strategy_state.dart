// lib/features/nutrition/services/diet_plan_strategy_state.dart
//
// Diet plan Unit 3b-1b (2026-11-14, docs/plans/diet-strategy-3b.md §3.5,
// §3.6): what the Diet Plan screen asks the generator for. Kept out of
// diet_plan_screen.dart (800-line ceiling).
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/utils/effective_macro_targets.dart';
import '../providers/nutrition_provider.dart';

/// The strategy and carb target of one plan request.
typedef DietPlanRequest = ({DietStrategy strategy, double? carbTarget});

/// The plan request for [targets] (`macroTargetsProvider`, which carries the
/// EFFECTIVE strategy as `strategy_index`) and [foodType].
///
/// - [enabled] false (DietStrategyFlags off): Balanced, no carb target, so
///   the generator runs exactly as before Unit 3b.
/// - Balanced: no carb target (the Balanced generator never reads one).
/// - The effective strategy itself: its carb target, from the same map.
/// - Keto + Vegan → Low carb (`planStrategyFor`): the Low carb carb target
///   for this profile's stored pack, never the Keto one (a Low carb plan
///   built against 30 g of carbs starves; plan §3.5). Null when the pack is
///   incomplete, and the generator then builds Balanced (`builtFor`).
DietPlanRequest dietPlanRequestFor({
  required Map<String, double> targets,
  required FoodType foodType,
  required Map<String, dynamic>? profile,
  required bool enabled,
}) {
  if (!enabled) return (strategy: DietStrategy.balanced, carbTarget: null);
  final effective = dietStrategyOfTargets(targets);
  final requested = planStrategyFor(effective, foodType);
  if (requested == DietStrategy.balanced) {
    return (strategy: requested, carbTarget: null);
  }
  if (requested == effective) {
    return (strategy: requested, carbTarget: targets['carbs']);
  }
  final alt = effectiveMacroTargets(
      resolveBaseMacroPack(profile), requested.storageKey,
      pro: true, enabled: true);
  return (strategy: requested, carbTarget: alt?.carbs);
}
