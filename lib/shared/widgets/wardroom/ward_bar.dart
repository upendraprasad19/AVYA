import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Horizontal progress meter. Track defaults to `line2` at 8% alpha,
/// fill defaults to Campaign Gold. Pass a [color] override for semantic
/// meters — `AppColors.ok` for hydration, `AppColors.warn` for
/// calories-over, `AppColors.info` for sleep, etc.
///
/// [pct] clamps to 0-1. Height defaults to 4 px. Animates fill width
/// over 400 ms on value change (ease-out).
///
/// Optional [trailingLabel] renders a mono percentage caption to the
/// right of the bar (used on the Train phase-progress header: "25%" in
/// gold mono right-aligned).
class WardBar extends StatelessWidget {
  const WardBar({
    super.key,
    required this.pct,
    this.color,
    this.height = 4,
    this.animate = true,
    this.trackColor,
    this.trailingLabel,
    this.trailingColor,
  });

  final double pct;
  final Color? color;
  final double height;
  final bool animate;
  final Color? trackColor;
  final String? trailingLabel;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final clamped = pct.clamp(0.0, 1.0).toDouble();
    final fill = color ?? AppColors.accent;
    final track = trackColor ?? AppColors.line2;

    final bar = LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(height),
          ),
          alignment: Alignment.centerLeft,
          child: animate
              ? AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  width: width * clamped,
                  height: height,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(height),
                  ),
                )
              : Container(
                  width: width * clamped,
                  height: height,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
        );
      },
    );

    if (trailingLabel == null) return bar;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: bar),
        const SizedBox(width: 10),
        Text(
          trailingLabel!,
          style: AppTypography.monoXs.copyWith(
            color: trailingColor ?? fill,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
