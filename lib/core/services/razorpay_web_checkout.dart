/// Web Razorpay checkout — selection barrel + pure mappings.
///
/// The JS-interop implementation (`razorpay_web_checkout_web.dart`) is
/// selected ONLY on web via the conditional import below, keyed on
/// `dart.library.js_interop` (modern web interop — NOT the deprecated
/// dart:html used by lib/features/dev/xls_saver_web.dart). Pattern
/// precedent: lib/shared/widgets/pwa_install/pwa_install_interop_*.dart.
/// The stub guarantees the Android/iOS build never references web libs.
///
/// Spec: docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md
library;

import 'razorpay_web_checkout_stub.dart'
    if (dart.library.js_interop) 'razorpay_web_checkout_web.dart' as impl;

/// Pure mapping of Razorpay Standard Checkout's web success payload onto
/// the three fields the native SDK's PaymentSuccessResponse carries —
/// the shared verification pipeline consumes identical values on both
/// platforms. Field names are Razorpay's checkout.js contract; a rename
/// here silently nulls the id verify-payment polls by.
({String? paymentId, String? orderId, String? signature})
    parseWebSuccessPayload(Map<String, dynamic> raw) {
  String? ns(Object? v) => v == null ? null : v.toString();
  return (
    paymentId: ns(raw['razorpay_payment_id']),
    orderId: ns(raw['razorpay_order_id']),
    signature: ns(raw['razorpay_signature']),
  );
}

/// §4.6 kill-switch predicate — pure, testable form (mirrors
/// `isSyncAutoDrainDisabled`, sync_state_provider.dart:43). configBox key
/// `disable_web_checkout`: absent or anything but `true` ⇒ web checkout
/// ACTIVE, so a missing/unopened configBox can never silently disable
/// payments. The defensive configBox wrapper is
/// `RazorpayService.webCheckoutDisabled`.
bool isWebCheckoutDisabledByConfig(Object? rawConfigValue) =>
    rawConfigValue == true;

/// Barrel entry — delegates to the selected implementation.
void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function() onDismissed,
  required void Function(String message) onUnavailable,
}) =>
    impl.openWebCheckout(
      options: options,
      onSuccess: onSuccess,
      onDismissed: onDismissed,
      onUnavailable: onUnavailable,
    );
