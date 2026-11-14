// lib/features/nutrition/widgets/diet_strategy_confirm_dialog.dart
//
// Diet plan Unit 3a (docs/plans/diet-strategy.md §3.6): the confirm dialog
// before a diet-strategy change, shared by the Diet Plan screen and Edit
// Profile. It shows the targets before and after; carbs and fat always,
// calories and protein only when they move (Edit Profile, when other edited
// fields feed the recompute).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../services/diet_strategy_actions.dart';

/// True when the user pressed Switch. Cancel, a back press or a tap outside
/// the dialog is false (nothing is written).
Future<bool> showDietStrategyConfirmDialog(
  BuildContext context, {
  required DietStrategy next,
  required DietStrategyChangePreview preview,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) =>
        DietStrategyConfirmDialog(next: next, preview: preview),
  );
  return result == true;
}

class DietStrategyConfirmDialog extends StatelessWidget {
  const DietStrategyConfirmDialog({
    super.key,
    required this.next,
    required this.preview,
  });

  final DietStrategy next;
  final DietStrategyChangePreview preview;

  @override
  Widget build(BuildContext context) {
    final b = preview.before;
    final a = preview.after;
    final moves = preview.caloriesOrProteinMove;
    final rows = <String>[
      if (moves && b.calories.round() != a.calories.round())
        'Calories ${b.calories.round()} kcal → ${a.calories.round()} kcal',
      if (moves && b.protein.round() != a.protein.round())
        'Protein ${b.protein.round()} g → ${a.protein.round()} g',
      'Carbs ${b.carbs.round()} g → ${a.carbs.round()} g',
      'Fat ${b.fat.round()} g → ${a.fat.round()} g',
    ];
    final body = AppTypography.body.copyWith(
        fontSize: 13, color: AppColors.textSecondary);
    return AlertDialog(
      key: const ValueKey('diet_strategy_confirm_dialog'),
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.cardM),
      ),
      title: Text(
        'Switch to ${next.label}?',
        style: AppTypography.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your daily targets change:', style: body),
          const SizedBox(height: 8),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(r,
                  style: body.copyWith(color: AppColors.textPrimary)),
            ),
          const SizedBox(height: 8),
          Text(
            moves
                ? 'Calories and protein also change because you edited other fields.'
                : 'Calories and protein stay the same.',
            style: body,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('diet_strategy_confirm_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: AppTypography.body
                  .copyWith(color: AppColors.textSecondary)),
        ),
        TextButton(
          key: const ValueKey('diet_strategy_confirm_switch'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Switch',
              style: AppTypography.body.copyWith(
                  color: AppColors.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
