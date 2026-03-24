import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Displays today's logged meals in a card with icon, name, macros, and calories.
class TodaysMealsCard extends StatelessWidget {
  final List<Map<String, dynamic>> meals;

  const TodaysMealsCard({super.key, required this.meals});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: meals.isEmpty ? _buildEmpty() : _buildMealList(),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Text(
          'No meals logged yet.',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMealList() {
    return Column(
      children: List.generate(meals.length, (index) {
        final meal = meals[index];
        final name = meal['food_name'] as String? ?? 'Unknown';
        final cal = (meal['total_calories'] as num?)?.toInt() ?? 0;
        final protein = (meal['total_protein'] as num?)?.toInt() ?? 0;
        final carbs = (meal['total_carbs'] as num?)?.toInt() ?? 0;
        final fat = (meal['total_fat'] as num?)?.toInt() ?? 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: index < meals.length - 1
                ? const Border(bottom: BorderSide(color: AppColors.border))
                : null,
          ),
          child: Row(
            children: [
              // Meal icon
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('\uD83C\uDF7D', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 10),

              // Name + macros
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
                    Text(
                      'P:${protein}g \u00B7 C:${carbs}g \u00B7 F:${fat}g',
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
                '$cal kcal',
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
    );
  }
}
