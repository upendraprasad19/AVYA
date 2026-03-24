import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// 2x2 grid showing baseline stats: Age/Gender, Height/Weight,
/// Activity Level, Body Fat.
class BaselineGrid extends StatelessWidget {
  final String ageGender;
  final String heightWeight;
  final String activityLevel;
  final String bodyFat;

  const BaselineGrid({
    super.key,
    required this.ageGender,
    required this.heightWeight,
    required this.activityLevel,
    required this.bodyFat,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.border, // Gap color between cells
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BaselineCell(label: 'AGE / GENDER', value: ageGender),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: _BaselineCell(
                        label: 'HEIGHT / WEIGHT', value: heightWeight),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Expanded(
                    child: _BaselineCell(
                        label: 'ACTIVITY LEVEL', value: activityLevel),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: _BaselineCell(label: 'BODY FAT', value: bodyFat),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BaselineCell extends StatelessWidget {
  final String label;
  final String value;

  const _BaselineCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
