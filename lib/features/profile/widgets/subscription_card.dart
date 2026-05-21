import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Subscription status card.
///
/// Free users: shows upgrade CTA with pricing.
/// PRO users: shows current plan + expiry date + "Manage Subscription".
class SubscriptionCard extends StatelessWidget {
  final bool isPro;
  final String? plan;
  final DateTime? expiresAt;
  final VoidCallback onUpgradeTap;
  final VoidCallback? onManageTap;

  const SubscriptionCard({
    super.key,
    required this.isPro,
    this.plan,
    this.expiresAt,
    required this.onUpgradeTap,
    this.onManageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(
          color: isPro
              ? AppColors.proGold.withValues(alpha: 0.3)
              : AppColors.accent.withValues(alpha: 0.2),
        ),
        gradient: isPro
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1a1408),
                  Color(0xFF0e1219),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0a1628),
                  Color(0xFF0e1219),
                ],
              ),
      ),
      child: isPro ? _buildProContent() : _buildFreeContent(),
    );
  }

  Widget _buildProContent() {
    final planStr = plan == 'yearly' ? 'Yearly' : 'Monthly';
    final expiryStr = expiresAt != null ? _formatDate(expiresAt!) : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.proGold,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Text(
                'PRO',
                style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Colors.black),
              ),
            ),
            const Spacer(),
            Text(
              '$planStr Plan',
              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.proGold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'You have full access to all features',
          style: AppTypography.bodyM.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Renews on $expiryStr',
          style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
        ),
        if (onManageTap != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onManageTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.proGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.proGold.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  'Manage Subscription',
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.proGold),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFreeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.workspace_premium,
              color: AppColors.accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Unlock PRO Features',
              style: AppTypography.bodyL.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'AI coaching, progress photos, advanced plans, and more.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 14),

        // Pricing row
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      '\u20B9${AppConstants.monthlyPriceInr}',
                      style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                    ),
                    Text(
                      '/month',
                      style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '\u20B9${AppConstants.yearlyPriceInr}',
                      style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                    ),
                    Text(
                      '/year \u00B7 Save 17%',
                      style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // CTA
        GestureDetector(
          onTap: onUpgradeTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Center(
              child: Text(
                'Upgrade to PRO',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
