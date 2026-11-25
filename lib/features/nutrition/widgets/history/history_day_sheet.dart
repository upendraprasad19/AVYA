// Day drill-down of the Nutrition History screen: one day's totals, target,
// status and meals.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import '../../repositories/nutrition_repository.dart';
import '../../services/nutrition_history.dart';
import 'history_common.dart';

Future<void> showHistoryDaySheet(
  BuildContext context, {
  required JudgedDay day,
  required int waterTargetMl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => HistoryDaySheet(
      day: day,
      waterTargetMl: waterTargetMl,
      meals: NutritionRepository.instance.mealsForDay(day.date),
    ),
  );
}

class HistoryDaySheet extends StatelessWidget {
  const HistoryDaySheet({
    super.key,
    required this.day,
    required this.meals,
    required this.waterTargetMl,
  });

  final JudgedDay day;
  final List<Map<String, dynamic>> meals;
  final int waterTargetMl;

  @override
  Widget build(BuildContext context) {
    final d = day.day;
    final t = day.target;
    final dim = AppTypography.bodySm.copyWith(color: AppColors.textDim);
    Widget macro(String label, double value, double? target, String unit) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: dim)),
              Text(
                target == null
                    ? '${groupedInt(value.round())} $unit'
                    : '${groupedInt(value.round())} of '
                        '${groupedInt(target.round())} $unit',
                style: AppTypography.bodyM
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      historyLongDayLabel(d.date),
                      key: const Key('history_day_title'),
                      style: AppTypography.titleS
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  HistoryLegend(
                      [(statusColor(day.status), statusLabel(day.status))]),
                ],
              ),
              const SizedBox(height: 14),
              macro('Calories', d.calories, t?.calories, 'kcal'),
              macro('Protein', d.protein, t?.protein, 'g'),
              macro('Carbs', d.carbs, t?.carbs, 'g'),
              macro('Fat', d.fat, t?.fat, 'g'),
              macro('Fibre', d.fiber, null, 'g'),
              macro('Water', d.waterMl.toDouble(),
                  waterTargetMl > 0 ? waterTargetMl.toDouble() : null, 'ml'),
              if (t != null && t.assumed)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(
                    'Targets were not recorded yet on this day, so your '
                    'earliest recorded target is used.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textMute),
                  ),
                ),
              const SizedBox(height: 10),
              Text('MEALS',
                  style: AppTypography.mono
                      .copyWith(color: AppColors.textMute, letterSpacing: 2)),
              const SizedBox(height: 8),
              if (meals.isEmpty)
                Text('Nothing logged on this day.', style: dim)
              else
                for (final m in meals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(
                              mealSlotOf(m['meal_type']).toUpperCase(),
                              style: AppTypography.monoXs
                                  .copyWith(color: AppColors.textMute)),
                        ),
                        Expanded(
                          child: Text(
                            NutritionReadService.deriveMealDisplayName(m),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyM
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${groupedInt(((m['total_calories'] as num?) ?? 0).round())} kcal',
                          style: dim,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
