import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// A single food log entry for the recent logs list.
class FoodLogEntry {
  final String name;
  final double protein;
  final double carbs;
  final double fat;
  final double calories;

  const FoodLogEntry({
    required this.name,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.calories,
  });
}

/// Recent food logs card — list of logged meals with icon, name, macros,
/// calories. Rows use WardKvRow-style layout: mono caps meta, Fraunces
/// numeric kcal trailing.
class RecentFoodLogs extends StatelessWidget {
  final List<FoodLogEntry> entries;
  final VoidCallback? onViewAll;

  const RecentFoodLogs({
    super.key,
    required this.entries,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return WardCard(
      variant: WardCardVariant.standard,
      padding: EdgeInsets.zero,
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No logs yet today. Start tracking!',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ),
            )
          : Column(
              children: List.generate(entries.length, (index) {
                final entry = entries[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: index < entries.length - 1
                        ? const Border(
                            bottom: BorderSide(color: AppColors.line2),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Food icon tile
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.bgRaise,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '\u{1F37D}',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.name,
                              style: AppTypography.body.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'P ${entry.protein.round()}  \u00B7  C ${entry.carbs.round()}  \u00B7  F ${entry.fat.round()}',
                              style: AppTypography.monoXs.copyWith(
                                color: AppColors.textMute,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Calories — Fraunces numeric
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${entry.calories.round()}',
                            style: AppTypography.h3.copyWith(
                              color: AppColors.accent,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'KCAL',
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.textMute,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }
}
