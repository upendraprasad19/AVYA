import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Streak-at-risk warning banner — matches the handoff
/// (`design_handoff_wardroom/src/screens/daily.jsx` lines 58–79).
///
/// `badSoft` bg with a solid 3-px `bad` left border, 1-px `bad`-55%
/// on the other three edges. Layout: ⚠ glyph → Fraunces 13 w600
/// `bad` title → mono 10 dim meta → solid `bad`-bg "Train Now" CTA.
/// `radSharp` corners.
class StreakWarningBanner extends StatelessWidget {
  final int streakDays;
  final int workoutsRemaining;
  final int freezesAvailable;
  final VoidCallback onTrainNow;
  final int? hoursLeft;

  const StreakWarningBanner({
    super.key,
    required this.streakDays,
    required this.workoutsRemaining,
    this.freezesAvailable = 0,
    required this.onTrainNow,
    this.hoursLeft,
  });

  /// Bug #12 — Personalised per-user eligibility. Unchanged from the
  /// previous Wardroom port; visual shell only updated in this PR.
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
    final rawThreshold = medianWorkoutHour + 3;
    final thresholdHour = rawThreshold.clamp(15, 23);

    return currentHour >= thresholdHour;
  }

  @override
  Widget build(BuildContext context) {
    final clock = DateTime.now();
    final hours = hoursLeft ?? (23 - clock.hour).clamp(0, 23);
    final metaLine = freezesAvailable > 0
        ? '${hours}H LEFT \u00B7 $freezesAvailable FREEZE AVAILABLE'
        : '${hours}H LEFT \u00B7 NO FREEZES — DON\'T MISS TODAY';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        14,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.bad.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border(
            top: BorderSide(color: AppColors.bad.withValues(alpha: 0.33)),
            right: BorderSide(color: AppColors.bad.withValues(alpha: 0.33)),
            bottom: BorderSide(color: AppColors.bad.withValues(alpha: 0.33)),
            left: BorderSide(color: AppColors.bad, width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('\u26A0', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$streakDays-day streak at risk',
                    style: AppTypography.h3.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.bad,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metaLine,
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 10,
                      color: AppColors.textDim,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onTrainNow,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.bad,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: Text(
                  'TRAIN NOW',
                  style: AppTypography.mono.copyWith(
                    fontSize: 11,
                    color: AppColors.bgDeep,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
