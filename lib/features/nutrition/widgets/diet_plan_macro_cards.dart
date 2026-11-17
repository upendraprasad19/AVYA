// lib/features/nutrition/widgets/diet_plan_macro_cards.dart
//
// The two pure header cards of the Diet chart screen (BMR / TDEE / TARGET and
// protein / carbs / fat), moved out of diet_plan_screen.dart (diet plan Unit
// 4a): the screen sat at 794 of the 800 lines Gate 43 allows
// (scripts/check_god_screen_max_lines.dart).
//
// Layout v2 (docs/plans/diet-layout-v2.md section 3.5): both are COMPACT, one
// short line each (a small caption over a 16 sp figure), so the diet itself
// starts right after the calorie block. Same names, same numbers.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Height ceiling of each compact card (the layout test pins it).
const double kDietPlanCompactCardMaxHeight = 60;

BoxDecoration _compactDecoration(Color border) => BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.cardM),
      border: Border.all(color: border),
    );

/// BMR / TDEE / TARGET calories.
class DietPlanTdeeCard extends StatelessWidget {
  const DietPlanTdeeCard({super.key, required this.targets});

  final Map<String, double> targets;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('diet_plan_tdee_card'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _compactDecoration(AppColors.accent.withValues(alpha: 0.2)),
      child: Row(
        children: [
          _dietPlanStat('BMR', '${targets['bmr']?.round() ?? 0}'),
          _dietPlanStat('TDEE', '${targets['tdee']?.round() ?? 0}'),
          _dietPlanStat('TARGET kcal', '${targets['calories']?.round() ?? 0}',
              emphasis: true),
        ],
      ),
    );
  }
}

/// Protein / carbs / fat targets.
class DietPlanMacroTargetsCard extends StatelessWidget {
  const DietPlanMacroTargetsCard({super.key, required this.targets});

  final Map<String, double> targets;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('diet_plan_macro_card'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _compactDecoration(AppColors.border),
      child: Row(
        children: [
          _dietPlanStat('Protein', '${targets['protein']?.round() ?? 0}g',
              color: AppColors.accent),
          _dietPlanStat('Carbs', '${targets['carbs']?.round() ?? 0}g',
              color: AppColors.green),
          _dietPlanStat('Fat', '${targets['fat']?.round() ?? 0}g',
              color: AppColors.purple),
        ],
      ),
    );
  }
}

/// One caption-over-figure cell; three share a card equally.
Widget _dietPlanStat(String label, String value,
    {Color color = AppColors.textPrimary, bool emphasis = false}) {
  return Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.monoXs.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textDim,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          style: AppTypography.body.copyWith(
            fontSize: 16,
            fontWeight: emphasis ? FontWeight.w900 : FontWeight.w800,
            color: emphasis ? AppColors.accent : color,
          ),
        ),
      ],
    ),
  );
}
