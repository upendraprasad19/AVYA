import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Mono uppercase section label. JetBrains Mono 9 / w600 / +2.0 in
/// [AppColors.textMute] — used as an eyebrow above a block.
///
/// Accepts an optional [trailing] widget aligned to the right of the
/// label row (e.g., a "VIEW ALL →" link or a status dot).
class WardEyebrow extends StatelessWidget {
  const WardEyebrow(
    this.label, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(22, 0, 22, 8),
    this.color,
  });

  final String label;
  final Widget? trailing;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.monoXs.copyWith(
                color: color ?? AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
