// lib/core/utils/effective_macro_targets.dart
//
// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §3.3): the ONE
// place a diet strategy turns STORED targets into SHOWN targets.
//
// Stored targets (`daily_calories`, `protein_grams`, `carb_grams` /
// `carbs_grams`, `fat_grams`) are always the Balanced split and are never
// rewritten for a strategy. Readers (`_resolveNutritionTargets`, Home's
// `NutritionSummaryNotifier`, the coach snapshot) pass the stored pack here.
//
// ONE rule: the strategy applies only when [enabled] (DietStrategyFlags) and
// [pro], the stored strategy is not Balanced, and [base] is a real pack
// (non-null, calories > 0, protein > 0, carbs > 0). Then calories and protein
// come back exactly and carbs/fat come from `BmrCalculator.macroSplit`. In
// EVERY other case [base] comes back unchanged (the very same doubles) with
// `strategy: DietStrategy.balanced`.
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

typedef MacroPack = ({
  double calories,
  double protein,
  double carbs,
  double fat,
});

typedef EffectiveMacroTargets = ({
  double calories,
  double protein,
  double carbs,
  double fat,
  DietStrategy strategy,
});

EffectiveMacroTargets? effectiveMacroTargets(
  MacroPack? base,
  Object? storedStrategy, {
  required bool pro,
  required bool enabled,
}) {
  if (base == null) return null;
  final unchanged = (
    calories: base.calories,
    protein: base.protein,
    carbs: base.carbs,
    fat: base.fat,
    strategy: DietStrategy.balanced,
  );
  if (!enabled || !pro) return unchanged;
  final strategy = dietStrategyOf(storedStrategy);
  if (strategy == DietStrategy.balanced) return unchanged;
  if (!(base.calories > 0) || !(base.protein > 0) || !(base.carbs > 0)) {
    return unchanged;
  }
  final split = BmrCalculator.macroSplit(
    dailyCalories: base.calories,
    proteinGrams: base.protein,
    balancedCarbs: base.carbs,
    strategy: strategy,
  );
  return (
    calories: base.calories,
    protein: base.protein,
    carbs: split.carbGrams.toDouble(),
    fat: split.fatGrams.toDouble(),
    strategy: strategy,
  );
}
