import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Twelve-phase progress row used on the Profile Journey card. Each dot
/// is 6 px. Phases `< currentPhase` use dimmed gold (`accent` at 45%
/// alpha), the current phase uses solid gold, and future phases use
/// `line2`.
class WardPhaseDots extends StatelessWidget {
  const WardPhaseDots({
    super.key,
    required this.currentPhase,
    this.totalPhases = 12,
    this.dotSize = 6,
    this.gap = 4,
  });

  final int currentPhase;
  final int totalPhases;
  final double dotSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= totalPhases; i++) ...[
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: i < currentPhase
                  ? AppColors.accent.withValues(alpha: 0.45)
                  : i == currentPhase
                      ? AppColors.accent
                      : AppColors.line2,
              shape: BoxShape.circle,
            ),
          ),
          if (i < totalPhases) SizedBox(width: gap),
        ],
      ],
    );
  }
}
