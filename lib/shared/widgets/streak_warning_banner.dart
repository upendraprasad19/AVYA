import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Warning card shown when the streak is at risk.
///
/// Wardroom styling: inset card, warn-tinted leading chip, Mono eyebrow,
/// DM Sans body, sharp outlined TRAIN NOW slab.
class StreakWarningBanner extends StatelessWidget {
  final int streakDays;
  final int workoutsRemaining;
  final int freezesAvailable;
  final VoidCallback onTrainNow;

  const StreakWarningBanner({
    super.key,
    required this.streakDays,
    required this.workoutsRemaining,
    this.freezesAvailable = 0,
    required this.onTrainNow,
  });

  /// Returns true if the banner should be displayed.
  ///
  /// Bug #12 — Personalised per user. Replaces the old "Sat/Sun-only +
  /// any-time-of-day" check with a smart rule:
  ///
  /// 1. Today must be a workout day (not a rest day).
  /// 2. Today's workout must NOT already be completed.
  /// 3. Current time must be ≥ user's median workout hour + 3 hours
  ///    (with a 15:00 IST hard floor and 23:00 IST hard ceiling).
  /// 4. User must have a non-zero streak (we don't warn on day 0).
  ///
  /// All inputs are computed by [streakWarningEligibilityProvider] in
  /// `home_provider.dart`. Keep this method pure so it stays unit-testable.
  static bool shouldShow({
    required int streakDays,
    required bool isWorkoutDayToday,
    required bool isTodayCompleted,
    required int medianWorkoutHour,
    DateTime? now,
  }) {
    if (streakDays == 0) return false;
    if (!isWorkoutDayToday) return false;
    if (isTodayCompleted) return false;

    final clock = now ?? DateTime.now();
    final currentHour = clock.hour;

    // Median + 3, then clamp to [15, 23]. The clamp prevents pre-3pm warnings
    // (annoying for users who train in the morning) and post-11pm warnings
    // (useless — by then it's "tomorrow's problem").
    final rawThreshold = medianWorkoutHour + 3;
    final thresholdHour = rawThreshold.clamp(15, 23);

    return currentHour >= thresholdHour;
  }

  @override
  Widget build(BuildContext context) {
    final bodyText = freezesAvailable > 0
        ? '$workoutsRemaining left \u2022 $freezesAvailable freeze${freezesAvailable > 1 ? "s" : ""} remaining'
        : '$workoutsRemaining left \u2022 No freezes — don\'t miss today!';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.stackS,
      ),
      child: WardCard(
        variant: WardCardVariant.inset,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.stackM,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const WardChip(
              label: 'AT RISK',
              tone: WardChipTone.bad,
              leading: Icon(
                Icons.local_fire_department_outlined,
                size: 12,
                color: AppColors.bad,
              ),
            ),
            const SizedBox(width: AppSpacing.stackM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'STREAK AT RISK',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.bad,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.stackXS),
                  Text(
                    '$streakDays-day streak · $bodyText',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.stackS),
            WardButton(
              label: 'TRAIN NOW',
              onPressed: onTrainNow,
              variant: WardButtonVariant.danger,
              size: WardButtonSize.small,
              fullWidth: false,
            ),
          ],
        ),
      ),
    );
  }
}
