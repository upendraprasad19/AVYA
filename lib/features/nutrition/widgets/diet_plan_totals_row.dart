// lib/features/nutrition/widgets/diet_plan_totals_row.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.1): the compact
// "your plan vs target" row under the meals. Four cells (calories, protein,
// carbs, fat): what the plan provides, the target, the signed difference; under
// them the strategy fit line and, when the plan fits a stricter strategy it
// dropped from, the "Back to <strategy>" button.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../services/diet_plan_totals.dart';

/// The row's height ceiling at text scale 1.0, the fit line and the inline
/// button included (the 60 dp ceiling belongs to the calorie cards). Measured
/// 122.8 dp in the widget test (diet_plan_chart_v3_screen_test.dart); a larger
/// system font grows the row, it does not overflow (every line scales down).
const double kDietPlanTotalsRowMaxHeight = 128;

/// The four targets the row compares with.
typedef DietTotalsTargets = ({
  double calories,
  double protein,
  double carbs,
  double fat,
});

class DietPlanTotalsRow extends StatelessWidget {
  const DietPlanTotalsRow({
    super.key,
    required this.totals,
    required this.targets,
    this.targetCaption,
    this.fitLine,
    this.fitOk = true,
    this.backLabel,
    this.onBack,
  });

  final DietPlanTotals totals;
  final DietTotalsTargets targets;

  /// Names the strategy the carb and fat targets belong to when it is not the
  /// one the targets cards show (a Keto + Vegan profile, whose plan is Low
  /// carb).
  final String? targetCaption;
  final String? fitLine;
  final bool fitOk;
  final String? backLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cells = <({String label, int plan, double target, String unit})>[
      (label: 'Calories', plan: totals.calories, target: targets.calories, unit: ''),
      (label: 'Protein', plan: totals.protein, target: targets.protein, unit: 'g'),
      (label: 'Carbs', plan: totals.carbs, target: targets.carbs, unit: 'g'),
      (label: 'Fat', plan: totals.fat, target: targets.fat, unit: 'g'),
    ];
    final dim =
        AppTypography.bodySm.copyWith(fontSize: 10, color: AppColors.textDim);
    return Container(
      key: const ValueKey('diet_plan_totals_row'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            targetCaption == null
                ? 'YOUR PLAN VS TARGET'
                : 'YOUR PLAN VS TARGET · $targetCaption',
            key: const ValueKey('diet_plan_totals_title'),
            style: AppTypography.mono
                .copyWith(fontSize: 9, color: AppColors.textMute, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final c in cells)
                Expanded(
                  child: _Cell(
                    key: ValueKey('diet_plan_totals_${c.label.toLowerCase()}'),
                    label: c.label,
                    plan: c.plan,
                    target: c.target,
                    unit: c.unit,
                    dim: dim,
                  ),
                ),
            ],
          ),
          if (fitLine != null || backLabel != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                if (fitLine != null)
                  Expanded(
                    child: Text(
                      fitLine!,
                      key: const ValueKey('diet_plan_fit_line'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fitOk ? AppColors.ok : AppColors.warn),
                    ),
                  )
                else
                  const Spacer(),
                if (backLabel != null)
                  TextButton(
                    key: const ValueKey('diet_plan_back_up'),
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: Text(backLabel!,
                        style: AppTypography.body.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accent)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.label,
    required this.plan,
    required this.target,
    required this.unit,
    required this.dim,
  });

  final String label;
  final int plan;
  final double target;
  final String unit;
  final TextStyle dim;

  @override
  Widget build(BuildContext context) {
    final t = target.round();
    final diff = plan - t;
    final off = dietPlanTotalOffTarget(plan, target);
    final sign = diff > 0 ? '+' : '';
    // Every line scales DOWN inside its cell instead of overflowing (a cell is
    // about 73 dp at 360 dp, and a larger system font must not break the row).
    Widget fit(Widget child) => FittedBox(
        fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fit(Text(label, style: dim)),
        fit(Text('$plan$unit',
            style: AppTypography.body.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary))),
        fit(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('of $t$unit', style: dim),
            const SizedBox(width: 4),
            Text('$sign$diff$unit',
                key: ValueKey('diet_plan_totals_diff_${label.toLowerCase()}'),
                style: dim.copyWith(
                    fontWeight: FontWeight.w700,
                    color: off ? AppColors.warn : AppColors.textDim)),
          ],
        )),
      ],
    );
  }
}
