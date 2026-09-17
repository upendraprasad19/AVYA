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

    test('native _handlePaymentSuccess DELEGATES (window-scoped — round-2 P1: a bare contains() is satisfied by the method definition itself and can never redden)', () {
      final delIdx =
          src.indexOf('void _handlePaymentSuccess(PaymentSuccessResponse');
      expect(delIdx, greaterThanOrEqualTo(0));
      expect(src.substring(delIdx, delIdx + 400),
          contains('handlePaymentConfirmed('),
          reason: 'the delegator body within 400 chars of the signature must '
              'call handlePaymentConfirmed — severing the delegation must redden this');
    });

    test('poll + in-flight mark reachable through the shared method', () {
      expect(src, contains('markPaymentInFlight'));
      expect(src, contains('_pollAndActivate('));
    });
  });
}
