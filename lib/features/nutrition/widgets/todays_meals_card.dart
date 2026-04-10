import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Displays today's logged meals in a card with icon, name, macros, and calories.
/// Supports swipe-to-delete and tap-to-edit macros.
class TodaysMealsCard extends StatelessWidget {
  final List<Map<String, dynamic>> meals;
  final void Function(Map<String, dynamic> meal)? onEdit;
  final void Function(String logId)? onDelete;

  const TodaysMealsCard({
    super.key,
    required this.meals,
    this.onEdit,
    this.onDelete,
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
      child: meals.isEmpty ? _buildEmpty() : _buildMealList(),
    );
  }

  static String _mealTypeLabel(String raw) {
    switch (raw) {
      case 'breakfast':
        return 'BREAKFAST';
      case 'lunch':
        return 'LUNCH';
      case 'dinner':
        return 'DINNER';
      case 'snacks':
      case 'snack':
        return 'SNACK';
      default:
        return '';
    }
  }

  static String _formatTime(String? iso8601) {
    if (iso8601 == null || iso8601.isEmpty) return '';
    final dt = DateTime.tryParse(iso8601);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h12:$minute $period';
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
        final fiber = (meal['total_fiber'] as num?)?.toInt() ?? 0;
        final logId = meal['id'] as String?;
        final mealTypeRaw =
            (meal['meal_type_label'] as String? ?? meal['meal_type'] as String?)
                ?.toLowerCase() ??
                '';
        final mealTypeLabel = _mealTypeLabel(mealTypeRaw);
        final createdAt = meal['created_at'] as String?;
        final timeLabel = _formatTime(createdAt);

        Widget row = GestureDetector(
          onTap: onEdit != null ? () => onEdit!(meal) : null,
          child: Container(
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
                      if (mealTypeLabel.isNotEmpty) ...[
                        Text(
                          mealTypeLabel,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.accent.withValues(alpha: 0.71),
                          ),
                        ),
                        const SizedBox(height: 1),
                      ],
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
                        'P:${protein}g · C:${carbs}g · Fat:${fat}g${fiber > 0 ? ' · Fi:${fiber}g' : ''}',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Calories + time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$cal kcal',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    if (timeLabel.isNotEmpty)
                      Text(
                        timeLabel,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                // Edit affordance — makes the tap-to-edit target discoverable.
                // Previously the whole row was tappable but had no visual cue,
                // so users only found the edit sheet by accident.
                if (onEdit != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        );

        // Wrap with Dismissible for swipe-to-delete
        if (onDelete != null && logId != null) {
          row = Dismissible(
            key: ValueKey(logId),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 18),
              color: AppColors.red.withValues(alpha: 0.15),
              child: const Icon(Icons.delete_outline, color: AppColors.red, size: 20),
            ),
            onDismissed: (_) => onDelete!(logId),
            child: row,
          );
        }

        return row;
      }),
    );
  }
}
