import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';

/// Four button variants in the Wardroom voice — Fraunces w600 uppercase
/// with +2.5 letter-spacing, sharp 2-px corners, light haptic on tap.
///
/// * [WardButtonVariant.primary] — solid gold on navy. The headline CTA.
/// * [WardButtonVariant.outline] — transparent, 1-px gold border.
/// * [WardButtonVariant.ghost] — transparent, 1-px `line2` border.
/// * [WardButtonVariant.danger] — transparent, `bad`-tinted text + border.
enum WardButtonVariant { primary, outline, ghost, danger }

/// Size presets — small buttons used in inline actions, medium is the
/// default CTA size.
enum WardButtonSize { small, medium }

class WardButton extends StatelessWidget {
  const WardButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = WardButtonVariant.primary,
    this.size = WardButtonSize.medium,
    this.leading,
    this.trailing,
    this.fullWidth = true,
    this.haptic = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final WardButtonVariant variant;
  final WardButtonSize size;
  final Widget? leading;
  final Widget? trailing;
  final bool fullWidth;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    switch (variant) {
      case WardButtonVariant.primary:
        bg = AppColors.accent;
        fg = AppColors.bgDeep;
        border = AppColors.accent;
        break;
      case WardButtonVariant.outline:
        bg = Colors.transparent;
        fg = AppColors.accent;
        border = AppColors.accent;
        break;
      case WardButtonVariant.ghost:
        bg = Colors.transparent;
        fg = AppColors.textPrimary;
        border = AppColors.line2;
        break;
      case WardButtonVariant.danger:
        bg = Colors.transparent;
        fg = AppColors.bad;
        border = AppColors.bad.withValues(alpha: 0.4);
        break;
    }

    final padding = size == WardButtonSize.small
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    final fontSize = size == WardButtonSize.small ? 11.0 : 12.0;

    final disabled = onPressed == null;
    final button = Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          onTap: disabled
              ? null
              : () {
                  if (haptic) HapticFeedback.lightImpact();
                  onPressed!();
                },
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize:
                  fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 10),
                ],
                Text(
                  label.toUpperCase(),
                  style: AppTypography.h3.copyWith(
                    fontSize: fontSize,
                    color: fg,
                    letterSpacing: 2.5,
                    height: 1,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
