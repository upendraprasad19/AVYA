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
/// in the widget test (diet_plan_chart_v3_screen_test.dart); the 44 dp button
/// (B-pass seat C finding 7) raised it from 128. At a text scale above 1.3 the
/// four cells go to a 2 x 2 grid so a larger font keeps its room (each line
/// still scales DOWN inside its cell rather than overflow).
const double kDietPlanTotalsRowMaxHeight = 144;

/// Text scale above which the four cells go to two rows of two.
const double kDietPlanTotalsGridScale = 1.3;

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
      (
        label: 'Calories',
        plan: totals.calories,
        target: targets.calories,
        unit: '',
      ),
      (
        label: 'Protein',
        plan: totals.protein,
        target: targets.protein,
        unit: 'g',
      ),
      (label: 'Carbs', plan: totals.carbs, target: targets.carbs, unit: 'g'),
      (label: 'Fat', plan: totals.fat, target: targets.fat, unit: 'g'),
    ];
    final dim = AppTypography.bodySm.copyWith(
      fontSize: 10,
      color: AppColors.textDim,
    );
    final grid =
        MediaQuery.textScalerOf(context).scale(1) > kDietPlanTotalsGridScale;
    Widget cellOf(({String label, int plan, double target, String unit}) c) =>
        Expanded(
          child: _Cell(
            key: ValueKey('diet_plan_totals_${c.label.toLowerCase()}'),
            label: c.label,
            plan: c.plan,
            target: c.target,
            unit: c.unit,
            dim: dim,
          ),
        );
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
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              color: AppColors.textMute,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          if (grid) ...[
            Row(children: [for (final c in cells.take(2)) cellOf(c)]),
            const SizedBox(height: 4),
            Row(children: [for (final c in cells.skip(2)) cellOf(c)]),
          ] else
            Row(children: [for (final c in cells) cellOf(c)]),
          if (fitLine != null || backLabel != null) ...[
            const SizedBox(height: 2),
            LayoutBuilder(
              builder: (context, box) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (fitLine != null)
                    Expanded(
                      child: Text(
                        fitLine!,
                        key: const ValueKey('diet_plan_fit_line'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fitOk ? AppColors.ok : AppColors.warn,
                        ),
                      ),
                    ),
                  if (backLabel != null)
                    // The button takes its own width, at most 60% of the row
                    // (its label may wrap to two lines), and the fit line gets
                    // the rest: a long limit text keeps its numbers (B-pass
                    // delta seat finding 2).
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                      child: TextButton(
                        key: const ValueKey('diet_plan_back_up'),
                        onPressed: onBack,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                          backLabel!,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );
    final unitWord = unit == 'g' ? ' grams' : ' kilocalories';
    final diffWord = diff == 0
        ? 'on target'
        : '${diff.abs()}${unit == 'g' ? ' grams' : ' kilocalories'} '
              '${diff > 0 ? 'over' : 'under'}';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label: $plan$unitWord of $t$unitWord, $diffWord',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fit(Text(label, style: dim)),
          fit(
            Text(
              '$plan$unit',
              style: AppTypography.body.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          fit(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('of $t$unit', style: dim),
                const SizedBox(width: 4),
                Text(
                  '$sign$diff$unit',
                  key: ValueKey('diet_plan_totals_diff_${label.toLowerCase()}'),
                  style: dim.copyWith(
                    fontWeight: FontWeight.w700,
                    color: off ? AppColors.warn : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
