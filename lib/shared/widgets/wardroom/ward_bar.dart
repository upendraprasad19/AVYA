import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Horizontal progress meter. Track is [AppColors.line2]-tinted at 10%
/// alpha, fill defaults to Campaign Gold. Pass a [color] override for
/// semantic meters — `AppColors.ok` for hydration, `AppColors.warn` for
/// calories-over, `AppColors.info` for sleep, etc.
///
/// [pct] clamps to 0-1. Height defaults to 4 px. Animates fill width
/// over 400 ms on value change (ease-out).
class WardBar extends StatelessWidget {
  const WardBar({
    super.key,
    required this.pct,
    this.color,
    this.height = 4,
    this.animate = true,
  });

  final double pct;
  final Color? color;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final clamped = pct.clamp(0.0, 1.0).toDouble();
    final fill = color ?? AppColors.accent;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final child = Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.line2,
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
        return child;
      },
    );
  }
}
