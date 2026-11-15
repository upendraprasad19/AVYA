// lib/features/nutrition/widgets/diet_plan_macro_cards.dart
//
// The two pure header cards of the Diet Plan screen (BMR / TDEE / TARGET and
// the protein / carbs / fat circles), moved out of diet_plan_screen.dart
// unchanged (diet plan Unit 4a, docs/plans/diet-supplements.md section 5):
// the screen sat at 794 of the 800 lines Gate 43 allows
// (scripts/check_god_screen_max_lines.dart). No behaviour change.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// BMR / TDEE / TARGET calories.
class DietPlanTdeeCard extends StatelessWidget {
  const DietPlanTdeeCard({super.key, required this.targets});

  final Map<String, double> targets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _dietPlanStatColumn('BMR', '${targets['bmr']?.round() ?? 0}', 'kcal'),
          Container(width: 1, height: 40, color: AppColors.border),
          _dietPlanStatColumn(
            'TDEE',
            '${targets['tdee']?.round() ?? 0}',
            'kcal',
          ),
          Container(width: 1, height: 40, color: AppColors.border),
          _dietPlanStatColumn(
            'TARGET',
            '${targets['calories']?.round() ?? 0}',
            'kcal',
          ),
        ],
      ),
    );
  }
}

/// Protein / carbs / fat targets as circles.
class DietPlanMacroTargetsCard extends StatelessWidget {
  const DietPlanMacroTargetsCard({super.key, required this.targets});

  final Map<String, double> targets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _dietPlanMacroCircle(
            'Protein',
            '${targets['protein']?.round() ?? 0}g',
            AppColors.accent,
          ),
          _dietPlanMacroCircle(
            'Carbs',
            '${targets['carbs']?.round() ?? 0}g',
            AppColors.green,
          ),
          _dietPlanMacroCircle(
            'Fat',
            '${targets['fat']?.round() ?? 0}g',
            AppColors.purple,
          ),
        ],
      ),
    );
  }
}

Widget _dietPlanStatColumn(String label, String value, String unit) {
  return Column(
    children: [
      Text(
        label,
        style: AppTypography.monoXs.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textDim,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: AppTypography.body.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: AppColors.textPrimary,
        ),
      ),
      Text(
        unit,
        style: AppTypography.monoXs.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: AppColors.textDim,
        ),
      ),
    ],
  );
}

Widget _dietPlanMacroCircle(String label, String value, Color color) {
  return Column(
    children: [
      Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            value,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: AppTypography.bodySm.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textDim,
        ),
      ),
    ],
  );
}
