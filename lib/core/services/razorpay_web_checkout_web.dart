// Web implementation of the Razorpay checkout bridge (spec 2026-09-17).
// Selected by the conditional import in razorpay_web_checkout.dart keyed
// `dart.library.js_interop`. MUST NOT be imported directly by native-facing
// code — the barrel is the only entry point.
//
// ⚠ checkout.js has NO failure callback: card failures/retries happen
// inside Razorpay's own modal; the only close signal is modal.ondismiss.
// onUnavailable covers the SDK-unavailable case (script blocked/offline).
//
// Spec: docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

extension type RazorpayCheckoutInstance._(JSObject _) implements JSObject {
  external void open();
}

@JS('Razorpay')
external JSFunction get _razorpayCtor;

void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function() onDismissed,
  required void Function(String message) onUnavailable,
}) {
  try {
    final jsAny = options.jsify();
    if (jsAny == null) {
      // Unreachable for a Map, but a null here must surface, not crash.
      onUnavailable("Couldn't start payment. Check your connection and try again.");
      return;
    }
    // JSAny → JSObject via `as` (the documented interop cast form; the `is`
    // check form trips invalid_runtime_check_with_js_interop_types).
    final jsOptions = jsAny as JSObject;
    jsOptions['handler'] = ((JSObject resp) {
      final raw = resp.dartify();
      onSuccess(raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{});
    }).toJS;
    final modal = JSObject();
    modal['ondismiss'] = (() => onDismissed()).toJS;
    jsOptions['modal'] = modal;

    final instance = _razorpayCtor
        .callAsConstructor<RazorpayCheckoutInstance>(jsOptions);
    instance.open();
  } catch (_) {
    // SDK missing (checkout.js blocked/offline) or construction failure —
    // actionable failure, never a silent swallow (rule 17: release error
    // handling must surface something to the user).
    onUnavailable("Couldn't start payment. Check your connection and try again.");
  }
}
