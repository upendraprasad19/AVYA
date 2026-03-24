import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// A row item used in profile menu sections.
///
/// Matches the mockup `.profile-row` style: icon box, title, subtitle,
/// and a trailing widget (chevron, toggle, or custom).
class ProfileRow extends StatelessWidget {
  final IconData icon;
  final Color? iconBgColor;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? titleSuffix;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showBorder;

  const ProfileRow({
    super.key,
    required this.icon,
    this.iconBgColor,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.titleSuffix,
    this.trailing,
    this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: showBorder
              ? const Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                )
              : null,
        ),
        child: Row(
          children: [
            // Icon box
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor ?? AppColors.input,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 15,
                color: iconColor ?? AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (titleSuffix != null) ...[
                        const SizedBox(width: 6),
                        titleSuffix!,
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Trailing
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Chevron trailing widget for profile rows.
class ProfileRowChevron extends StatelessWidget {
  final Color? color;

  const ProfileRowChevron({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      '\u203A',
      style: TextStyle(
        fontSize: 18,
        color: color ?? AppColors.textSecondary,
      ),
    );
  }
}

/// Custom toggle switch matching the mockup design (40x22px).
class ProfileToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ProfileToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 22,
        decoration: BoxDecoration(
          color: value ? AppColors.accent : AppColors.border,
          borderRadius: BorderRadius.circular(11),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: value ? Colors.black : AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Units segmented control (LBS/IN | KG/CM).
class UnitsSegmentedControl extends StatelessWidget {
  final bool isMetric; // true = KG/CM, false = LBS/IN
  final ValueChanged<bool> onChanged;

  const UnitsSegmentedControl({
    super.key,
    required this.isMetric,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegment('LBS/IN', !isMetric, () => onChanged(false)),
          _buildSegment('KG/CM', isMetric, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _buildSegment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Small gold PRO pill badge (inline with text).
class ProPill extends StatelessWidget {
  const ProPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.proGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        'PRO',
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.proGold,
        ),
      ),
    );
  }
}
