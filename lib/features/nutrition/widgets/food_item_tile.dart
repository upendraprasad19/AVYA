import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Food name + calories + macros row used in meal sections.
class FoodItemTile extends StatelessWidget {
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double? quantityG;
  final VoidCallback? onTap;

  const FoodItemTile({
    super.key,
    required this.name,
    required this.calories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.quantityG,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _macroLabel('P', protein, AppColors.accent),
                      const SizedBox(width: 8),
                      _macroLabel('C', carbs, AppColors.orange),
                      const SizedBox(width: 8),
                      _macroLabel('F', fat, AppColors.purple),
                      if (quantityG != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${quantityG!.round()}g',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${calories.round()} kcal',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroLabel(String prefix, double value, Color color) {
    return Text(
      '$prefix ${value.round()}g',
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color.withValues(alpha: 0.7),
      ),
    );
  }
}
