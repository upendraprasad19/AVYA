import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Circular progress ring for calorie tracking. Wraps [WardRing] for
/// consistent animated ring semantics across the app; the home callsite
/// only supplies `current`/`target`, this widget derives `pct`.
class NutritionRing extends StatelessWidget {
  final double current;
  final double target;
  final double size;

  const NutritionRing({
    super.key,
    required this.current,
    required this.target,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final remaining = (target - current).clamp(0, target);

    return WardRing(
      pct: progress,
      size: size,
      stroke: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${remaining.round()}',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'KCAL LEFT',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
