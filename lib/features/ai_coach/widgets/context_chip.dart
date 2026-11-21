import 'package:flutter/material.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Horizontal scrollable context chip for the AI Coach screen.
///
/// Wardroom styling:
/// * Active → gold [WardChip] (filled tone).
/// * Inactive → neutral [WardChip].
class ContextChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const ContextChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: WardChip(
        label: label,
        tone: isActive ? WardChipTone.gold : WardChipTone.neutral,
      ),
    );
  }
}
