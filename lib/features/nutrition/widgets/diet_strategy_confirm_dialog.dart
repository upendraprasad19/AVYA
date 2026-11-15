// lib/features/nutrition/widgets/diet_strategy_confirm_dialog.dart
//
// Diet plan Unit 3a (docs/plans/diet-strategy.md §3.6): the confirm dialog
// before a diet-strategy change, shared by the Diet Plan screen and Edit
// Profile. It shows the targets before and after; carbs and fat always,
// calories and protein only when they move (Edit Profile, when other edited
// fields feed the recompute).
//
// Unit 3b (docs/plans/diet-strategy-3b.md §3.8): a change TO Keto always
// shows this dialog with the Keto medical note, even when the targets would
// not move or are unknown; then [preview] is null or same-shown and the
// dialog has no number rows.
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
  required DietStrategyChangePreview? preview,
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
  final DietStrategyChangePreview? preview;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final showRows = p != null && !p.sameShown;
    final moves = showRows && p.caloriesOrProteinMove;
    final rows = <String>[
      if (showRows) ...[
        if (moves && p.before.calories.round() != p.after.calories.round())
          'Calories ${p.before.calories.round()} kcal → '
              '${p.after.calories.round()} kcal',
        if (moves && p.before.protein.round() != p.after.protein.round())
          'Protein ${p.before.protein.round()} g → '
              '${p.after.protein.round()} g',
        'Carbs ${p.before.carbs.round()} g → ${p.after.carbs.round()} g',
        'Fat ${p.before.fat.round()} g → ${p.after.fat.round()} g',
      ],
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
          if (showRows) ...[
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
          if (next == DietStrategy.keto) ...[
            if (showRows) const SizedBox(height: 12),
            Text(kKetoMedicalNote,
                key: const ValueKey('diet_strategy_confirm_keto_note'),
                style: body),
          ],
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
