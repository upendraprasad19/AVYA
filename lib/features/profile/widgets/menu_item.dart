import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Profile menu row item with icon, label, and optional trailing widget.
class ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Widget? trailing;
  final bool showDivider;

  const ProfileMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.trailing,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.accent)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.row),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor ?? AppColors.accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                trailing ??
                    const Icon(Icons.chevron_right,
                        color: AppColors.textDisabled, size: 20),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(color: AppColors.border, height: 1, thickness: 1),
      ],
    );
  }
}
