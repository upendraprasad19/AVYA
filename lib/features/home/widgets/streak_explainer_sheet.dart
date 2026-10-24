import 'package:flutter/material.dart';

import '../../../core/copy/streak_freeze_copy.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/wardroom/wardroom.dart';

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => StreakExplainerSheet(
        freezesAvailable: freezesAvailable,
        isPro: isPro,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The caps this sheet states: ONE pair for rule 4 and for the PRO note
    // (they equal the refill's `isPro ? 3 : 1`, pinned by a test).
    const freeMax = 1;
    const proMax = 3;
    final maxFreezes = isPro ? proMax : freeMax;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, 14, AppSpacing.gutter, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'STREAK \u00B7 FIELD MANUAL',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    color: AppColors.accent, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'How your streak works',
                    style: AppTypography.h2.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _rule('You earn +1 for every scheduled training day you complete. '
                'Rest days never count against you.'),
            _rule('Rest days and off days don\'t count against you.'),
            _rule(kStreakFreezeRuleMissed),
            _rule(streakFreezeRuleRefill(maxFreezes)),
            _rule('You have $freezesAvailable freeze${freezesAvailable == 1 ? "" : "s"} '
                'available right now.'),
            if (!isPro) ...[
              const SizedBox(height: 10),
              WardCard(
                variant: WardCardVariant.inset,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium,
                        color: AppColors.proGold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        streakFreezeProNote(freeMax: freeMax, proMax: proMax),
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.proGold,
                          fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 5, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
