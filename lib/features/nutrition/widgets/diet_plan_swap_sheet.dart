// lib/features/nutrition/widgets/diet_plan_swap_sheet.dart
//
// The Diet Plan screen's swap bottom sheet, moved out of
// diet_plan_screen.dart unchanged (diet plan Unit 3b-1b, 2026-11-14: the
// strategy work would have crossed the 800-line ceiling,
// scripts/check_god_screen_max_lines.dart). The screen decides what a pick
// does ([onPick]); the sheet only lists the alternatives and closes.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../services/diet_plan_generator.dart';

/// "No alternatives" feedback (B-pass finding 6 of Unit 1: a silent no-op
/// gave the tap zero feedback).
void showNoDietPlanSwapSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'No alternatives available for this item',
        style: AppTypography.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      ),
      backgroundColor: AppColors.card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Lists [alternatives] for [itemName]; a tap calls [onPick] and closes.
void showDietPlanSwapSheet(
  BuildContext context, {
  required String itemName,
  required List<DietPlanFoodItem> alternatives,
  required ValueChanged<DietPlanFoodItem> onPick,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Swap "$itemName" with...',
              style: AppTypography.body.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            ...alternatives.map((alt) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  alt.name,
                  style: AppTypography.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  '${alt.servingDesc} · ${alt.calories} kcal',
                  style: AppTypography.bodySm
                      .copyWith(fontSize: 11, color: AppColors.textDim),
                ),
                trailing: const Icon(Icons.swap_horiz,
                    color: AppColors.accent, size: 20),
                onTap: () {
                  onPick(alt);
                  Navigator.of(ctx).pop();
                },
              );
            }),
          ],
        ),
      ),
    ),
  );
}
