import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

/// Handles Razorpay checkout flow:
///   1. Open Razorpay WebView checkout (₹349/month or ₹2,999/year)
///   2. On success → poll Supabase for webhook confirmation
///   3. Update Hive configBox → PRO features unlock immediately
///
/// Pricing: ₹349/month or ₹2,999/year (annual pre-selected, "Save 28%").
/// Never hardcode prices here — sourced from AppConstants.
class RazorpayService {
  RazorpayService._();
  static final RazorpayService _instance = RazorpayService._();
  static RazorpayService get instance => _instance;

  Razorpay? _razorpay;
  VoidCallback? _onSuccess;
  VoidCallback? _onFailure;
  String? _pendingPlan;

  /// Global navigator key for showing snackbars after checkout.
  static GlobalKey<NavigatorState>? navigatorKey;

  void initialize() {
    if (kIsWeb) return;
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void dispose() {
    if (kIsWeb) return;
    _razorpay?.clear();
  }

  /// Opens the Razorpay checkout for the given [plan] ("monthly" or "yearly").
  ///
  /// Annual plan is pre-selected in PaywallSheet, showing "Save 28%".
  /// Optional [promoCode] and [discountPct] apply a discount to the amount.
  void openCheckout({
    required String plan,
    String? promoCode,
    int? discountPct,
    VoidCallback? onSuccess,
    VoidCallback? onFailure,
  }) {
    final keyId = AppConstants.razorpayKeyId;
    if (keyId.isEmpty || keyId.contains('REPLACE')) {
      debugPrint('RazorpayService: invalid key ID — aborting checkout');
      onFailure?.call();
      return;
    }

    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _pendingPlan = plan;

    int baseAmount = plan == 'yearly'
        ? AppConstants.yearlyPriceInr
        : AppConstants.monthlyPriceInr;

    // Apply promo discount if provided.
    if (promoCode != null && discountPct != null && discountPct > 0) {
      baseAmount = (baseAmount * (100 - discountPct) / 100).round();
    }

    final amount = baseAmount * 100; // Razorpay expects paise
    debugPrint('RazorpayService: opening checkout — plan=$plan, amount=$amount paise, key=${keyId.substring(0, 12)}...');

    final user = SupabaseService.instance.currentUser;

    final notes = <String, String>{
      'user_id': user?.id ?? '',
      'plan': plan,
    };

    if (promoCode != null) {
      notes['promo_code'] = promoCode;
    }

    final options = {
      'key': AppConstants.razorpayKeyId,
      'amount': amount,
      'name': AppConstants.appName,
      'description': 'PRO ${plan == 'yearly' ? 'Yearly' : 'Monthly'} Plan',
      'currency': 'INR',
      'prefill': {
        'email': user?.email ?? '',
      },
      'notes': notes,
      'theme': {
        'color': '#00D4FF',
      },
    };

    if (kIsWeb) return;
    _razorpay?.open(options);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('RazorpayService: payment success — paymentId=${response.paymentId}, orderId=${response.orderId}');

    // Show "verifying" snackbar immediately so user isn't staring at nothing
    final ctx = navigatorKey?.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                'Verifying payment...',
                style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0e1219),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 15),
        ),
      );
    }

    await _pollAndActivate(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );

    // Clear the "verifying" snackbar before showing success
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).clearSnackBars();
    }

    _onSuccess?.call();
    _showProActivatedFeedback();
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('RazorpayService: payment error — code=${response.code}, message=${response.message}');
    _onFailure?.call();
    final context = navigatorKey?.currentContext;
    if (context == null) return;
    final msg = response.message ?? 'Payment failed';
    // Only show error if it's not a user cancellation
    if (response.code != Razorpay.PAYMENT_CANCELLED) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment failed: $msg',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13),
          ),
          backgroundColor: const Color(0xFF2a1a1a),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // External wallet selected — treat as pending, do nothing.
  }

  /// Shows a success snackbar and invalidates subscription providers
  /// using the global navigator key. Safe to call after the paywall
  /// sheet has been dismissed.
  void _showProActivatedFeedback() {
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    // Invalidate subscription provider so UI updates immediately
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(subscriptionInfoProvider);
    } catch (_) {}

    // Show success snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 18),
            const SizedBox(width: 10),
            Text(
              'PRO activated! Welcome to AVYA PRO',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1a2a1a),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Computes a valid end date for a plan, used when webhook row has
  /// no end_date or as fallback when polling exhausts.
  String _computeEndDate(String plan) {
    final end = plan == 'yearly'
        ? DateTime.now().add(const Duration(days: 365))
        : DateTime.now().add(const Duration(days: 30));
    return end.toIso8601String();
  }

  /// Polls Supabase subscriptions table for confirmation from the
  /// razorpay-webhook Edge Function.
  ///
  /// Uses exponential backoff: 2s → 3s → 4s (15 attempts, ~45s total).
  /// On exhaustion, calls verify-payment Edge Function as final check
  /// before falling back to local-only activation.
  Future<void> _pollAndActivate({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return;

    final hive = HiveService.instance;
    final fallbackPlan = _pendingPlan ?? 'monthly';

    // Phase 1: Poll Supabase with exponential backoff (15 attempts)
    for (int attempt = 0; attempt < 15; attempt++) {
      // Exponential backoff: 2s for first 5, 3s for next 5, 4s for last 5
      final delay = attempt < 5 ? 2 : (attempt < 10 ? 3 : 4);
      await Future.delayed(Duration(seconds: delay));

      try {
        final row = await SupabaseService.instance.client
            .from('subscriptions')
            .select()
            .eq('user_id', userId)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (row != null) {
          // Accept any active subscription — don't require exact payment_id match
          // because webhook timing may differ from poll timing
          final endDate = row['end_date'] as String?;
          final plan = row['plan'] as String? ?? fallbackPlan;

          await hive.configBox.put('isPro', true);
          await hive.configBox.put('expiresAt',
              (endDate != null && endDate.isNotEmpty) ? endDate : _computeEndDate(plan));
          await hive.configBox.put('plan', plan);
          debugPrint('RazorpayService: webhook confirmed at attempt $attempt');
          return;
        }
      } catch (e) {
        debugPrint('RazorpayService: poll attempt $attempt failed: $e');
      }
    }

    // Phase 2: Direct verification via Edge Function (server checks Razorpay API)
    if (paymentId.isNotEmpty) {
      try {
        debugPrint('RazorpayService: polling exhausted, trying verify-payment Edge Function...');
        final verifyResponse = await SupabaseService.instance.callFunction(
          'verify-payment',
          body: {
            'payment_id': paymentId,
            'plan': fallbackPlan,
          },
        );

        if (verifyResponse.status == 200 && verifyResponse.data != null) {
          final data = verifyResponse.data is Map
              ? verifyResponse.data as Map<String, dynamic>
              : <String, dynamic>{};
          if (data['verified'] == true) {
            final endDate = data['end_date'] as String?;
            final plan = data['plan'] as String? ?? fallbackPlan;
            await hive.configBox.put('isPro', true);
            await hive.configBox.put('expiresAt',
                (endDate != null && endDate.isNotEmpty) ? endDate : _computeEndDate(plan));
            await hive.configBox.put('plan', plan);
            debugPrint('RazorpayService: verified via Edge Function');
            return;
          }
        }
      } catch (e) {
        debugPrint('RazorpayService: verify-payment Edge Function failed: $e');
      }
    }

    // Phase 3: Local-only fallback — activate PRO so user isn't stuck.
    // Next app launch will re-verify via SubscriptionService.refreshFromSupabase().
    debugPrint('RazorpayService: all verification exhausted — activating local fallback for plan=$fallbackPlan');
    await hive.configBox.put('isPro', true);
    await hive.configBox.put('expiresAt', _computeEndDate(fallbackPlan));
    await hive.configBox.put('plan', fallbackPlan);

    // Queue delayed re-checks in case webhook arrives late
    Future.delayed(const Duration(seconds: 60), () {
      SubscriptionService.instance.refreshFromSupabase();
    });
    Future.delayed(const Duration(minutes: 5), () {
      SubscriptionService.instance.refreshFromSupabase();
    });
  }
}
