import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Renders a rank insignia badge.
///
/// In this APK Test #3 batch, SVG assets at `rank/<code>.svg` do
/// not yet exist (per spec F20). The widget therefore falls back to
/// rendering the rank's `shortName` inside a gold-ringed circular
/// seal. Once SVGs land in `pubspec.yaml`, a future PR can detect
/// the asset (via `rootBundle.load` or a build-time map) and swap
/// in the SVG.
///
/// Sizes follow Wardroom seal proportions:
///   small  16 dp — used in `RankChip`
///   medium 28 dp — used in roadmap markers + ladder rows
///   large  56 dp — used in ladder header / detail sheet
class RankInsignia extends StatelessWidget {
  const RankInsignia({
    super.key,
    required this.rankCode,
    this.size = 28,
    this.dimmed = false,
  });

  final String rankCode;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final entry = rankByCode(rankCode) ?? rankByCode('SD2')!;
    final ringColor = dimmed
        ? AppColors.textMute.withValues(alpha: 0.45)
        : AppColors.accent;
    final textColor = dimmed
        ? AppColors.textMute
        : AppColors.accent;

    // Font scales with the badge — keep the label legible at 16 dp
    // (chip) and tasteful at 56 dp (ladder header).
    final fontSize = size <= 18 ? 6.0 : size <= 32 ? 8.0 : 10.0;
    final letterSpacing = size <= 18 ? 0.6 : 1.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            entry.shortName.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTypography.mono.copyWith(
              fontSize: fontSize,
              color: textColor,
              letterSpacing: letterSpacing,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
