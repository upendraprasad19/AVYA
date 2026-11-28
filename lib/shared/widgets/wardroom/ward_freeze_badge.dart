import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// FreezeBadge — small chip showing the user's available streak freezes.
///
/// Renders as a compact pill: ❄ glyph + count, on a [AppColors.bgRaise]
/// background with a hairline parchment border. Sits alongside
/// [StreakBadge] inside [WardStatusStrip] in the page letterhead.
///
/// Hidden when [count] <= 0 — returns a zero-size [SizedBox.shrink].
class WardFreezeBadge extends StatelessWidget {
  const WardFreezeBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.line2, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '❄',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.info,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: AppTypography.mono.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
