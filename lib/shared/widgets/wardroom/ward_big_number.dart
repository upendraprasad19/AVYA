import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Big number + unit pair — Fraunces tabular figures paired with a JB
/// Mono uppercase unit. The canonical stat display across Daily, Train,
/// Nutrition, Coach, Weekly Report.
///
/// Pass [accent] `true` for gold-coloured numerals (rank, streak, PR).
/// [size] controls the Fraunces font size — defaults to 54 (spec), drop
/// to 28-32 for inline stat rows.
class WardBigNumber extends StatelessWidget {
  const WardBigNumber({
    super.key,
    required this.value,
    this.unit,
    this.size = 54,
    this.accent = false,
    this.bold = false,
  });

  final String value;
  final String? unit;
  final double size;
  final bool accent;

  /// Bumps the Fraunces weight from w600 → w700. Used for prominent
  /// stats on hero cards (weekly volume, calories remaining).
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: AppTypography.numeric.copyWith(
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: accent ? AppColors.accent : AppColors.textPrimary,
            letterSpacing: -1.5,
            height: 1,
          ),
        ),
        if (unit != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Text(
              unit!.toUpperCase(),
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}
