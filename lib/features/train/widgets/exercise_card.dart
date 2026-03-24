import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Exercise card used in the template builder.
class ExerciseCard extends StatelessWidget {
  final String name;
  final String? category;
  final String loggingType;
  final int sets;
  final String reps;
  final int restSeconds;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const ExerciseCard({
    super.key,
    required this.name,
    this.category,
    required this.loggingType,
    this.sets = 3,
    this.reps = '10',
    this.restSeconds = 90,
    this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardS),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Drag handle
            const Icon(Icons.drag_handle, color: AppColors.textDisabled, size: 20),
            const SizedBox(width: 12),

            // Exercise info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (category != null) ...[
                        _chip(category!),
                        const SizedBox(width: 6),
                      ],
                      _chip(_formatLoggingType(loggingType)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$sets sets x $reps ${loggingType == 'timed' ? 'sec' : 'reps'} | ${restSeconds}s rest',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Remove button
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, color: AppColors.red, size: 18),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        text,
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _formatLoggingType(String type) {
    return type.replaceAll('_', ' ').toUpperCase();
  }
}
