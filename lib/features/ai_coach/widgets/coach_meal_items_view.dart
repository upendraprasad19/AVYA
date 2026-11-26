import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// OI-348 Landing 3b (founder P5): the body of a coach meal card, one row per
/// food with its macros, then the total that will be stored.
///
/// Read-only and provider-free: both coach meal cards (`LogConfirmCard` for a
/// `log_food` tag, `ToolConfirmCard` for `log_meal_by_text`) build it from
/// their own data. The row copies the Nutrition screen's AI breakdown row
/// (`ai_breakdown_card.dart` `_buildItemRow`: name over the amount, then
/// PRO / CARB / FAT / KCAL columns) without its edit button; that card reads
/// global providers, so it is not reused. [totalKcal] / [totalProtein] come
/// from `NutritionWriteService.mealTotals`, never added up here.
class CoachMealItemsView extends StatelessWidget {
  final List<FoodItem> items;
  final int totalKcal;
  final int totalProtein;

  /// The slot the meal will be written to, already capitalised (`Lunch`).
  final String slot;

  /// False for the tool's parsed items: the parser gives no grams (the 100 g
  /// in `coachItemsFromParsedMeal` is a sentinel), so no amount line.
  final bool showGrams;
  final bool lowConfidence;

  const CoachMealItemsView({
    super.key,
    required this.items,
    required this.totalKcal,
    required this.totalProtein,
    required this.slot,
    this.showGrams = true,
    this.lowConfidence = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          slot.toUpperCase(),
          key: const Key('coach_meal_slot'),
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textDim,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++) _row(items[i], i),
        const SizedBox(height: 8),
        Text(
          'Total  $totalKcal kcal · ${totalProtein}g protein',
          key: const Key('coach_meal_total'),
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (lowConfidence) ...[
          const SizedBox(height: 4),
          Text(
            'Low confidence. Check the amounts before you apply.',
            style: AppTypography.bodySm.copyWith(color: AppColors.warn),
          ),
        ],
      ],
    );
  }

  Widget _row(FoodItem item, int index) {
    return Container(
      key: Key('coach_meal_item_$index'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (showGrams) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_whole(item.quantityG)} g',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _macroCol('${_whole(item.protein)}g', 'PRO', AppColors.accent),
          const SizedBox(width: 6),
          _macroCol('${_whole(item.carbs)}g', 'CARB', AppColors.textPrimary),
          const SizedBox(width: 6),
          _macroCol('${_whole(item.fat)}g', 'FAT', AppColors.warn),
          const SizedBox(width: 6),
          _macroCol(
              _whole(item.kcalWithFallback), 'KCAL', AppColors.textPrimary),
        ],
      ),
    );
  }

  static String _whole(double v) => v.round().toString();

  Widget _macroCol(String value, String label, Color color) {
    return SizedBox(
      width: 38,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTypography.bodySm.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}
