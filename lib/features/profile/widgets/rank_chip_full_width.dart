// lib/features/profile/widgets/rank_chip_full_width.dart
//
// Full-width rank chip rendered below WardTabHeader on every tab.
// Reads rank info directly from RankService (dumb read — no Riverpod
// provider spin-up; same pattern as the existing per-tab RankChip usage).
//
// Tap navigates to /train/roadmap so the user can see the full
// 9-rung Indian Navy ladder.
//
// Source: APK Test #4 hotfix plan D §Task D-7.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/rank_insignia.dart';

/// Full-width rank strip displayed below [WardTabHeader] on every tab.
///
/// Shows:  [insignia 18dp] [RANK NAME] · [countdown text]  →  chevron
///
/// The widget is intentionally stateless — no ConsumerWidget overhead.
/// RankService reads from Hive in-process with negligible latency.
class RankChipFullWidth extends StatelessWidget {
  const RankChipFullWidth({super.key});

  @override
  Widget build(BuildContext context) {
    final current = RankService.instance.getCurrentRank();
    final next = RankService.instance.getNextRank();

    final countdown = current.entry.isTerminal
        ? 'MAX RANK ACHIEVED'
        : (next?.daysUntilEligible != null
            ? 'NEXT IN ${next!.daysUntilEligible} DAYS'
            : 'NEXT IN —');

    return GestureDetector(
      onTap: () => context.push('/train/roadmap'),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.bgRaise,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.27),
          ),
        ),
        child: Row(
          children: [
            // Insignia
            RankInsignia(rankCode: current.entry.code, size: 18),
            const SizedBox(width: 10),
            // Rank name
            Text(
              current.entry.displayName.toUpperCase(),
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '·',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                countdown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.mono.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.0,
                  color: AppColors.textDim,
                ),
              ),
            ),
            // Chevron hint
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: AppColors.textMute,
            ),
          ],
        ),
      ),
    );
  }
}
