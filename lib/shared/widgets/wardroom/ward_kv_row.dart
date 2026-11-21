import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Key/value row used in detail sheets, settings, weekly report.
///
/// Key is JB Mono uppercase 10 / w600 / +1.5. Value is DM Sans 13 / w600
/// with tabular figures. A dashed `line2` divider underlines each row
/// unless it's the last in a group (pass [showDivider] = false).
class WardKvRow extends StatelessWidget {
  const WardKvRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.showDivider = true,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool showDivider;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.line2,
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
