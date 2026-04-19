import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

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

    return WardCard(
      variant: isToday ? WardCardVariant.hero : WardCardVariant.standard,
      onTap: onTap,
      child: Row(
        children: [
          // Day indicator tile
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.accent
                  : isToday
                      ? AppColors.accentSoft
                      : AppColors.bgRaise,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check, color: AppColors.bgDeep, size: 20)
                  : Text(
                      'D$dayNumber',
                      style: AppTypography.mono.copyWith(
                        color: isToday
                            ? AppColors.accent
                            : AppColors.textDim,
                        letterSpacing: 1.4,
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
                  style: AppTypography.h3,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      muscles,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: AppColors.textGhost,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$exerciseCount exercises',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (isToday && !isCompleted && onStart != null)
            WardButton(
              label: 'START',
              onPressed: onStart,
              size: WardButtonSize.small,
              fullWidth: false,
            )
          else if (isCompleted)
            const WardChip(label: 'DONE', tone: WardChipTone.ok)
          else
            const Icon(Icons.chevron_right, color: AppColors.textGhost),
        ],
      ),
    );
  }
}
