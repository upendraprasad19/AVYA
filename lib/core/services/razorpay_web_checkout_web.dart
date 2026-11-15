// Web implementation of the Razorpay checkout bridge (spec 2026-09-17).
// Selected by the conditional import in razorpay_web_checkout.dart keyed
// `dart.library.js_interop`. MUST NOT be imported directly by native-facing
// code — the barrel is the only entry point.
//
// Close/error signals (B-pass corrected): Razorpay Standard Checkout DOES
// expose a failure event — `payment.failed` — and we WIRE it so real card
// failures get the same app-level feedback as native. `modal.ondismiss`
// remains the close signal for user-initiated closes; onUnavailable covers
// the SDK-unavailable case (script blocked/offline).
//
// Spec: docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:icanbefitter/core/services/error_telemetry.dart';

extension type RazorpayCheckoutInstance._(JSObject _) implements JSObject {
  external void open();
  external void on(JSString event, JSFunction handler);
}

@JS('Razorpay')
external JSFunction get _razorpayCtor;

void openWebCheckout({
  required Map<String, dynamic> options,
  required void Function(Map<String, dynamic> rawSuccess) onSuccess,
  required void Function(String message) onPaymentFailed,
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
    // Wire the SDK's real failure event — response.error.description per
    // Razorpay's standard-checkout docs; defensive on the payload shape.
    instance.on('payment.failed'.toJS, ((JSObject resp) {
      final raw = resp.dartify();
      var msg = 'Payment failed';
      if (raw is Map) {
        final err = raw['error'];
        if (err is Map && err['description'] != null) {
          msg = err['description'].toString();
        }
      }
      onPaymentFailed(msg);
    }).toJS);
    instance.open();
  } catch (e, st) {
    // SDK missing (checkout.js blocked/offline) or construction failure —
    // actionable failure + telemetry (B-pass P2: this was the only
    // telemetry-free catch in the payment path).
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'razorpay_web_checkout_unavailable'));
    onUnavailable("Couldn't start payment. Check your connection and try again.");
  }
}
