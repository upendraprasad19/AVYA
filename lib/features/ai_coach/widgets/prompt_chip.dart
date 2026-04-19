import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Quick action chip for suggested prompts.
///
/// Wardroom styling: neutral [WardChip] tone with optional leading icon.
/// Labels auto-uppercase inside the chip (Mono-caps eyebrow feel).
class PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const PromptChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: WardChip(
        label: label,
        tone: WardChipTone.gold,
        leading: icon == null
            ? null
            : Icon(icon, color: AppColors.accent, size: 12),
      ),
    );
  }
}
