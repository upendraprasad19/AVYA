import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';

/// F14 · In-app explainer for how streak + streak-freeze work.
///
/// Launched via tap on the info icon next to the streak badge. No logic
/// changes — just surfaces the existing rules from
/// `WorkoutRepository.calculateCurrentStreak()`.
class StreakExplainerSheet extends StatelessWidget {
  final int freezesAvailable;
  final bool isPro;

  const StreakExplainerSheet({
    super.key,
    required this.freezesAvailable,
    required this.isPro,
  });

  static void show(BuildContext context,
      {required int freezesAvailable, required bool isPro}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => StreakExplainerSheet(
        freezesAvailable: freezesAvailable,
        isPro: isPro,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxFreezes = isPro ? 3 : 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    color: AppColors.accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'How your streak works',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _rule('You earn +1 each week you complete at least 80% of your '
                'scheduled workouts.'),
            _rule('Rest days and off days don\'t count against you.'),
            _rule('Miss a scheduled workout and we\'ll use a Streak Freeze '
                'automatically to keep your streak alive.'),
            _rule('Freezes refill every Monday — $maxFreezes per week '
                '${isPro ? "(PRO)" : "(free tier)"}.'),
            _rule('You have $freezesAvailable freeze${freezesAvailable == 1 ? "" : "s"} '
                'available right now.'),
            if (!isPro) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.proGoldTint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.proGold.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium,
                        color: AppColors.proGold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PRO users get 3 freezes per week instead of 1.',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.proGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rule(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 5, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
