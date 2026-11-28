import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';

/// Reusable numeric grid tile used on:
/// * Onboarding Plan targets card (4-col: KCAL / PROT / LIFTS / TGT)
/// * Profile Body Stats card (4-col: WEIGHT / TARGET / BMI / BODY FAT)
/// * Weekly Report top stats (3-col: WORKOUTS / VOLUME / STREAK)
/// * Profile Journey insights inline numbers
///
/// Mono label + Fraunces tabular numeric + optional mono unit. The
/// [accent] variant colours the numeric in gold for emphasis.
class WardStatTile extends StatelessWidget {
  const WardStatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.accent = false,
    this.numericSize = 18,
    this.bg,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final String? unit;
  final bool accent;
  final double numericSize;
  final Color? bg;
  final EdgeInsets padding;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg ?? AppColors.bgRaise,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
      ),
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              fontSize: 8,
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTypography.h2.copyWith(
                  fontSize: numericSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: accent ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!.toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    color: AppColors.textMute,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
