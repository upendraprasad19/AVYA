// lib/features/nutrition/widgets/diet_plan_swap_sheet.dart
//
// The Diet Plan screen's swap bottom sheet, moved out of
// diet_plan_screen.dart unchanged (diet plan Unit 3b-1b, 2026-11-14: the
// strategy work would have crossed the 800-line ceiling,
// scripts/check_god_screen_max_lines.dart). The screen decides what a pick
// does ([onPick]); the sheet lists the alternatives, ends with "Search any
// food" and closes ITSELF before it hands a pick over, so a dialog the pick
// opens never pops the sheet (diet chart v3, docs/plans/diet-chart-v3.md §4.2).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../providers/diet_serving_view_provider.dart';
import '../services/diet_plan_generator.dart';
import '../services/diet_serving_label.dart';

/// Lists [alternatives] for [itemName] (all of them, scrollable; none is fine:
/// the search row is always there); a tap pops the sheet and calls [onPick].
/// [onSearch] opens "Search any food" on top of the sheet and returns the
/// picked item, or null; a pick pops the sheet and calls [onPick] too.
Future<void> showDietPlanSwapSheet(
  BuildContext context, {
  required String itemName,
  required List<DietPlanFoodItem> alternatives,
  required ValueChanged<DietPlanFoodItem> onPick,
  required Future<DietPlanFoodItem?> Function(BuildContext sheetContext)
      onSearch,
  DietServingView view = DietServingView.portions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
    ),
    builder: (ctx) => ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
      child: SafeArea(
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
              Flexible(
                child: alternatives.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No ready alternatives for this item.',
                          key: const ValueKey('diet_swap_no_alternatives'),
                          style: AppTypography.bodySm.copyWith(
                              fontSize: 12, color: AppColors.textDim),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final alt in alternatives)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                alt.name,
                                style: AppTypography.body.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                              ),
                              subtitle: Text(
                                '${servingLabelFor(alt.foodId, alt.servingDesc, alt.servingG, view)} · ${alt.calories} kcal',
                                style: AppTypography.bodySm.copyWith(
                                    fontSize: 11, color: AppColors.textDim),
                              ),
                              trailing: const Icon(Icons.swap_horiz,
                                  color: AppColors.accent, size: 20),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                onPick(alt);
                              },
                            ),
                        ],
                      ),
              ),
              const Divider(color: AppColors.border),
              InkWell(
                key: const ValueKey('diet_swap_search_row'),
                onTap: () async {
                  final picked = await onSearch(ctx);
                  if (picked == null || !ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  onPick(picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          color: AppColors.accent, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Search any food',
                        style: AppTypography.body.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
