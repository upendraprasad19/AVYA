import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';

/// Wardroom card variants:
///
/// * [WardCardVariant.standard] — `card` bg, 1-px neutral `line2` border.
/// * [WardCardVariant.hero] — `cardTop` bg, 1-px gold border at 33%
///   alpha. Reserved for featured blocks and today-focus cards.
/// * [WardCardVariant.inset] — `bgRaise` bg, no border. Used for rails
///   inside other cards (nested input strips, log lines).
enum WardCardVariant { standard, hero, inset }

class WardCard extends StatelessWidget {
  const WardCard({
    super.key,
    required this.child,
    this.variant = WardCardVariant.standard,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin,
  });

  final Widget child;
  final WardCardVariant variant;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Border? border;
    switch (variant) {
      case WardCardVariant.hero:
        bg = AppColors.cardTop;
        border = Border.all(
          color: AppColors.accent.withValues(alpha: 0.33),
        );
        break;
      case WardCardVariant.inset:
        bg = AppColors.bgRaise;
        border = null;
        break;
      case WardCardVariant.standard:
        bg = AppColors.card;
        border = Border.all(color: AppColors.line2);
        break;
    }

    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );

    final wrapped = onTap == null
        ? body
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: onTap,
              child: body,
            ),
          );

    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}
