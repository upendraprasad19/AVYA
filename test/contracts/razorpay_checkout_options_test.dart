import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';

void main() {
  group('buildRazorpayCheckoutOptions — order/amount parity pin', () {
    test('carries SERVER order_id and amount — never client-computed', () {
      final o = RazorpayService.buildRazorpayCheckoutOptions(
        keyId: 'rzp_test_x',
        orderId: 'order_server_made',
        amountPaise: 34900,
        plan: 'monthly',
        email: 'u@x.com',
        notes: {'user_id': 'uid', 'plan': 'monthly'},
      );
      expect(o['order_id'], 'order_server_made');
      expect(o['amount'], 34900);
      expect(o['currency'], 'INR');
    });

    test('notes flow through (user_id + promo reach the webhook)', () {
      final o = RazorpayService.buildRazorpayCheckoutOptions(
        keyId: 'k', orderId: 'o', amountPaise: 1, plan: 'yearly',
        email: '', notes: {'user_id': 'u', 'plan': 'yearly', 'promo_code': 'X'},
      );
      expect((o['notes'] as Map)['promo_code'], 'X');
      expect((o['prefill'] as Map)['email'], '');
    });

    test('plan label switches Yearly/Monthly', () {
      final y = RazorpayService.buildRazorpayCheckoutOptions(
        keyId: 'k', orderId: 'o', amountPaise: 1, plan: 'yearly',
        email: '', notes: const {},
      );
      expect(y['description'], 'PRO Yearly Plan');
    });
  });
}
