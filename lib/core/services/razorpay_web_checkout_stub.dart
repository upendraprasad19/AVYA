// Non-web stub for the Razorpay checkout bridge (spec 2026-09-17).
// razorpay_service only calls openWebCheckout behind kIsWeb, but the stub
// guarantees the Android/iOS build never references dart:js_interop (same
// rule as lib/shared/widgets/pwa_install/pwa_install_interop_stub.dart:6).
// The parsed-payload + kill-switch PURE functions live in the barrel and
// are importable on every platform.

/// No-op off-web. onUnavailable fires on native callers, but there are
/// none — the kIsWeb branch is the only caller.
void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function() onDismissed,
  required void Function(String message) onUnavailable,
}) {
  onUnavailable('Payments are only available on web or the mobile app.');
}
