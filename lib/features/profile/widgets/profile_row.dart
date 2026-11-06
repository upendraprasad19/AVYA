import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// A row item used in profile menu sections.
///
/// Wardroom styling: Fraunces h3 title, Mono caps subtitle, sharp chevron.
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
                  bottom: BorderSide(color: AppColors.line2, width: 1),
                )
              : null,
        ),
        child: Row(
          children: [
            // Icon slab — sharp square, neutral bg
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor ?? AppColors.bgRaise,
                borderRadius: BorderRadius.circular(AppRadius.soft),
              ),
              child: Icon(
                icon,
                size: 15,
                color: iconColor ?? AppColors.textDim,
              ),
            ),
            const SizedBox(width: 12),

            // Info — h3 title, mono subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.h3.copyWith(
                            fontSize: 14,
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
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
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
    return Icon(
      Icons.chevron_right,
      size: 18,
      color: color ?? AppColors.textMute,
    );
  }
}

/// Custom toggle switch matching Wardroom styling (40x22px, sharp corners).
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
          color: value ? AppColors.accent : AppColors.line2,
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
              color: value ? AppColors.bgDeep : AppColors.textDim,
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
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(AppRadius.soft),
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
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        child: Text(
          label,
          style: AppTypography.monoXs.copyWith(
            color: selected ? AppColors.textPrimary : AppColors.textMute,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
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
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'PRO',
        style: AppTypography.monoXs.copyWith(
          color: AppColors.accent,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
