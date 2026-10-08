import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Vertical 46-px left sidebar with a rotated mono category label.
/// Used on Coach Suggested-Actions rows (TRAINING / SLEEP / MEAL) and
/// Notifications category tags (COACH / SYSTEM / PR / MEAL).
///
/// The label rotates -90° (reads bottom-to-top).
class WardCategorySidebar extends StatelessWidget {
  const WardCategorySidebar({
    super.key,
    required this.label,
    this.width = 46,
    this.color,
    this.bg,
  });

  final String label;
  final double width;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: bg ?? AppColors.bgDeep,
      alignment: Alignment.center,
      child: RotatedBox(
        quarterTurns: 3,
        child: Text(
          label.toUpperCase(),
          style: AppTypography.monoXs.copyWith(
            color: color ?? AppColors.accent,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
