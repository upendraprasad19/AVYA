import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Red warning banner shown on day 6–7 of a week when the streak is at risk.
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
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a0808),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFef4444).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$streakDays-day streak at risk!',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFef4444),
                  ),
                ),
                Text(
                  freezesAvailable > 0
                      ? '$workoutsRemaining left \u2022 $freezesAvailable freeze${freezesAvailable > 1 ? "s" : ""} remaining'
                      : '$workoutsRemaining left \u2022 No freezes \u2014 don\'t miss today!',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    color: freezesAvailable > 0
                        ? const Color(0xFF6b7a8d)
                        : const Color(0xFFef4444).withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTrainNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFef4444),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Train Now',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
