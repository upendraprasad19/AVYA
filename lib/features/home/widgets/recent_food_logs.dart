import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

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

/// Recent food logs card — list of logged meals with icon, name, macros, calories.
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No logs yet today. Start tracking!',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          : Column(
              children: List.generate(entries.length, (index) {
                final entry = entries[index];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: index < entries.length - 1
                        ? const Border(
                            bottom: BorderSide(color: AppColors.border),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Food icon
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(8),
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
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'P:${entry.protein.round()} C:${entry.carbs.round()} F:${entry.fat.round()}',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Calories
                      Text(
                        '${entry.calories.round()} kcal',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }
}
