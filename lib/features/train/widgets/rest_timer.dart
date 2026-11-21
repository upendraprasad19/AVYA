import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Circular countdown timer shown between sets. Wardroom voice: WardRing
/// with Fraunces numeric seconds inside, sharp 2-px Mono-caps slabs below.
class RestTimer extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onSkip;
  final VoidCallback? onAdd15;

  const RestTimer({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onSkip,
    this.onAdd15,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        totalSeconds > 0 ? 1.0 - (secondsRemaining / totalSeconds) : 0.0;
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    final timeText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return WardCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'REST',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 16),
          WardRing(
            pct: progress,
            size: 140,
            stroke: 6,
            color: AppColors.accent,
            child: Text(
              timeText,
              style: AppTypography.numeric.copyWith(
                fontSize: 32,
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onAdd15 != null) ...[
                WardButton(
                  label: 'ADD 15S',
                  onPressed: onAdd15,
                  variant: WardButtonVariant.outline,
                  size: WardButtonSize.small,
                  fullWidth: false,
                ),
                const SizedBox(width: 10),
              ],
              WardButton(
                label: 'SKIP',
                onPressed: onSkip,
                variant: WardButtonVariant.ghost,
                size: WardButtonSize.small,
                fullWidth: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
