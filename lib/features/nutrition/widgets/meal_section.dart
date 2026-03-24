import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'food_item_tile.dart';

/// Collapsible meal type section (Breakfast, Lunch, Dinner, Snacks).
class MealSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Map<String, dynamic>> items;
  final VoidCallback onAddFood;

  const MealSection({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.items,
    required this.onAddFood,
  });

  @override
  Widget build(BuildContext context) {
    double totalCalories = 0;
    for (final item in items) {
      totalCalories += (item['total_calories'] as num?)?.toDouble() ?? 0;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: items.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
          ),
          childrenPadding: EdgeInsets.only(
            left: AppSpacing.cardPadding,
            right: AppSpacing.cardPadding,
            bottom: AppSpacing.cardPadding,
          ),
          leading: Icon(icon, color: iconColor, size: 20),
          title: Row(
            children: [
              Text(
                title,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (totalCalories > 0)
                Text(
                  '${totalCalories.round()} kcal',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
            ],
          ),
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          children: [
            if (items.isNotEmpty) ...[
              ...items.asMap().entries.map((entry) {
                final item = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom:
                        entry.key < items.length - 1 ? 6 : 0,
                  ),
                  child: FoodItemTile(
                    name: item['food_name'] as String? ?? 'Unknown',
                    calories:
                        (item['total_calories'] as num?)?.toDouble() ?? 0,
                    protein:
                        (item['total_protein'] as num?)?.toDouble() ?? 0,
                    carbs: (item['total_carbs'] as num?)?.toDouble() ?? 0,
                    fat: (item['total_fat'] as num?)?.toDouble() ?? 0,
                    quantityG:
                        (item['quantity_g'] as num?)?.toDouble(),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddFood,
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Add Food',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.row),
                  ),
                  side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
