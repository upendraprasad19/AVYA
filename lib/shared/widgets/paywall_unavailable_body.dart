import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// What [PaywallSheet] shows when this binary sells nothing
/// (`PurchaseMode.showsPurchaseUi` is false; ADR-0022, plan section 4).
///
/// Presentation only: the sheet keeps the state and the restore logic and
/// hands this widget its callbacks. It is NOT a second paywall: `PaywallSheet`
/// is still the only entry (CLAUDE.md rule 7), this is its body in one mode.
///
/// No plan card, no price, no promo box, no purchase button, no website.
class PaywallUnavailableBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> benefits;
  final bool isProcessing;
  final VoidCallback onCheckStatus;
  final VoidCallback onClose;

  /// A failure line shown above the button (null = none). Inline on purpose:
  /// a snackbar is drawn behind the modal sheet.
  final String? statusMessage;

  const PaywallUnavailableBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.benefits,
    required this.isProcessing,
    required this.onCheckStatus,
    required this.onClose,
    this.statusMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('paywall-unavailable-body'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
        border: Border(
          top: BorderSide(color: AppColors.line2, width: 1),
          left: BorderSide(color: AppColors.line2, width: 1),
          right: BorderSide(color: AppColors.line2, width: 1),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.stackM,
            AppSpacing.gutter,
            AppSpacing.stackL,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.stackL),
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              WardLetterhead(
                eyebrow: PurchaseCopy.eyebrow,
                title: title,
                divider: false,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.stackS),
              const WardRule(gold: true, margin: EdgeInsets.zero),
              const SizedBox(height: AppSpacing.stackM),
              Text(
                subtitle,
                style: AppTypography.body.copyWith(
                  color: AppColors.textDim,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.stackL),
              WardCard(
                variant: WardCardVariant.inset,
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PurchaseCopy.benefitsLabel,
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.stackS),
                    ...benefits.map(
                      (benefit) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check,
                              color: AppColors.accent,
                              size: 15,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                benefit,
                                style: AppTypography.body.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.stackL),
              WardCard(
                variant: WardCardVariant.inset,
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Text(
                  PurchaseCopy.card,
                  key: const ValueKey('paywall-unavailable-card'),
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
              if (statusMessage != null) ...[
                const SizedBox(height: AppSpacing.stackM),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    statusMessage!,
                    key: const ValueKey('paywall-unavailable-status'),
                    style: AppTypography.bodySm.copyWith(color: AppColors.warn),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.stackM),
              WardButton(
                label: isProcessing ? '...' : PurchaseCopy.checkStatusButton,
                onPressed: isProcessing ? null : onCheckStatus,
                variant: WardButtonVariant.outline,
                fullWidth: true,
              ),
              const SizedBox(height: AppSpacing.stackS),
              TextButton(
                onPressed: onClose,
                child: Text(
                  PurchaseCopy.closeButton,
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
