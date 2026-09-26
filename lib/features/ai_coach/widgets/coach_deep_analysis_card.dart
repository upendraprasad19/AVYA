import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// "Weekly Deep Analysis" entry at the bottom of the AI Coach insight
/// stack — matches the handoff spec (`design_handoff_wardroom/src/
/// screens/coach.jsx` lines 166–178): dashed-border card, Fraunces
/// 14 title, mono `READY · SUNDAY 21 APR` subline, mono `OPEN →` CTA.
///
/// Tapping routes to `/profile/reports` (the Weekly AI Report screen
/// that PR AD ported). The "READY" date shown is the next Sunday —
/// matches how the report currently generates (weekly on Sundays).
class CoachDeepAnalysisCard extends StatelessWidget {
  const CoachDeepAnalysisCard({super.key});

  @override
  Widget build(BuildContext context) {
    final nextSunday = _nextSundayLabel(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: GestureDetector(
        onTap: () => context.go('/profile/reports'),
        behavior: HitTestBehavior.opaque,
        child: WardDashedBorder(
          color: AppColors.accent.withValues(alpha: 0.40),
          strokeWidth: 1,
          dashLength: 4,
          gapLength: 3,
          radius: AppRadius.card.toDouble(),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Weekly Deep Analysis',
                        style: AppTypography.h3.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'READY \u00B7 $nextSunday',
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 9,
                          color: AppColors.textMute,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'OPEN \u2192',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    color: AppColors.accent,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "SUNDAY DD MMM" for the next Sunday (today if already Sunday).
  static String _nextSundayLabel(DateTime now) {
    const weekdaysToSunday = {
      DateTime.monday: 6,
      DateTime.tuesday: 5,
      DateTime.wednesday: 4,
      DateTime.thursday: 3,
      DateTime.friday: 2,
      DateTime.saturday: 1,
      DateTime.sunday: 0,
    };
    final daysUntil = weekdaysToSunday[now.weekday] ?? 0;
    final sunday = now.add(Duration(days: daysUntil));
    const monthShort = [
      '',
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return 'SUNDAY ${sunday.day} ${monthShort[sunday.month]}';
  }
}
