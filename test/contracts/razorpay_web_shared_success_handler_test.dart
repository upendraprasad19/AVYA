// Source-grep wiring pin: native and web feed ONE shared success pipeline.
// Source-grep ONLY (rule 21 presence-only class, justified in the plan):
// behavioral testing of a plugin-callback delegation isn't feasible in a VM
// test and the extracted body is pinned by the verbatim-move instruction.
// The delegation is made non-vacuous by Mutation 4 (remove the call →
// the window-scoped delegation assertion reddens).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const srcPath = 'lib/core/services/razorpay_service.dart';
  late String src;

  setUpAll(() {
    src = File(srcPath).readAsStringSync();
  });

  group('shared success handler wiring — native and web feed ONE pipeline', () {
    test('extracted handlePaymentConfirmed exists with the shared signature', () {
      expect(src, contains('Future<void> handlePaymentConfirmed({'));
      expect(src, contains('required String paymentId'));
      expect(src, contains('String? orderId'));
      expect(src, contains('String? signature'));
    });

    test('native _handlePaymentSuccess DELEGATES (brace-scoped regex — round-2 P1 + round-3 mutation-4 finding: a substring/window form is satisfied by the method definition itself or the ADJACENT definition and can never redden)', () {
      final delIdx =
          src.indexOf('void _handlePaymentSuccess(PaymentSuccessResponse');
      expect(delIdx, greaterThanOrEqualTo(0));
      // [^}]* ends at the delegator's own closing brace, so only the
      // delegator's BODY can satisfy this — the adjacent definition cannot.
      expect(
        RegExp(r'void _handlePaymentSuccess\(PaymentSuccessResponse[^}]*handlePaymentConfirmed\(')
            .hasMatch(src.substring(delIdx)),
        isTrue,
        reason: 'the delegator body must call handlePaymentConfirmed — '
            'severing the delegation (body → return;) must redden this',
      );
    });

    test('poll + in-flight mark reachable through the shared method', () {
      expect(src, contains('markPaymentInFlight'));
      expect(src, contains('_pollAndActivate('));
    });

    test('web payment.failed wired to the SHARED failure feedback (B-pass P2-3)', () {
      // Source-grep presence pins (behavioral not feasible — navigatorKey UI
      // in a JS-bridge callback; the predicate/latch logic is a local
      // closure). The bridge's payment.failed wiring is additionally
      // exercised only at web compile (Task 6 flutter build web).
      expect(src, contains('onPaymentFailed'));
      expect(src, contains('_showPaymentFailedFeedback('));
      expect(src, contains('var settled = false;'),
          reason: 'B-pass P3-5 one-shot latch — ondismiss may fire after success');
      final webSrc =
          File('lib/core/services/razorpay_web_checkout_web.dart').readAsStringSync();
      expect(webSrc, contains("'payment.failed'"));
      expect(webSrc, contains('recordNonFatal'),
          reason: 'B-pass P2-1: the bridge catch must carry telemetry');
    });
  });
}
