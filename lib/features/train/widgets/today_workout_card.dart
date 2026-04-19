import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';

/// Today's workout preview card at the top of the Train screen.
/// Wardroom voice: hero card with Mono eyebrow, Fraunces title, Mono-caps
/// meta row, and a sharp 2-px primary CTA.
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

    return WardCard(
      variant: WardCardVariant.hero,
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mono eyebrow
          Text(
            'TODAY · $dayType',
            style: AppTypography.mono.copyWith(
              color: AppColors.accent,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 8),

          // Fraunces title
          Text(
            workout.name,
            style: AppTypography.h2.copyWith(height: 1.1),
          ),
          const SizedBox(height: 10),

          // Meta row — Mono caps
          Row(
            children: [
              _metaItem(workout.estimatedDuration),
              const SizedBox(width: 14),
              _metaItem('${workout.exerciseCount} exercises'),
              const SizedBox(width: 14),
              _metaItem('~340 kcal'),
            ],
          ),
          const SizedBox(height: 14),

          // Sharp 2-px primary CTA
          WardButton(
            label: 'START WORKOUT',
            onPressed: onStart,
            leading: Icon(Icons.play_arrow, color: AppColors.bgDeep, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.monoXs.copyWith(
        color: AppColors.textDim,
        letterSpacing: 1.4,
      ),
    );
  }
}
