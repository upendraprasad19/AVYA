import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Workout day card showing workout name, muscle groups, exercise count, and status.
class DayCard extends StatelessWidget {
  final int dayNumber;
  final String name;
  final String muscles;
  final int exerciseCount;
  final String status; // planned, completed, skipped
  final bool isToday;
  final VoidCallback? onTap;
  final VoidCallback? onStart;

  const DayCard({
    super.key,
    required this.dayNumber,
    required this.name,
    required this.muscles,
    required this.exerciseCount,
    this.status = 'planned',
    this.isToday = false,
    this.onTap,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == 'completed';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(
            color: isToday
                ? AppColors.accent.withValues(alpha: 0.3)
                : AppColors.border,
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Day indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.accent
                    : isToday
                        ? AppColors.accentTint
                        : AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.row),
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check, color: Colors.black, size: 20)
                    : Text(
                        'D$dayNumber',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isToday
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        muscles,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.textDisabled,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$exerciseCount exercises',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Start button for today
            if (isToday && !isCompleted && onStart != null)
              ElevatedButton(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Start',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              )
            else if (isCompleted)
              Text(
                'DONE',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                  letterSpacing: 1,
                ),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}
