import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../providers/nutrition_provider.dart';

/// Shows saved meal presets with one-tap re-log functionality.
class SavedMealsSection extends ConsumerWidget {
  const SavedMealsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedMeals = ref.watch(savedMealsProvider);

    if (savedMeals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.bookmark_border,
                color: AppColors.textSecondary, size: 28),
            const SizedBox(height: 8),
            Text(
              'No saved meals yet',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Log meals with AI and save them for quick re-logging',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                color: AppColors.textDisabled,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(savedMeals.length, (index) {
          final meal = savedMeals[index];
          final name = meal['name'] as String? ?? 'Saved Meal';
          final cals = (meal['total_calories'] as num?)?.toInt() ?? 0;
          final protein = (meal['total_protein'] as num?)?.toInt() ?? 0;
          final carbs = (meal['total_carbs'] as num?)?.toInt() ?? 0;
          final fat = (meal['total_fat'] as num?)?.toInt() ?? 0;
          final timesUsed = (meal['times_used'] as num?)?.toInt() ?? 0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: index < savedMeals.length - 1
                  ? const Border(
                      bottom: BorderSide(color: AppColors.border))
                  : null,
            ),
            child: Row(
              children: [
                // Bookmark icon
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.bookmark,
                      color: AppColors.accent, size: 15),
                ),
                const SizedBox(width: 10),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
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
                      Row(
                        children: [
                          Text(
                            'P:${protein}g \u00B7 C:${carbs}g \u00B7 F:${fat}g',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (timesUsed > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '\u00D7$timesUsed',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Calories
                Text(
                  '$cals kcal',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(width: 8),

                // Quick re-log button
                GestureDetector(
                  onTap: () => _showMealTypeSelector(context, ref, meal),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '+ Log',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _showMealTypeSelector(
      BuildContext context, WidgetRef ref, Map<String, dynamic> meal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
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
                'Log as...',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...[
                ('breakfast', 'Breakfast', '\u2600\uFE0F'),
                ('lunch', 'Lunch', '\u2600\uFE0F'),
                ('dinner', 'Dinner', '\uD83C\uDF19'),
                ('snacks', 'Snack', '\uD83C\uDF6A'),
              ].map((entry) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(entry.$3, style: const TextStyle(fontSize: 18)),
                  title: Text(
                    entry.$2,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref
                        .read(savedMealsProvider.notifier)
                        .relogSavedMeal(meal, mealType: entry.$1);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Logged ${meal['name']} as ${entry.$2}',
                          style: GoogleFonts.getFont('DM Sans', fontSize: 13),
                        ),
                        backgroundColor: AppColors.card,
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
