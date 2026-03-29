import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';

/// Shows the single, reusable paywall bottom sheet.
///
/// This is the ONLY paywall UI in the app. Never create custom paywall modals.
///
/// Usage:
/// ```dart
/// showPaywallSheet(context, feature: 'AI Food Analysis');
/// ```
void showPaywallSheet(BuildContext context, {required String feature}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    transitionAnimationController: AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 350),
    ),
    builder: (_) => PaywallSheet(feature: feature),
  );
}

class PaywallSheet extends StatefulWidget {
  final String feature;

  const PaywallSheet({super.key, required this.feature});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  String _selectedPlan = 'yearly';
  bool _isProcessing = false;

  static const List<String> _proBenefits = [
    'Unlimited AI Coach with deep personalised coaching',
    'AI food analysis & meal scanning (camera)',
    'Generate new plans after Week 4 (phases 2-12)',
    'Weekly AI nutrition report + Telegram push',
    'Progress photos & body composition tracking',
    'Reasoning tab for advanced coaching',
    'PRO tips on every exercise',
    'Diet plan PDF download',
    'Adjustable food portions',
  ];

  /// Feature-specific compelling copy for the paywall subtitle.
  String get _featureSubtitle {
    switch (widget.feature) {
      case 'Phases 2-12':
        return 'You crushed Phase 1! Unlock progressive phases to keep building strength and muscle.';
      case 'Unlimited AI Coach':
        return 'Get unlimited coaching conversations with deep personalised insights.';
      case 'Deep Analysis':
        return 'Unlock advanced reasoning for detailed workout and nutrition analysis.';
      case 'Scan Meal':
        return 'Snap a photo of your plate and get instant macro breakdown.';
      case 'Cart Auditor':
        return 'Audit your grocery cart for macro-friendly swaps and better nutrition.';
      case 'AI Food Analysis':
        return 'Let AI analyse what you ate and log it instantly with accurate macros.';
      case 'Voice Notes':
        return 'Just talk to your coach \u2014 push-to-talk voice input for hands-free logging.';
      case 'Monthly Prediction':
        return 'Get an updated AI prediction of your fitness progress every month.';
      case 'Weekly AI Report':
        return 'Receive detailed weekly nutrition insights powered by AI.';
      case 'Progress Photos':
        return 'Track your body transformation with a visual photo timeline.';
      case 'Morning Alert':
        return 'Wake up to AI-personalised motivation and daily plan reminders.';
      default:
        return 'Upgrade to PRO and unlock your full potential.';
    }
  }

  void _handleUpgrade() {
    if (_isProcessing) return;

    if (kIsWeb) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payments are only available in the mobile app. Download ICANBEFITTER to upgrade.',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13),
          ),
          backgroundColor: const Color(0xFF0e1219),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    Navigator.of(context).pop();
    RazorpayService.instance.openCheckout(
      plan: _selectedPlan,
      onSuccess: () {
        // PRO activated via RazorpayService polling
      },
      onFailure: () {
        // Payment failed — user can retry from any PRO feature tap
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Format prices from AppConstants (never hardcode)
    final monthlyPrice = _formatPrice(AppConstants.monthlyPriceInr);
    final yearlyPrice = _formatPrice(AppConstants.yearlyPriceInr);
    final monthlyCostOfYearly =
        (AppConstants.yearlyPriceInr / 12).round();
    final savingsPercent = (((AppConstants.monthlyPriceInr * 12 -
                    AppConstants.yearlyPriceInr) /
                (AppConstants.monthlyPriceInr * 12)) *
            100)
        .round();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.cardL),
        ),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Lock icon + feature name
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.proGoldTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: AppColors.proGold,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.feature} is a PRO feature',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _featureSubtitle,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),

            // Benefits list
            Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.cardM),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: _proBenefits
                    .map((benefit) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.accent,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  benefit,
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 20),

            // Pricing cards — annual pre-selected
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPlan = 'monthly'),
                    child: _PricingCard(
                      label: 'MONTHLY',
                      price: monthlyPrice,
                      period: '/month',
                      isSelected: _selectedPlan == 'monthly',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPlan = 'yearly'),
                    child: _PricingCard(
                      label: 'YEARLY',
                      price: yearlyPrice,
                      period: '/year',
                      isSelected: _selectedPlan == 'yearly',
                      savings: 'Save $savingsPercent%',
                      subtitle:
                          '\u20B9$monthlyCostOfYearly/mo',
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // CTA button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _handleUpgrade,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.textDisabled,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  elevation: 4,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        'Upgrade to PRO',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 10),

            // Dismiss link
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Maybe later',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format price with thousands separator for Indian rupees.
  static String _formatPrice(int price) {
    if (price >= 1000) {
      final thousands = price ~/ 1000;
      final remainder = price % 1000;
      if (remainder == 0) return '$thousands,000';
      return '$thousands,${remainder.toString().padLeft(3, '0')}';
    }
    return '$price';
  }
}

class _PricingCard extends StatelessWidget {
  final String label;
  final String price;
  final String period;
  final bool isSelected;
  final String? savings;
  final String? subtitle;

  const _PricingCard({
    required this.label,
    required this.price,
    required this.period,
    required this.isSelected,
    this.savings,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accentTint : AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        border: Border.all(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.3)
              : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          if (savings != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.proGold,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Text(
                savings!,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
          Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '\u20B9',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                price,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                period,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
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
    );
  }
}
