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
  static bool shouldShow({
    required int streakDays,
    required int workoutsPlanned,
    required int workoutsCompleted,
  }) {
    if (streakDays == 0) return false;
    final dayOfWeek = DateTime.now().weekday; // 1=Mon … 7=Sun
    final remaining = workoutsPlanned - workoutsCompleted;
    return dayOfWeek >= 6 && remaining > 0;
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
