import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

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

class PaywallSheet extends ConsumerStatefulWidget {
  final String feature;

  const PaywallSheet({super.key, required this.feature});

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  String _selectedPlan = 'yearly';
  bool _isProcessing = false;

  // Promo code state
  final TextEditingController _promoController = TextEditingController();
  bool _promoValidating = false;
  bool _promoApplied = false;
  int _promoDiscountPct = 0;
  String? _promoError;

  // Audit 2026-05-12 P2-C — paywall funnel events. `_upgradeTapped`
  // distinguishes "user closed without action" from "user tapped upgrade
  // (paywall_upgrade_tapped already fired in _handleUpgrade)".
  bool _upgradeTapped = false;

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
        return 'You crushed Phase 1. Unlock progressive phases to keep building strength and muscle.';
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
      case 'Photo Analysis':
        return 'Send photos to your AI coach for instant meal analysis, form checks, and more.';
      default:
        return 'Upgrade to PRO and unlock your full potential.';
    }
  }

  @override
  void initState() {
    super.initState();
    // Audit 2026-05-12 P2-C — funnel event 1/3. Logs the feature gate
    // that surfaced the paywall so conversion analytics can attribute
    // upgrade taps to specific PRO features.
    unawaited(ErrorTelemetry.logEvent(
      'paywall_shown',
      message: 'feature=${widget.feature}',
    ));
  }

  @override
  void dispose() {
    _promoController.dispose();
    // Audit 2026-05-12 P2-C — funnel event 3/3. Fires only when the user
    // closed the sheet WITHOUT tapping UPGRADE TO PRO. Distinguishes
    // "dismiss" (didn't convert) from "upgrade tap in flight" (still
    // converting via Razorpay WebView).
    if (!_upgradeTapped) {
      unawaited(ErrorTelemetry.logEvent(
        'paywall_dismissed',
        message: 'feature=${widget.feature}',
      ));
    }
    super.dispose();
  }

  /// Validate promo code via the validate-promo Edge Function.
  Future<void> _validatePromoCode() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _promoValidating = true;
      _promoError = null;
      _promoApplied = false;
      _promoDiscountPct = 0;
    });

    try {
      final response = await SupabaseService.instance.client.functions
          .invoke('validate-promo', body: {'code': code});

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        setState(() {
          _promoError = 'Unable to validate code';
          _promoValidating = false;
        });
        return;
      }

      if (data['valid'] == true) {
        setState(() {
          _promoApplied = true;
          _promoDiscountPct = (data['discount_pct'] as num).toInt();
          _promoError = null;
          _promoValidating = false;
        });
      } else {
        setState(() {
          _promoError = data['reason'] as String? ?? 'Invalid code';
          _promoApplied = false;
          _promoValidating = false;
        });
      }
    } catch (e) {
      setState(() {
        _promoError = 'Network error. Try again.';
        _promoValidating = false;
      });
    }
  }

  /// Discounted charge in **paise**, computed byte-for-byte the way the
  /// server does it in `create-razorpay-order`:
  ///   amountPaise = Math.round(basePaise * (100 - discountPct) / 100)
  /// (in-sync sweep 2026-06-07 / F35). Rounding at paise granularity here —
  /// not at rupee granularity — is what keeps the displayed price equal to the
  /// amount Razorpay is actually asked to charge. The old helper rounded in
  /// whole rupees, so e.g. ₹349 @ 15% displayed ₹297 while the server charged
  /// 29 665 paise (₹296.65).
  int _discountedPaise(int basePrice) {
    final basePaise = basePrice * 100;
    if (!_promoApplied || _promoDiscountPct <= 0) return basePaise;
    return (basePaise * (100 - _promoDiscountPct) / 100).round();
  }

  /// Discounted price in whole rupees, derived from the server-consistent
  /// paise figure (used for the coarse `monthlyCostOfYearly` / `savingsPercent`
  /// derivations where sub-rupee precision is immaterial). The user-facing
  /// price label uses [_formatPriceFromPaise] so it shows the exact charge.
  int _discountedPrice(int basePrice) => (_discountedPaise(basePrice) / 100).round();

  Future<void> _handleUpgrade() async {
    if (_isProcessing) return;

    // Audit 2026-05-12 P2-C — funnel event 2/3. Fires the moment the user
    // taps the UPGRADE TO PRO button, BEFORE Razorpay/network. Captures
    // intent independent of whether the payment ultimately succeeds.
    _upgradeTapped = true;
    unawaited(ErrorTelemetry.logEvent(
      'paywall_upgrade_tapped',
      message: 'feature=${widget.feature} plan=$_selectedPlan'
          '${_promoApplied ? " promo_pct=$_promoDiscountPct" : ""}',
    ));

    if (kIsWeb) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payments are only available in the mobile app. Download ICANBEFITTER to upgrade.',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.card,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    // Brief pause so the spinner is visible before Razorpay opens
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    Navigator.of(context).pop();
    // openCheckout is now async (waits for server-side order creation).
    // Fire-and-forget — the paywall sheet is dismissed above, and Razorpay
    // SDK callbacks fire from its own channel (not this future).
    // A7 / B5 D9-D10 — canonical provider path.
    unawaited(ref.read(razorpayServiceProvider).openCheckout(
      plan: _selectedPlan,
      promoCode: _promoApplied ? _promoController.text.trim() : null,
      discountPct: _promoApplied ? _promoDiscountPct : null,
      onSuccess: () {
        // PRO activated optimistically by RazorpayService._handlePaymentSuccess;
        // background confirmation happens automatically.
      },
      onFailure: () {
        // Payment failed or order creation failed — user can retry from any
        // PRO feature tap. RazorpayService already showed an appropriate
        // error snackbar.
      },
    ));
  }

  Future<void> _handleRestore() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // A7 / B5 D9-D10 — canonical provider path.
      await ref.read(subscriptionServiceProvider).refreshFromSupabase();
      if (!mounted) return;
      Navigator.of(context).pop();
      final isPro = ref.read(subscriptionServiceProvider).isPro();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPro
                ? 'PRO restored successfully'
                : 'No active subscription found. Contact support if this is wrong.',
            style: AppTypography.bodySm,
          ),
          backgroundColor: isPro ? AppColors.ok : AppColors.card,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[PaywallSheet._handleRestore] $e');
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('paywall_restore_purchase_failed',
          message: clipped));
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not verify purchase. Check your connection and try again.',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format prices from AppConstants (never hardcode)
    final monthlyBase = AppConstants.monthlyPriceInr;
    final yearlyBase = AppConstants.yearlyPriceInr;
    final monthlyFinal = _discountedPrice(monthlyBase);
    final yearlyFinal = _discountedPrice(yearlyBase);

    // Display labels are derived from the server-consistent paise figure so the
    // shown price equals what Razorpay charges (in-sync sweep / F35). Shows
    // paise only when a promo produces a fractional rupee; whole-rupee prices
    // render exactly as before.
    final monthlyPrice = _formatPriceFromPaise(_discountedPaise(monthlyBase));
    final yearlyPrice = _formatPriceFromPaise(_discountedPaise(yearlyBase));
    final monthlyCostOfYearly = (yearlyFinal / 12).round();
    final savingsPercent = (((monthlyFinal * 12 - yearlyFinal) /
                (monthlyFinal * 12)) *
            100)
        .round();

    return Container(
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
              // Drag handle
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

              // Hero letterhead
              WardLetterhead(
                eyebrow: 'GO PRO',
                title: '${widget.feature} is a PRO feature',
                divider: false,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.stackS),
              const WardRule(gold: true, margin: EdgeInsets.zero),
              const SizedBox(height: AppSpacing.stackM),

              // Subtitle
              Text(
                _featureSubtitle,
                style: AppTypography.body.copyWith(
                  color: AppColors.textDim,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.stackL),

              // Benefits list
              WardCard(
                variant: WardCardVariant.inset,
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WHAT YOU UNLOCK',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.stackS),
                    ..._proBenefits.map(
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

              // Pricing cards — annual pre-selected
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPlan = 'monthly'),
                      child: _PricingCard(
                        label: 'MONTHLY',
                        price: monthlyPrice,
                        period: 'PER MONTH',
                        isSelected: _selectedPlan == 'monthly',
                        originalPrice:
                            _promoApplied ? _formatPrice(monthlyBase) : null,
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
                        period: 'PER YEAR',
                        isSelected: _selectedPlan == 'yearly',
                        savings: 'SAVE $savingsPercent%',
                        subtitle: '\u20B9$monthlyCostOfYearly/mo',
                        originalPrice:
                            _promoApplied ? _formatPrice(yearlyBase) : null,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.stackM),

              // Promo code input
              _buildPromoCodeSection(),

              const SizedBox(height: AppSpacing.stackM),

              // CTA button
              WardButton(
                label: _isProcessing ? '...' : 'UPGRADE TO PRO',
                onPressed: _isProcessing ? null : _handleUpgrade,
                variant: WardButtonVariant.primary,
                fullWidth: true,
              ),

              const SizedBox(height: AppSpacing.stackS),

              // Dismiss + Restore row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'MAYBE LATER',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Text(
                    '·',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textGhost,
                    ),
                  ),
                  TextButton(
                    onPressed: _isProcessing ? null : _handleRestore,
                    child: Text(
                      'RESTORE',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the promo code input field with Apply button + status.
  Widget _buildPromoCodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  border: Border.all(
                    color: _promoApplied
                        ? AppColors.ok.withValues(alpha: 0.45)
                        : _promoError != null
                            ? AppColors.bad.withValues(alpha: 0.45)
                            : AppColors.line2,
                    width: 2,
                  ),
                ),
                child: TextField(
                  controller: _promoController,
                  enabled: !_promoApplied && !_promoValidating,
                  textCapitalization: TextCapitalization.characters,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                  decoration: InputDecoration(
                    hintText: 'PROMO CODE',
                    hintStyle: AppTypography.mono.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 2,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.stackS),
            SizedBox(
              height: 40,
              child: _promoValidating
                  ? const SizedBox(
                      width: 40,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    )
                  : WardButton(
                      label: _promoApplied ? 'APPLIED' : 'APPLY',
                      onPressed:
                          _promoApplied ? null : _validatePromoCode,
                      variant: _promoApplied
                          ? WardButtonVariant.ghost
                          : WardButtonVariant.outline,
                      size: WardButtonSize.small,
                      fullWidth: false,
                    ),
            ),
          ],
        ),

        // Status message
        if (_promoApplied)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 14, color: AppColors.ok),
                const SizedBox(width: 4),
                Text(
                  '$_promoDiscountPct% off applied',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.ok,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        if (_promoError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _promoError!,
              style: AppTypography.bodySm.copyWith(color: AppColors.bad),
            ),
          ),
      ],
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

  /// Format a paise amount as an Indian-rupee price string, matching exactly
  /// what `create-razorpay-order` will charge (in-sync sweep / F35). Whole
  /// rupees render via [_formatPrice] (unchanged, no decimals); a fractional
  /// rupee from a promo shows two-decimal paise (e.g. 29 665 paise → "296.65").
  static String _formatPriceFromPaise(int paise) {
    final rupees = paise ~/ 100;
    final paiseRem = paise % 100;
    final whole = _formatPrice(rupees);
    if (paiseRem == 0) return whole;
    return '$whole.${paiseRem.toString().padLeft(2, '0')}';
  }
}

class _PricingCard extends StatelessWidget {
  final String label;
  final String price;
  final String period;
  final bool isSelected;
  final String? savings;
  final String? subtitle;
  final String? originalPrice;

  const _PricingCard({
    required this.label,
    required this.price,
    required this.period,
    required this.isSelected,
    this.savings,
    this.subtitle,
    this.originalPrice,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accentSoft : AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(
          color: isSelected ? AppColors.accent : AppColors.line2,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          if (savings != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                savings!,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.bgDeep,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          Text(
            label,
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          if (originalPrice != null) ...[
            Text(
              '\u20B9$originalPrice',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textMute,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.textMute,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '\u20B9',
                style: AppTypography.h3.copyWith(
                  fontSize: 16,
                  color: originalPrice != null
                      ? AppColors.ok
                      : AppColors.textPrimary,
                ),
              ),
              Text(
                price,
                style: AppTypography.h1.copyWith(
                  fontSize: 28,
                  color: originalPrice != null
                      ? AppColors.ok
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            period,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textMute,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
