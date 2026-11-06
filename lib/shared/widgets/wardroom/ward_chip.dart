import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Six status-pill tones:
///
/// * [WardChipTone.neutral] — transparent bg, `line2` border, dim text.
/// * [WardChipTone.gold] — gold tint bg, 27% gold border, gold text.
/// * [WardChipTone.ok] — success tint, green text.
/// * [WardChipTone.warn] — amber tint, amber text.
/// * [WardChipTone.bad] — destructive tint, red text.
/// * [WardChipTone.filled] — solid gold, navy text. Reserved for the
///   most important single status chip on a screen (rank, streak, etc.).
enum WardChipTone { neutral, gold, ok, warn, bad, filled }

class WardChip extends StatelessWidget {
  const WardChip({
    super.key,
    required this.label,
    this.tone = WardChipTone.neutral,
    this.leading,
  });

  final String label;
  final WardChipTone tone;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    switch (tone) {
      case WardChipTone.gold:
        bg = AppColors.accentSoft;
        fg = AppColors.accent;
        border = AppColors.accent.withValues(alpha: 0.27);
        break;
      case WardChipTone.ok:
        bg = AppColors.ok.withValues(alpha: 0.14);
        fg = AppColors.ok;
        border = AppColors.ok.withValues(alpha: 0.27);
        break;
      case WardChipTone.warn:
        bg = AppColors.warn.withValues(alpha: 0.16);
        fg = AppColors.warn;
        border = AppColors.warn.withValues(alpha: 0.27);
        break;
      case WardChipTone.bad:
        bg = AppColors.bad.withValues(alpha: 0.14);
        fg = AppColors.bad;
        border = AppColors.bad.withValues(alpha: 0.27);
        break;
      case WardChipTone.filled:
        bg = AppColors.accent;
        fg = AppColors.bgDeep;
        border = AppColors.accent;
        break;
      case WardChipTone.neutral:
        bg = Colors.transparent;
        fg = AppColors.textDim;
        border = AppColors.line2;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              color: fg,
              letterSpacing: 1.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
