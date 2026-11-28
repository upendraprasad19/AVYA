// Plan section 7 test 2b: `RazorpayService.openCheckout` is the second door
// behind the paywall. In a binary whose purchase mode is not `razorpay` it
// must refuse BEFORE it validates the key or creates a server-side order.
//
// Observable: in `flutter test` the Razorpay key id is empty, so with the guard
// removed the call still ends in `onFailure` (through the invalid-key branch).
// The two branches print different lines, so the test reads the printed line to
// tell which door refused: a guard that is deleted turns this red.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';

Future<({int failures, List<String> lines, List<String> events})> _open(
    PurchaseMode mode) async {
  PurchaseMode.debugOverrideForTests = mode;
  final lines = <String>[];
  final events = <String>[];
  ErrorTelemetry.debugOnLogEventForTests =
      (op, {message}) => events.add('$op|${message ?? ''}');
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  var failures = 0;
  try {
    await RazorpayService.instance
        .openCheckout(plan: 'monthly', onFailure: () => failures++);
  } finally {
    debugPrint = original;
    PurchaseMode.debugOverrideForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
  }
  return (failures: failures, lines: lines, events: events);
}

void main() {
  const guardLine = 'does not sell through Razorpay';

  test('mode none: the guard refuses before the key check', () async {
    final r = await _open(PurchaseMode.none);
    expect(r.failures, 1);
    expect(r.lines.any((l) => l.contains(guardLine)), isTrue);
    expect(r.lines.any((l) => l.contains('invalid key ID')), isFalse);
    expect(r.events, ['razorpay_checkout_refused_mode|none'],
        reason: 'a refusal must not be silent (B-pass P3)');
  });

  test('mode playBilling behaves as none', () async {
    final r = await _open(PurchaseMode.playBilling);
    expect(r.failures, 1);
    expect(r.lines.any((l) => l.contains(guardLine)), isTrue);
    expect(r.events, ['razorpay_checkout_refused_mode|play_billing']);
  });

  test('mode razorpay: the guard does not fire (the old path is reachable)',
      () async {
    // This case needs an EMPTY key: with `--dart-define-from-file=.env` the
    // call would go on to create a real order. Say so instead of failing.
    if (AppConstants.razorpayKeyId.isNotEmpty) {
      markTestSkipped('RAZORPAY_KEY_ID is defined in this run');
      return;
    }
    final r = await _open(PurchaseMode.razorpay);
    expect(r.lines.any((l) => l.contains(guardLine)), isFalse);
    expect(r.events, isEmpty);
    // With no key in the test environment the next door refuses instead.
    expect(r.lines.any((l) => l.contains('invalid key ID')), isTrue);
  });
}
