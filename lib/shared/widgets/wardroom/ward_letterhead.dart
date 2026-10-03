import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import 'ward_glyphs.dart';

/// Divider style below a [WardLetterhead].
///
/// * [WardDivider.single] — 1 px gold hairline. Used on Daily, Train,
///   Nutrition, Profile.
/// * [WardDivider.double] — two 1 px gold hairlines at different
///   opacities, 2 px gap. Used on Coach, Weekly Report, Settings, Edit
///   Profile, Notifications.
/// * [WardDivider.none] — no rule.
enum WardDivider { single, double, none }

/// Page-header letterhead block. Small gold anchor glyph + mono eyebrow
/// on top, Fraunces title below, optional gold divider.
///
/// Used at the top of every Wardroom screen (Daily, Train, Nutrition,
/// Coach, Profile, Weekly Report). Pairs with `WardEyebrow` for inline
/// section labels further down the page.
///
/// Legacy API: `divider: true|false` → single|none. New API: pass
/// [dividerStyle] directly ([WardDivider.none] / `.single` / `.double`).
/// When [dividerStyle] is set, [divider] is ignored.
class WardLetterhead extends StatelessWidget {
  const WardLetterhead({
    super.key,
    this.eyebrow,
    this.title,
    this.trailing,
    this.leadingAvatar,
    this.divider = true,
    this.dividerStyle,
    this.padding = const EdgeInsets.fromLTRB(22, 56, 22, 14),
    this.showAnchor = true,
  });

  final String? eyebrow;
  final String? title;
  final Widget? trailing;

  /// Optional widget rendered to the LEFT of the eyebrow + title block.
  /// Designed for the 44 dp avatar pattern on the Home letterhead, but
  /// any caller-sized widget works. When null, no left column is added
  /// and existing call sites render unchanged.
  final Widget? leadingAvatar;

  final bool divider;
  final WardDivider? dividerStyle;
  final EdgeInsets padding;
  final bool showAnchor;

  WardDivider get _effectiveStyle =>
      dividerStyle ?? (divider ? WardDivider.single : WardDivider.none);

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (leadingAvatar != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: leadingAvatar!,
            ),
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

    switch (_effectiveStyle) {
      case WardDivider.none:
        return body;
      case WardDivider.single:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            Container(
              height: 1,
              color: AppColors.accent.withValues(alpha: 0.33),
            ),
          ],
        );
      case WardDivider.double:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            Container(
              height: 1,
              color: AppColors.accent.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 2),
            Container(
              height: 1,
              color: AppColors.accent.withValues(alpha: 0.3),
            ),
          ],
        );
    }
  }
}
