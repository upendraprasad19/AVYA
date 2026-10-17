import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Eight-cell hydration grid for the Nutrition screen. Each cell
/// renders as a small glass icon — filled cells use `info + '33'` bg,
/// `info` border, and their 1-based position index in blue; empty cells
/// are transparent with a dashed `line2` border and a ghost position
/// label.
///
/// Tap a filled cell to fire [onDecrement]; tap the first empty cell
/// (or any empty cell) to fire [onAdd]. Callers enforce the
/// water_logs UNIQUE-per-day constraint.
class WardGlassGrid extends StatelessWidget {
  const WardGlassGrid({
    super.key,
    required this.filled,
    this.slots = 8,
    this.onAdd,
    this.onDecrement,
  });

  final int filled;
  final int slots;
  final VoidCallback? onAdd;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.0;
        final cellWidth = (c.maxWidth - gap * (slots - 1)) / slots;
        return Row(
          children: [
            for (var i = 0; i < slots; i++) ...[
              _Cell(
                index: i + 1,
                filled: i < filled,
                size: cellWidth,
                onTap: i < filled ? onDecrement : onAdd,
              ),
              if (i < slots - 1) SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.filled,
    required this.size,
    required this.onTap,
  });
  final int index;
  final bool filled;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cellColor = filled
        ? AppColors.info.withValues(alpha: 0.2)
        : Colors.transparent;
    final borderColor =
        filled ? AppColors.info.withValues(alpha: 0.8) : AppColors.line2;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size * 1.35,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size * 0.72,
              height: size * 1.15,
              decoration: BoxDecoration(
                color: cellColor,
                border: Border.all(color: borderColor, width: 1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(2),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
            ),
            Text(
              '$index',
              style: AppTypography.monoXs.copyWith(
                color: filled ? AppColors.info : AppColors.textGhost,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
