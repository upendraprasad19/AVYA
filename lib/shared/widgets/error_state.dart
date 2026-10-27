import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Reusable error-state placeholder with retry action.
///
/// Ported to Wardroom: inset card, warn-tinted glyph, Fraunces title,
/// DM Sans body, sharp outlined RETRY slab in Mono caps.
class ErrorState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.subtitle = 'Tap to retry',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return WardCard(
      variant: WardCardVariant.inset,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.stackXL,
      ),
      onTap: onRetry,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.bad, size: 44),
          const SizedBox(height: AppSpacing.stackM),
          Text(
            title,
            style: AppTypography.h3,
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.stackXS),
            Text(
              subtitle!,
              style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.stackL),
            SizedBox(
              width: 140,
              child: WardButton(
                label: 'RETRY',
                onPressed: onRetry,
                variant: WardButtonVariant.outline,
                size: WardButtonSize.small,
                fullWidth: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
