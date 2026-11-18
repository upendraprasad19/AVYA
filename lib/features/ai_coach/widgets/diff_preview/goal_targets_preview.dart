import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/goal_change_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/services/goal_change_patch.dart';

/// The lines under the coach's goal-switch banner that say what ELSE the switch
/// writes (OI-191): the target weight when it moves, and the daily calories and
/// protein when they move. Fed by the same `goalChange(...)` the dispatcher
/// applies, so the preview and the write cannot name different things. Renders
/// nothing when neither moves (a target that already fits, an incomplete profile
/// with no targets to recompute).
class GoalTargetsPreview extends StatelessWidget {
  const GoalTargetsPreview({
    super.key,
    required this.change,
    required this.goal,
    this.metric = true,
  });

  final GoalChange change;
  final String goal;

  /// The user's unit preference (`units_metric`); weights read in lbs when false.
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final showTarget = change.targetSeeded;
    final showTargets = change.targetsMoved;
    if (!showTarget && !showTargets) return const SizedBox.shrink();

    final lines = <Widget>[];
    if (showTarget) {
      lines.add(
        _line(
          GoalChangeCopy.targetLine(
            from: change.targetFrom,
            to: change.seededTarget!,
            metric: metric,
          ),
          key: const ValueKey('goal_preview_target'),
        ),
      );
      lines.add(
        _note(
          GoalChangeCopy.targetReason(
            goal: goal,
            currentKg: change.currentKg,
            metric: metric,
          ),
        ),
      );
    }
    if (showTargets) {
      if (change.caloriesFrom != change.caloriesTo &&
          change.caloriesTo != null) {
        lines.add(
          _line(
            GoalChangeCopy.caloriesLine(
              from: change.caloriesFrom,
              to: change.caloriesTo!,
            ),
            key: const ValueKey('goal_preview_calories'),
          ),
        );
      }
      if (change.proteinFrom != change.proteinTo && change.proteinTo != null) {
        lines.add(
          _line(
            GoalChangeCopy.proteinLine(
              from: change.proteinFrom,
              to: change.proteinTo!,
            ),
            key: const ValueKey('goal_preview_protein'),
          ),
        );
      }
    }

    return Container(
      key: const ValueKey('goal_targets_preview'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GoalChangeCopy.eyebrow,
            style: AppTypography.body.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          ...lines,
        ],
      ),
    );
  }

  Widget _line(String text, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: AppTypography.bodySm.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppTypography.bodySm.copyWith(
        color: AppColors.textSecondary,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}
