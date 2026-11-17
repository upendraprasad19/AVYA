// lib/features/nutrition/services/diet_plan_strategy_fit.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.2): which diet
// strategy the plan on screen still FITS, judged on the day's carbs. Pure.
//
// A strategy's carb ceiling is its carb target (`BmrCalculator.macroSplit`, the
// same call `effectiveMacroTargets` makes) times [kStrategyFitFactor]. The
// factor is above 1 because a freshly GENERATED Keto or Low carb plan often
// exceeds its own strict target (measured 2026-11-17: up to 1.42 times the
// target without the Supplements shake, 1.48 with the pea shake added on top,
// over 3800 plans in the fit test), and a fresh plan must never read as broken.
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/utils/effective_macro_targets.dart';

/// The carb ceiling of a strategy as a multiple of its carb target.
const double kStrategyFitFactor = 1.5;

/// 2 Keto, 1 Low carb, 0 Balanced: higher is stricter.
int dietStrategyStrictness(DietStrategy s) => switch (s) {
      DietStrategy.keto => 2,
      DietStrategy.lowCarb => 1,
      DietStrategy.balanced => 0,
    };

/// True when [base] is a real pack (the same three checks
/// `effectiveMacroTargets` makes before it applies a strategy).
bool _usable(MacroPack? base) =>
    base != null &&
    base.calories > 0 &&
    base.protein > 0 &&
    base.carbs > 0;

/// The carb target of [s] in grams, or null for Balanced or an unusable pack.
/// (`macroSplit` throws for Balanced, so it is never called with it.)
int? dietStrategyCarbTarget(DietStrategy s, MacroPack? base) {
  if (s == DietStrategy.balanced || !_usable(base)) return null;
  return BmrCalculator.macroSplit(
    dailyCalories: base!.calories,
    proteinGrams: base.protein,
    balancedCarbs: base.carbs,
    strategy: s,
  ).carbGrams;
}

/// The most carbs (grams) a plan of [s] may hold and still FIT it; null for
/// Balanced (nothing to exceed) or an unusable pack.
int? dietStrategyCarbCeiling(DietStrategy s, MacroPack? base) {
  final t = dietStrategyCarbTarget(s, base);
  return t == null ? null : (t * kStrategyFitFactor).round();
}

/// The strictest strategy a day of [dayCarbs] fits; null when no fit can be
/// judged (an unusable pack). [allowKeto] false (a Vegan food type) never
/// answers Keto.
DietStrategy? strictestFit({
  required num dayCarbs,
  required MacroPack? base,
  required bool allowKeto,
}) {
  if (!_usable(base)) return null;
  if (allowKeto && dayCarbs <= dietStrategyCarbCeiling(DietStrategy.keto, base)!) {
    return DietStrategy.keto;
  }
  if (dayCarbs <= dietStrategyCarbCeiling(DietStrategy.lowCarb, base)!) {
    return DietStrategy.lowCarb;
  }
  return DietStrategy.balanced;
}

/// The strategy a pick forces the plan DOWN to, or null when it forces none.
///
/// A shift needs BOTH: the pick adds carbs ([afterCarbs] > [beforeCarbs]), and
/// the day then fits only a LESS strict strategy than [planStrategy]. So a pick
/// that keeps or lowers carbs never asks, even on a plan already over its
/// ceiling (a plan saved before this feature, an extreme archetype), and a pick
/// never moves the plan UP.
DietStrategy? shiftTargetFor({
  required DietStrategy planStrategy,
  required num beforeCarbs,
  required num afterCarbs,
  required MacroPack? base,
  required bool allowKeto,
}) {
  if (planStrategy == DietStrategy.balanced) return null;
  if (!(afterCarbs > beforeCarbs)) return null;
  final fit = strictestFit(dayCarbs: afterCarbs, base: base, allowKeto: allowKeto);
  if (fit == null) return null;
  return dietStrategyStrictness(fit) < dietStrategyStrictness(planStrategy)
      ? fit
      : null;
}

/// The strategy the totals row may offer to go back to: the strictest level
/// the day's carbs fit, capped at [droppedFrom], and only while it is stricter
/// than [planStrategy]. After Keto -> Balanced a day that fits only Low carb
/// again offers "Back to Low carb" (B-pass seat A, finding 2); the cap keeps
/// the offer from ever going above where the plan came from.
DietStrategy? backUpTargetFor({
  required DietStrategy? droppedFrom,
  required DietStrategy planStrategy,
  required num dayCarbs,
  required MacroPack? base,
  required bool allowKeto,
}) {
  if (droppedFrom == null) return null;
  if (dietStrategyStrictness(droppedFrom) <=
      dietStrategyStrictness(planStrategy)) {
    return null;
  }
  final fit = strictestFit(dayCarbs: dayCarbs, base: base, allowKeto: allowKeto);
  if (fit == null) return null;
  final target = dietStrategyStrictness(fit) >= dietStrategyStrictness(droppedFrom)
      ? droppedFrom
      : fit;
  return dietStrategyStrictness(target) > dietStrategyStrictness(planStrategy)
      ? target
      : null;
}

/// The fit line under the totals: null for a Balanced plan or an unusable pack.
/// "Fits Keto (up to 37 g)" / "Over the Keto limit (49 g, up to 37 g)".
String? dietPlanFitLine({
  required DietStrategy planStrategy,
  required num dayCarbs,
  required MacroPack? base,
}) {
  final ceiling = dietStrategyCarbCeiling(planStrategy, base);
  if (ceiling == null) return null;
  final label = planStrategy.label;
  return dayCarbs <= ceiling
      ? 'Fits $label (up to $ceiling g)'
      : 'Over the $label limit (${dayCarbs.round()} g, up to $ceiling g)';
}
