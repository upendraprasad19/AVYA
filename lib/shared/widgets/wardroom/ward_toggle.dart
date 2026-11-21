import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Pill toggle — 36 × 20 with an 14 px thumb that slides 16 px left/right.
/// Track crossfades `line2 → accent` over 150 ms ease-out on state
/// change. Used on Settings + Profile Health Sync rows.
class WardToggle extends StatelessWidget {
  const WardToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 36,
    this.height = 20,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final thumb = height - 6;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: width,
        height: height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.accent : AppColors.line2,
          borderRadius: BorderRadius.circular(height),
          border: Border.all(
            color: value ? AppColors.accent : AppColors.textGhost,
            width: 1,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumb,
            height: thumb,
            decoration: BoxDecoration(
              color: value ? AppColors.bgDeep : AppColors.textDim,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
