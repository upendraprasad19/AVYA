import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';

/// Inline two-position toggle for unit preferences (KG / LBS, CM / IN).
/// Active option: accent bg, dark text. Inactive: transparent, dim
/// text. Mono 9 w700 +1.5 tracking, sharp 2 px corners.
class WardUnitToggle extends StatelessWidget {
  const WardUnitToggle({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftSelected,
    this.onChanged,
  });

  final String leftLabel;
  final String rightLabel;
  final bool leftSelected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.sharp),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Option(
            label: leftLabel,
            selected: leftSelected,
            onTap: () => onChanged?.call(true),
          ),
          _Option(
            label: rightLabel,
            selected: !leftSelected,
            onTap: () => onChanged?.call(false),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.monoXs.copyWith(
            fontSize: 9,
            color: selected ? AppColors.bgDeep : AppColors.textDim,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
