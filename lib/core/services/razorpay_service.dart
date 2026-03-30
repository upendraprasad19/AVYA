import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

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
    // Poll Supabase for webhook confirmation, then update Hive.
    await _pollAndActivate(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );
    _onSuccess?.call();
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    _onFailure?.call();
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // External wallet selected — treat as pending, do nothing.
  }

  /// Polls Supabase subscriptions table for confirmation from the
  /// razorpay-webhook Edge Function. Retries up to 5 times with 2s delay.
  Future<void> _pollAndActivate({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return;

    final hive = HiveService.instance;

    for (int attempt = 0; attempt < 5; attempt++) {
      await Future.delayed(const Duration(seconds: 2));

      try {
        final row = await SupabaseService.instance.client
            .from('subscriptions')
            .select()
            .eq('user_id', userId)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (row != null && row['razorpay_payment_id'] == paymentId) {
          // Webhook confirmed — activate locally.
          final endDate = row['end_date'] as String?;
          final plan = row['plan'] as String?;

          await hive.configBox.put('isPro', true);
          await hive.configBox.put('expiresAt', endDate ?? '');
          await hive.configBox.put('plan', plan ?? 'monthly');
          return;
        }
      } catch (_) {
        // Network error — retry.
      }
    }

    // Fallback: even if polling fails, optimistically activate for 24h
    // so the user isn't stuck. Next app launch will re-verify via
    // SubscriptionService.refreshFromSupabase().
    final fallbackPlan = _pendingPlan ?? 'monthly';
    await hive.configBox.put('isPro', true);
    await hive.configBox.put(
      'expiresAt',
      DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    );
    await hive.configBox.put('plan', fallbackPlan);
  }
}
