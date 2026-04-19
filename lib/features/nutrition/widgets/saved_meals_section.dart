import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/nutrition_provider.dart';

/// Shows saved meal presets with one-tap re-log functionality.
class SavedMealsSection extends ConsumerWidget {
  const SavedMealsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedMeals = ref.watch(savedMealsProvider);

    if (savedMeals.isEmpty) {
      return WardCard(
        child: Column(
          children: [
            Icon(Icons.bookmark_border,
                color: AppColors.textDim, size: 28),
            const SizedBox(height: 8),
            Text(
              'No saved meals yet',
              style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 4),
            Text(
              'Log meals with AI and save them for quick re-logging',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return WardCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: index < savedMeals.length - 1
                    ? const Border(
                        bottom: BorderSide(color: AppColors.line2))
                    : null,
              ),
              child: Row(
                children: [
                  // Bookmark icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
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
                          style: AppTypography.h3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'P:${protein}g \u00B7 C:${carbs}g \u00B7 F:${fat}g',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.textDim,
                              ),
                            ),
                            if (timesUsed > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                '\u00D7$timesUsed',
                                style: AppTypography.monoXs.copyWith(
                                  color: AppColors.textMute,
                                  letterSpacing: 1.2,
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
                    '$cals KCAL',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Quick re-log button
                  GestureDetector(
                    onTap: () => _showMealTypeSelector(context, ref, meal),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                      ),
                      child: Text(
                        'RE-LOG',
                        style: AppTypography.monoXs.copyWith(
                          color: AppColors.bgDeep,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  void _showMealTypeSelector(
      BuildContext context, WidgetRef ref, Map<String, dynamic> meal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'LOG AS...',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
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
                  leading:
                      Text(entry.$3, style: const TextStyle(fontSize: 18)),
                  title: Text(
                    entry.$2,
                    style: AppTypography.h3,
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
                          style: AppTypography.body,
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
