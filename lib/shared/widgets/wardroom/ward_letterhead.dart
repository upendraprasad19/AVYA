import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import 'ward_glyphs.dart';

/// Page-header letterhead block. Small gold anchor glyph + mono eyebrow
/// on top, Fraunces title below, optional gold double-rule divider.
///
/// Used at the top of every Wardroom screen (Daily, Train, Nutrition,
/// Coach, Profile, Weekly Report). Pairs with [WardEyebrow] for inline
/// section labels further down the page.
class WardLetterhead extends StatelessWidget {
  const WardLetterhead({
    super.key,
    this.eyebrow,
    this.title,
    this.trailing,
    this.divider = true,
    this.padding = const EdgeInsets.fromLTRB(22, 56, 22, 14),
    this.showAnchor = true,
  });

  final String? eyebrow;
  final String? title;
  final Widget? trailing;
  final bool divider;
  final EdgeInsets padding;
  final bool showAnchor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: divider
            ? Border(
                bottom: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.33),
                  width: 1,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAnchor)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: AnchorGlyph(size: 12),
                        ),
                      Flexible(
                        child: Text(
                          eyebrow!.toUpperCase(),
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.accent,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      title!,
                      style: AppTypography.h1.copyWith(height: 1.05),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}
