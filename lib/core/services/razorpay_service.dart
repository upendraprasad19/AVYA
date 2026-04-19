import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

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
  /// Flow (fix from the 2026-04-17 stuck-at-authorized bug):
  ///   1. Call our `create-razorpay-order` Edge Function server-side
  ///      to create the Razorpay Order with `payment_capture: 1`.
  ///      This guarantees auto-capture on authorization — the order-less
  ///      checkout path used previously would occasionally leave UPI /
  ///      wallet payments stuck in `authorized` status because Razorpay
  ///      was waiting for an explicit /capture call that never came.
  ///   2. Open Razorpay WebView with the server-created `order_id`.
  ///   3. On PAYMENT_SUCCESS → poll Supabase for webhook confirmation.
  ///
  /// Annual plan is pre-selected in PaywallSheet, showing "Save 28%".
  /// Optional [promoCode] and [discountPct] apply a discount to the amount.
  Future<void> openCheckout({
    required String plan,
    String? promoCode,
    int? discountPct,
    VoidCallback? onSuccess,
    VoidCallback? onFailure,
  }) async {
    final keyId = AppConstants.razorpayKeyId;
    if (keyId.isEmpty || keyId.contains('REPLACE')) {
      debugPrint('RazorpayService: invalid key ID — aborting checkout');
      onFailure?.call();
      return;
    }

    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _pendingPlan = plan;

    final user = SupabaseService.instance.currentUser;
    if (user == null) {
      debugPrint('RazorpayService: no user — aborting checkout');
      onFailure?.call();
      return;
    }

    // Step 1 — create server-side order. Derives price + promo server-side
    // (client never dictates amount), returns order_id + key_id.
    int amountPaise = 0;
    String? orderId;
    try {
      final resp = await SupabaseService.instance.callFunction(
        'create-razorpay-order',
        body: {
          'plan': plan,
          if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
        },
      );

      if (resp.status != 200 || resp.data == null) {
        debugPrint('RazorpayService: create-razorpay-order failed '
            'status=${resp.status} data=${resp.data}');
        _showOrderCreationFailure();
        onFailure?.call();
        return;
      }

      final data = resp.data is Map
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      orderId = data['order_id'] as String?;
      amountPaise = (data['amount'] as num?)?.toInt() ?? 0;

      if (orderId == null || orderId.isEmpty || amountPaise == 0) {
        debugPrint('RazorpayService: order response missing fields: $data');
        _showOrderCreationFailure();
        onFailure?.call();
        return;
      }
    } catch (e) {
      debugPrint('RazorpayService: create-razorpay-order threw: $e');
      _showOrderCreationFailure();
      onFailure?.call();
      return;
    }

    debugPrint('RazorpayService: opening checkout — plan=$plan, '
        'order_id=$orderId, amount=$amountPaise paise');

    // Step 2 — open Razorpay checkout with the server-created order.
    // Passing `order_id` ensures Razorpay uses the order's
    // `payment_capture: 1` flag → payment is captured automatically
    // the instant it's authorized. No more stuck-at-authorized bug.
    final notes = <String, String>{
      'user_id': user.id,
      'plan': plan,
    };
    if (promoCode != null && promoCode.isNotEmpty) {
      notes['promo_code'] = promoCode;
    }

    final options = {
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'name': AppConstants.appName,
      'description': 'PRO ${plan == 'yearly' ? 'Yearly' : 'Monthly'} Plan',
      'currency': 'INR',
      'prefill': {
        'email': user.email ?? '',
      },
      'notes': notes,
      'theme': {
        'color': '#D4B270',
      },
    };

    if (kIsWeb) return;
    _razorpay?.open(options);
  }

  /// Shows a non-blocking snackbar when server-side order creation fails
  /// before Razorpay checkout even opens. The user hasn't paid yet, so
  /// this is a recoverable "try again" state.
  void _showOrderCreationFailure() {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          'Couldn\'t start payment. Check your connection and try again.',
          style: AppTypography.bodySm.copyWith(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2a1a1a),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('RazorpayService: payment success — paymentId=${response.paymentId}, orderId=${response.orderId}');

    // Capture ScaffoldMessenger BEFORE any awaits to avoid
    // use_build_context_synchronously lint.
    final ctx = navigatorKey?.currentContext;
    final messenger = ctx != null ? ScaffoldMessenger.maybeOf(ctx) : null;

    // Force-refresh Supabase JWT. The app was backgrounded during Razorpay
    // WebView checkout, so the access token may have expired. Without this,
    // subsequent Edge Function calls (AI chat, food analysis) fail with 401.
    try {
      await SupabaseService.instance.client.auth.refreshSession();
      debugPrint('RazorpayService: session refreshed after checkout');
    } catch (e) {
      debugPrint('RazorpayService: session refresh failed (non-fatal): $e');
    }

    // Fix 2 (2026-04-17) · OPTIMISTIC LOCAL ACTIVATION.
    //
    // Activate PRO in Hive IMMEDIATELY — the user sees the PRO badge the
    // instant Razorpay says the payment succeeded. Server-side confirmation
    // happens in the background via _pollAndActivate. Even if polling and
    // verify-payment both fail, we already have:
    //   - Hive `isPro=true` + `localActivationAt` timestamp (grace period)
    //   - SubscriptionService.gate() server-verifies high-value features
    //     so a compromised local state still can't unlock paid content
    //     (see CLAUDE.md §10 — verifyFromServer cache TTL 5 min).
    //
    // Before this fix, if Phase 1 polling + Phase 2 verify both failed or
    // threw, the Phase 3 local fallback was ALSO skipped (it lived at the
    // end of _pollAndActivate) — leaving the user stuck without PRO even
    // though their payment went through. Now Phase 3 runs first + poll
    // confirms it afterwards.
    final fallbackPlan = _pendingPlan ?? 'monthly';
    final optimisticEndDate = _computeEndDate(fallbackPlan);
    try {
      await SubscriptionService.instance.writeSubscriptionState(
        isPro: true,
        expiresAt: optimisticEndDate,
        plan: fallbackPlan,
      );
      await HiveService.instance.configBox.put(
        'localActivationAt',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('RazorpayService: optimistic activation write failed: $e');
    }

    // Announce PRO to the user right away — no more 45s "Verifying..." wait.
    _showProActivatedFeedback();
    _onSuccess?.call();

    // Background confirmation. Wrapped in try/catch so Razorpay's success
    // callback thread never throws an unhandled exception that kills the
    // whole payment path.
    try {
      await _pollAndActivate(
        paymentId: response.paymentId ?? '',
        orderId: response.orderId ?? '',
        signature: response.signature ?? '',
      );
    } catch (e) {
      debugPrint('RazorpayService: _pollAndActivate threw: $e');
      // Local state is already PRO; background verify retries will keep
      // trying via _scheduleVerificationRetry inside _pollAndActivate's
      // normal flow, or via refreshFromSupabase on next app launch.
    }

    // Clear any leftover "Verifying" snackbar (safety — we no longer show
    // one on this path, but legacy callers might).
    messenger?.clearSnackBars();
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
            style: AppTypography.bodySm.copyWith(color: Colors.white),
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

    // Invalidate subscription + trial providers so every tab's PRO-gated
    // UI rebuilds the moment the user returns from Razorpay.
    //
    // The widget-side fix (2026-04-18) switched AI coach + nutrition
    // tiles from direct SubscriptionService.isPro() calls to
    // ref.watch(subscriptionInfoProvider).isPro, so invalidating
    // subscriptionInfoProvider cascades into those rebuilds.
    //
    // Trial + message-limit providers cache free-tier counters; PRO
    // users shouldn't see those at all, so invalidate them too to
    // avoid a stale "15 msgs left today" sliver on the AI coach screen.
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(subscriptionInfoProvider);
      container.invalidate(trialInfoProvider);
      container.invalidate(messageLimitProvider);
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
              style: AppTypography.bodySm.copyWith(
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

    final fallbackPlan = _pendingPlan ?? 'monthly';

    // Phase 1: Poll Supabase with exponential backoff (15 attempts).
    // Attempts 0-11: exact match on razorpay_payment_id (this specific payment).
    // Attempts 12-14: fall back to any active row created in last 5 minutes.
    for (int attempt = 0; attempt < 15; attempt++) {
      final delay = attempt < 5 ? 2 : (attempt < 10 ? 3 : 4);
      await Future.delayed(Duration(seconds: delay));

      try {
        Map<String, dynamic>? row;

        if (attempt < 12) {
          // Exact match: only accept the subscription created by THIS payment
          row = await SupabaseService.instance.client
              .from('subscriptions')
              .select()
              .eq('user_id', userId)
              .eq('razorpay_payment_id', paymentId)
              .eq('status', 'active')
              .maybeSingle();
        } else {
          // Fallback: any active subscription for THIS PLAN created in the
          // last 5 minutes. Plan filter is the critical safety rail:
          // without it, a monthly→yearly upgrade could match the stale
          // monthly row created minutes ago, granting 30 days instead of
          // 365. The plan column on `subscriptions` is set by the webhook
          // from `payment.amount_paise` (never trusted from client).
          final cutoff = DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String();
          row = await SupabaseService.instance.client
              .from('subscriptions')
              .select()
              .eq('user_id', userId)
              .eq('status', 'active')
              .eq('plan', fallbackPlan)
              .gte('created_at', cutoff)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        }

        if (row != null) {
          final endDate = row['end_date'] as String?;
          final plan = row['plan'] as String? ?? fallbackPlan;

          await SubscriptionService.instance.writeSubscriptionState(
            isPro: true,
            expiresAt: (endDate != null && endDate.isNotEmpty) ? endDate : _computeEndDate(plan),
            plan: plan,
          );
          debugPrint('RazorpayService: webhook confirmed at attempt $attempt (exact=${attempt < 12})');
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
            await SubscriptionService.instance.writeSubscriptionState(
              isPro: true,
              expiresAt: (endDate != null && endDate.isNotEmpty) ? endDate : _computeEndDate(plan),
              plan: plan,
            );
            debugPrint('RazorpayService: verified via Edge Function');
            return;
          }
        }
      } catch (e) {
        debugPrint('RazorpayService: verify-payment Edge Function failed: $e');
      }
    }

    // Phase 3 was already done optimistically in _handlePaymentSuccess
    // before we were called. All we need to do now is schedule the
    // background verification retries so the server-side row gets written
    // eventually (either by webhook or by verify-payment).
    //
    // If Phase 1 + Phase 2 both failed above, hive still has PRO from the
    // optimistic write. These retries will reconcile when connectivity /
    // Razorpay / webhook recover.
    debugPrint(
      'RazorpayService: Phase 1+2 exhausted — local PRO already active, scheduling background retries');
    _scheduleVerificationRetry(
      paymentId: paymentId,
      orderId: orderId,
      plan: fallbackPlan,
    );

    // Also refresh from Supabase a few times in case the webhook arrives late.
    Future.delayed(const Duration(seconds: 60), () {
      SubscriptionService.instance.refreshFromSupabase();
    });
    Future.delayed(const Duration(minutes: 5), () {
      SubscriptionService.instance.refreshFromSupabase();
    });
  }

  /// Background retry of the verify-payment Edge Function.
  ///
  /// The Edge Function has the Razorpay secret key and validates the
  /// payment server-side via the Razorpay API. On success, it writes
  /// to the Supabase subscriptions table (server-side, with proof).
  ///
  /// 3 attempts at 60s, 5m, 15m. On final failure, does nothing —
  /// existing safety nets reconcile on next app launch.
  void _scheduleVerificationRetry({
    required String paymentId,
    required String orderId,
    required String plan,
  }) {
    const delays = [
      Duration(seconds: 60),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ];

    for (final delay in delays) {
      Future.delayed(delay, () async {
        try {
          // Refresh JWT before retry — the original token from checkout
          // is likely expired (app was backgrounded during Razorpay WebView).
          try {
            await SupabaseService.instance.client.auth.refreshSession();
          } catch (_) {}

          final response = await SupabaseService.instance.callFunction(
            'verify-payment',
            body: {
              'payment_id': paymentId,
              'order_id': orderId,
              'plan': plan,
            },
          );
          if (response.status == 200) {
            // verify-payment returns 200 with verified:false for uncaptured
            // payments, and 200 with verified:true even if the subscription
            // row insert failed. Only trust verified:true.
            final data = response.data is Map
                ? Map<String, dynamic>.from(response.data as Map)
                : <String, dynamic>{};
            if (data['verified'] == true) {
              debugPrint('RazorpayService: verify-payment retry confirmed after ${delay.inSeconds}s');
              await SubscriptionService.instance.refreshFromSupabase();
              await HiveService.instance.configBox.delete('localActivationAt');
              return; // Payment verified server-side — stop retrying
            }
            debugPrint('RazorpayService: verify-payment returned 200 but verified=${data['verified']} — continuing retries');
          }
        } catch (e) {
          debugPrint('RazorpayService: verify-payment retry failed after ${delay.inSeconds}s: $e');
        }
      });
    }
  }
}
