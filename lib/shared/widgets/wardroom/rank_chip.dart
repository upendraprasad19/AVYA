import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import 'rank_insignia.dart';

/// Compact rank chip rendered as a single mono row:
///
///   [insignia 16dp] SEAMAN 2ND CLASS · NEXT IN 12 DAYS
///
/// Used on Train (top of tab content), Home (one line below streak),
/// and Profile detail sheets.
///
/// Dumb widget — pass `displayName` + `countdownText` already
/// computed from `RankService.getCurrentRank()` /
/// `RankService.getNextRank()`. Keeps the chip portable + testable
/// without spinning up Hive in a widget test.
///
/// `isTerminal` swaps the countdown for a constant `MAX RANK ACHIEVED`
/// string when the user is at Captain.
class RankChip extends StatelessWidget {
  const RankChip({
    super.key,
    required this.rankCode,
    required this.displayName,
    required this.countdownText,
    this.isTerminal = false,
    this.onTap,
  });

  final String rankCode;
  final String displayName;
  final String? countdownText;
  final bool isTerminal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trail = isTerminal
        ? 'MAX RANK ACHIEVED'
        : (countdownText ?? 'NEXT IN —');

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.27),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankInsignia(rankCode: rankCode, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
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
          Text(
            trail,
            maxLines: 1,
            style: AppTypography.mono.copyWith(
              fontSize: 9,
              letterSpacing: 1.0,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}
