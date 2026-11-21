// lib/features/profile/widgets/target_impact_dialog.dart
//
// goal-change-targets B3: the "Targets updated" dialog Edit Profile shows after a Save that moved
// the calorie / protein targets, and the lines the reschedule dialog reuses in its "Already
// updated" section.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/target_impact_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/services/target_impact.dart';

/// The two number lines (and the saved-chart sentence when [savedPlanExists]).
class TargetImpactLines extends StatelessWidget {
  const TargetImpactLines({
    super.key,
    required this.impact,
    required this.savedPlanExists,
  });

  final TargetImpact impact;
  final bool savedPlanExists;

  @override
  Widget build(BuildContext context) {
    final line = AppTypography.bodySm
        .copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TargetImpactCopy.caloriesLine(
              from: impact.caloriesFrom, to: impact.caloriesTo),
          key: const ValueKey('target_impact_calories'),
          style: line,
        ),
        const SizedBox(height: 3),
        Text(
          TargetImpactCopy.proteinLine(
              from: impact.proteinFrom, to: impact.proteinTo),
          key: const ValueKey('target_impact_protein'),
          style: line,
        ),
        if (savedPlanExists) ...[
          const SizedBox(height: 8),
          Text(
            TargetImpactCopy.savedPlanSentence,
            key: const ValueKey('target_impact_saved_plan'),
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),
        ],
      ],
    );
  }
}

/// Shows the "Targets updated" dialog and completes when it is dismissed.
Future<void> showTargetImpactDialog(
  BuildContext context, {
  required TargetImpact impact,
  required bool savedPlanExists,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('target_impact_dialog'),
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(
        TargetImpactCopy.title,
        style: AppTypography.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary),
      ),
      content: TargetImpactLines(impact: impact, savedPlanExists: savedPlanExists),
      actions: [
        TextButton(
          key: const ValueKey('target_impact_ok'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(TargetImpactCopy.dismissLabel,
              style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w700, color: AppColors.accent)),
        ),
      ],
    ),
  );
}
