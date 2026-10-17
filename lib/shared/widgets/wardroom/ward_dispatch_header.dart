import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import 'ward_glyphs.dart';

/// Dispatch-style letterhead for the Coach screen and the Weekly Report.
/// Gold anchor + mono eyebrow on top, Fraunces headline with an
/// italic-gold emphasis word, dim DM Sans context line below, and a
/// double gold rule at the bottom.
///
/// Pass the full headline in [title] and the single word to italicise
/// (gold, Fraunces italic w500) in [emphasis]. The first occurrence of
/// [emphasis] inside [title] is replaced with the italic run.
class WardDispatchHeader extends StatelessWidget {
  const WardDispatchHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.emphasis,
    this.context,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(22, 56, 22, 14),
    this.titleSize = 26,
  });

  final String eyebrow;
  final String title;
  final String? emphasis;
  final String? context;
  final Widget? trailing;
  final EdgeInsets padding;
  final double titleSize;

  @override
  Widget build(BuildContext ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AnchorGlyph(size: 12),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            eyebrow.toUpperCase(),
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.accent,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _TitleWithEmphasis(
                      title: title,
                      emphasis: emphasis,
                      size: titleSize,
                    ),
                    if (context != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        context!,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.textDim,
                          height: 1.4,
                        ),
                      ),
                    ],
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
        ),
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

class _TitleWithEmphasis extends StatelessWidget {
  const _TitleWithEmphasis({
    required this.title,
    required this.emphasis,
    required this.size,
  });

  final String title;
  final String? emphasis;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.h1.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.4,
      height: 1.05,
      color: AppColors.textPrimary,
    );

    if (emphasis == null || emphasis!.isEmpty || !title.contains(emphasis!)) {
      return Text(title, style: base);
    }

    final idx = title.indexOf(emphasis!);
    final before = title.substring(0, idx);
    final mid = title.substring(idx, idx + emphasis!.length);
    final after = title.substring(idx + emphasis!.length);

    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: before),
          TextSpan(
            text: mid,
            style: base.copyWith(
              fontStyle: FontStyle.italic,
              color: AppColors.accent,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
