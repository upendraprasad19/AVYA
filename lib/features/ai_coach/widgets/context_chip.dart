import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Horizontal scrollable context chip for the AI Coach screen.
///
/// Active: cyan bg tint, cyan border, cyan text.
/// Inactive: dark bg (#161d28), gray border, gray text.
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentTint : AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: isActive
                ? AppColors.accent.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isActive ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
