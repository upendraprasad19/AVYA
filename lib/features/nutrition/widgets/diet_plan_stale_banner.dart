// lib/features/nutrition/widgets/diet_plan_stale_banner.dart
//
// goal-change-targets B4: "your targets changed since this chart was built". Plain and factual,
// exact numbers, one Regenerate button and a dismiss; nothing is regenerated until the user taps.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/target_impact_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../services/diet_plan_stale_targets.dart';

class DietPlanStaleBanner extends StatelessWidget {
  const DietPlanStaleBanner({
    super.key,
    required this.stamp,
    required this.current,
    required this.onRegenerate,
    required this.onDismiss,
  });

  final TargetStamp stamp;
  final TargetStamp current;
  final VoidCallback onRegenerate;
  final VoidCallback onDismiss;

  static const title = 'Your targets changed since this chart was built';
  static const sentence = 'Regenerating replaces the plan on screen.';

  @override
  Widget build(BuildContext context) {
    final line = AppTypography.bodySm
        .copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    return Container(
      key: const ValueKey('diet_plan_stale_banner'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  TargetImpactCopy.caloriesLine(
                      from: stamp.calories, to: current.calories),
                  key: const ValueKey('diet_plan_stale_calories'),
                  style: line,
                ),
                Text(
                  TargetImpactCopy.proteinLine(
                      from: stamp.protein, to: current.protein),
                  key: const ValueKey('diet_plan_stale_protein'),
                  style: line,
                ),
                const SizedBox(height: 4),
                Text(sentence,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textDim)),
                const SizedBox(height: 4),
                TextButton(
                  key: const ValueKey('diet_plan_stale_regenerate'),
                  onPressed: onRegenerate,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('Regenerate',
                      style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('diet_plan_stale_dismiss'),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMute),
          ),
        ],
      ),
    );
  }
}
