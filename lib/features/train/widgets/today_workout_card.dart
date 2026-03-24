import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import '../providers/train_provider.dart';

/// Today's workout preview card at the top of the Train screen.
/// Matches the mockup: pill tag, title, meta row, START WORKOUT button.
class TodayWorkoutCard extends StatelessWidget {
  final WorkoutDayData workout;
  final VoidCallback onStart;

  const TodayWorkoutCard({
    super.key,
    required this.workout,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    // Determine day type label from the workout name
    String dayType = 'PUSH DAY';
    if (workout.name.contains('BACK') || workout.name.contains('PULL')) {
      dayType = 'PULL DAY';
    } else if (workout.name.contains('LEG')) {
      dayType = 'LEG DAY';
    } else if (workout.name.contains('HIIT') ||
        workout.name.contains('CARDIO')) {
      dayType = 'CARDIO DAY';
    } else if (workout.name.contains('REST')) {
      dayType = 'REST DAY';
    }

    // Build the title with the accent-colored portion
    final nameParts = workout.name.split('&');
    final hasAmpersand = nameParts.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom:
              BorderSide(color: AppColors.accent.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pill badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'TODAY \u00b7 $dayType',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 7),

          // Title
          if (hasAmpersand) ...[
            Text(
              nameParts[0].trim(),
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '& ${nameParts[1].trim()}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              workout.name,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Meta row
          Row(
            children: [
              _metaChip('\u23f1 ${workout.estimatedDuration}'),
              const SizedBox(width: 14),
              _metaChip('\u{1f4aa} ${workout.exerciseCount} exercises'),
              const SizedBox(width: 14),
              _metaChip('\u{1f525} ~340 kcal'),
            ],
          ),
          const SizedBox(height: 10),

          // START WORKOUT button
          GestureDetector(
            onTap: onStart,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, color: Colors.black, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'START WORKOUT',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String text) {
    return Text(
      text,
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
    );
  }
}
