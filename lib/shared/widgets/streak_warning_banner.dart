import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Red warning banner shown on day 6–7 of a week when the streak is at risk.
class StreakWarningBanner extends StatelessWidget {
  final int streakWeeks;
  final int workoutsRemaining;
  final VoidCallback onTrainNow;

  const StreakWarningBanner({
    super.key,
    required this.streakWeeks,
    required this.workoutsRemaining,
    required this.onTrainNow,
  });

  /// Returns true if the banner should be displayed.
  static bool shouldShow({
    required int streakWeeks,
    required int workoutsPlanned,
    required int workoutsCompleted,
  }) {
    if (streakWeeks == 0) return false;
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
                  '$streakWeeks-week streak at risk!',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFef4444),
                  ),
                ),
                Text(
                  '$workoutsRemaining workout${workoutsRemaining > 1 ? "s" : ""} left this week',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    color: const Color(0xFF6b7a8d),
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
