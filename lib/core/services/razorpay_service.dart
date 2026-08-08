import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
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
  RazorpayService._() {
    _registerLifecycle();
  }
  static final RazorpayService _instance = RazorpayService._();

  /// Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) — prefer
  /// `ref.read(razorpayServiceProvider)` over `.instance`. The
  /// singleton path is preserved for non-Riverpod contexts
  /// (main.dart bootstrap).
  @Deprecated(
      'Use ref.read(razorpayServiceProvider) — singleton path will be removed after full migration')
  static RazorpayService get instance => _instance;

  Razorpay? _razorpay;
  VoidCallback? _onSuccess;
  VoidCallback? _onFailure;
  String? _pendingPlan;

  /// Tech-debt audit 2026-05-20 / A7 — register cross-account reset
  /// hook so an abandoned checkout (user signs out mid-payment) does
  /// not fire the previous user's [_onSuccess] / [_onFailure] callback
  /// against the new user's UI state. The Razorpay native SDK instance
  /// is kept (re-used on next [initialize]).
  void _registerLifecycle() {
    SingletonLifecycleRegistry.register('RazorpayService', _onUserChanged);
  }

  /// A7 — invoked from [SingletonLifecycleRegistry.notifyUserChanged].
  /// Drops pending checkout callbacks + plan so the previous user's
  /// in-flight payment cannot dispatch into the new session.
  void _onUserChanged() {
    _onSuccess = null;
    _onFailure = null;
    _pendingPlan = null;
  }

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

      // APK Test #12.2 / Task #6 — handle 409 already_pro from the
      // server-side double-payment guard. Server returns 409 when user
      // already has a non-expired active subscription.
      //
      // APK Test #12.5 / Class 2a — defense-in-depth path. In
      // supabase_flutter ^2.12.0, `client.functions.invoke()` THROWS
      // `FunctionException` for non-2xx responses by default — control
      // jumps to the catch block, never reaching this branch. Kept here
      // for forward-compat in case the package adopts response-style
      // semantics later.
      if (resp.status == 409) {
        final data = resp.data is Map
            ? resp.data as Map<String, dynamic>
            : <String, dynamic>{};
        if (data['error_code'] == 'already_pro') {
          await _handleAlreadyProResponse(data);
          onSuccess?.call(); // treat as success — user IS PRO
          return;
        }
      }
      if (resp.status != 200 || resp.data == null) {
        debugPrint('RazorpayService: create-razorpay-order failed '
            'status=${resp.status} data=${resp.data}');
        _showOrderCreationFailure(serverError: _extractServerError(resp.data));
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
    } catch (e, st) {
      // APK Test #12.5 / Class 2a — handle FunctionException from
      // supabase_flutter ^2.12.0. invoke() throws on non-2xx; the
      // 409 branch above is dead code in this version. Parse
      // `e.details` here.
      // audit-2026-05-11 H-42 — telemetry pair (covers BOTH the
      // FunctionException branch handlers AND the unknown-exception
      // tail at the end of this block).
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'razorpay_create_order'));
      if (e is FunctionException) {
        final status = e.status;
        final details = e.details;
        if (status == 409 && details is Map) {
          final m = Map<String, dynamic>.from(details);
          if (m['error_code'] == 'already_pro') {
            try {
              await _handleAlreadyProResponse(m);
              onSuccess?.call();
              return;
            } catch (inner, innerSt) {
              debugPrint('RazorpayService: 409 handler threw: $inner');
              unawaited(ErrorTelemetry.recordNonFatal(inner, innerSt,
                  reason: 'razorpay_already_pro_handler'));
            }
          }
        }
        debugPrint(
            'RazorpayService: create-razorpay-order FunctionException '
            'status=$status details=$details');
        _showOrderCreationFailure(serverError: _extractServerError(details));
        onFailure?.call();
        return;
      }
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

  /// APK Test #12.2 / Task #6 — shown when the server-side double-pay
  /// guard rejects the order create with 409 + already_pro. The user
  /// thought they were free; truth is they're PRO until [endLabel]. This
  /// fires both a toast AND triggers the cascade of provider invalidations
  /// that was supposed to happen on the original payment.
  void _showAlreadyProFeedback(String endLabel) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You\'re already PRO — active until $endLabel',
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1a2a1a),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Shows a non-blocking snackbar when server-side order creation fails
  /// before Razorpay checkout even opens. The user hasn't paid yet, so
  /// this is a recoverable "try again" state.
  ///
  /// APK Test #12.5 / Class 2b — when the server returns an actionable
  /// error message, surface it instead of the generic copy. Helps
  /// debug payment-flow regressions in the field (e.g. promo expired,
  /// validation failed, etc.) without needing edge-function logs.
  void _showOrderCreationFailure({String? serverError}) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    final msg = (serverError != null && serverError.isNotEmpty)
        ? serverError
        : 'Couldn\'t start payment. Check your connection and try again.';
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: AppTypography.bodySm.copyWith(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2a1a1a),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// APK Test #12.5 / Class 2a — extracted handler so the 409 path
  /// is identical whether `resp.status == 409` or the call threw a
  /// `FunctionException` carrying the same payload.
  ///
  /// Force-trusts the server's truth: writes active subscription
  /// state locally so subsequent reads (subscriptionInfoProvider,
  /// gate(), profile dossier) are correct.
  Future<void> _handleAlreadyProResponse(Map<String, dynamic> data) async {
    final endIso = data['current_expires_at'] as String?;
    final endDate = endIso != null ? DateTime.tryParse(endIso) : null;
    final endLabel = endDate != null
        ? '${endDate.day}/${endDate.month}/${endDate.year}'
        : 'now';
    if (endIso != null) {
      try {
        await SubscriptionService.instance.writeSubscriptionState(
          isPro: true,
          expiresAt: endIso,
          plan: (data['current_plan'] as String?) ?? 'monthly',
        );
        await SubscriptionService.instance.clearPaymentInFlight();
        _invalidateSubscriptionProviders();
      } catch (_) {}
    }
    _showAlreadyProFeedback(endLabel);
  }

  /// APK Test #12.5 / Class 2b — pulls a user-readable error message
  /// out of an Edge Function response body. Edge Functions follow the
  /// docs/architecture/ai.md "Edge Function Error Sanitization" contract:
  /// validation errors return `{error: "..."}` while internal errors
  /// return generic `{error: "Internal server error", request_id}`.
  /// Both shapes are handled — internal errors fall through to the
  /// generic toast (the request_id is in debug logs).
  String? _extractServerError(dynamic body) {
    if (body is! Map) return null;
    final err = body['error'];
    if (err is! String) return null;
    if (err == 'Internal server error') return null;
    return err;
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
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('RazorpayService: session refresh failed (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'razorpay_session_refresh'));
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
    //     (see docs/architecture/subscription.md — verifyFromServer cache TTL 5 min).
    //
    // Before this fix, if Phase 1 polling + Phase 2 verify both failed or
    // threw, the Phase 3 local fallback was ALSO skipped (it lived at the
    // end of _pollAndActivate) — leaving the user stuck without PRO even
    // though their payment went through. Now Phase 3 runs first + poll
    // confirms it afterwards.
    final fallbackPlan = _pendingPlan ?? 'monthly';
    final optimisticEndDate = _computeEndDate(fallbackPlan);
    // APK Test #12.2 / Task #5 — independent try/catch per write so a
    // single failure can't block the others. Pre-fix one shared try
    // around 3 awaited writes meant a throw in writeSubscriptionState
    // skipped both localActivationAt AND markPaymentInFlight — leaving
    // refreshFromSupabase with no grace window, which downgrades on
    // first server-query miss (webhook lag in test mode → no row →
    // downgrade). Founder's PRO-doesn't-stick bug.
    //
    // Write order: markPaymentInFlight FIRST so the grace window opens
    // even if the more complex writes fail. Then writeSubscriptionState
    // (3 keys) and localActivationAt independently. Each failure
    // surfaces via _reportSyncFailure → log-client-error (now widened
    // in Task #3 to actually accept these payloads).
    try {
      // H-41 (audit-2026-05-11) — record the Razorpay order_id so
      // the webhook + verify-payment confirmation paths have an
      // event-based handle to clear by. The 10-min time ceiling is
      // a fallback only now.
      await SubscriptionService.instance
          .markPaymentInFlight(orderId: response.orderId);
    } catch (e, st) {
      debugPrint('RazorpayService: markPaymentInFlight failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'razorpay_mark_payment_in_flight'));
    }
    try {
      await SubscriptionService.instance.writeSubscriptionState(
        isPro: true,
        expiresAt: optimisticEndDate,
        plan: fallbackPlan,
      );
    } catch (e, st) {
      debugPrint('RazorpayService: writeSubscriptionState failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'razorpay_write_subscription_state'));
    }
    try {
      await MigratedKey.write(
        'localActivationAt',
        DateTime.now().toIso8601String(),
      );
    } catch (e, st) {
      debugPrint('RazorpayService: localActivationAt write failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'razorpay_local_activation_at_write'));
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
    } catch (e, st) {
      debugPrint('RazorpayService: _pollAndActivate threw: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'razorpay_poll_and_activate'));
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
    _invalidateSubscriptionProviders();

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

  /// Invalidates the 3 subscription-related Riverpod providers.
  /// Called from:
  ///   - _showProActivatedFeedback (immediately on payment success)
  ///   - _pollAndActivate Phase 1 (when webhook confirms)
  ///   - _pollAndActivate Phase 2 (when verify-payment confirms)
  /// Each call triggers a UI rebuild for any widget watching these
  /// providers, so the user's pills + message counter reflect the latest
  /// PRO state without manual refresh.
  void _invalidateSubscriptionProviders() {
    final context = navigatorKey?.currentContext;
    if (context == null) return;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(subscriptionInfoProvider);
      container.invalidate(messageLimitProvider);
    } catch (_) {}
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
    //
    // H-20 (audit-2026-05-11) — per-iteration cancellation check.
    // The poll loop is fire-and-forget from `_handlePaymentSuccess`,
    // so the user could sign out / sign in as a different account
    // while we're sleeping between attempts. Pre-fix, the loop would
    // keep writing PRO state for the WRONG user. Re-read
    // `currentUser?.id` at the top of every iteration and abort if it
    // changed (or went null).
    for (int attempt = 0; attempt < 15; attempt++) {
      final delay = attempt < 5 ? 2 : (attempt < 10 ? 3 : 4);
      await Future.delayed(Duration(seconds: delay));

      // H-20 — cancel if session changed during the wait.
      final currentSessionUserId =
          SupabaseService.instance.currentUser?.id;
      if (currentSessionUserId != userId) {
        debugPrint(
            'RazorpayService: H-20 cancel — session changed mid-poll '
            '(captured=$userId now=$currentSessionUserId). Aborting at attempt $attempt.');
        return;
      }

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
          // APK Test #12 / Task C-1 — webhook confirmed, close grace window
          // so verifyFromServer behaves normally on subsequent calls.
          await SubscriptionService.instance.clearPaymentInFlight();
          // Trigger another provider invalidation now that we have the
          // server-confirmed end date (different from optimistic).
          _invalidateSubscriptionProviders();
          debugPrint('RazorpayService: webhook confirmed at attempt $attempt (exact=${attempt < 12})');
          return;
        }
      } catch (e, st) {
        debugPrint('RazorpayService: poll attempt $attempt failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'razorpay_poll_attempt'));
      }
    }

    // Phase 2: Direct verification via Edge Function (server checks Razorpay API)
    //
    // H-20 (audit-2026-05-11) — same session-cancellation guard as
    // Phase 1. Phase 2 awaits an Edge Function call which may take
    // seconds; the user could sign out / switch accounts in that
    // window. Re-check before writing PRO state.
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

        // H-20 — abort write if session changed during the Edge Function call.
        final postCallSessionId =
            SupabaseService.instance.currentUser?.id;
        if (postCallSessionId != userId) {
          debugPrint(
              'RazorpayService: H-20 cancel — session changed during verify-payment '
              '(captured=$userId now=$postCallSessionId). Aborting PRO write.');
          return;
        }

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
            await SubscriptionService.instance.clearPaymentInFlight();
            _invalidateSubscriptionProviders();
            debugPrint('RazorpayService: verified via Edge Function');
            return;
          }
        }
      } catch (e, st) {
        debugPrint('RazorpayService: verify-payment Edge Function failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'razorpay_verify_payment_edge_function'));
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
              await MigratedKey.delete('localActivationAt');
              return; // Payment verified server-side — stop retrying
            }
            debugPrint('RazorpayService: verify-payment returned 200 but verified=${data['verified']} — continuing retries');
          }
        } catch (e, st) {
          debugPrint('RazorpayService: verify-payment retry failed after ${delay.inSeconds}s: $e');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'razorpay_verify_payment_retry'));
        }
      });
    }
  }
}
