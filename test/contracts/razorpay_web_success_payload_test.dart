import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/razorpay_web_checkout.dart';

void main() {
  group('parseWebSuccessPayload — web success → shared-pipeline fields', () {
    test('full payload maps all three fields', () {
      final r = parseWebSuccessPayload({
        'razorpay_payment_id': 'pay_Q123',
        'razorpay_order_id': 'order_Q456',
        'razorpay_signature': 'sig789',
      });
      expect(r.paymentId, 'pay_Q123');
      expect(r.orderId, 'order_Q456');
      expect(r.signature, 'sig789');
    });

    test('missing fields are null, never thrown', () {
      final r = parseWebSuccessPayload({});
      expect(r.paymentId, isNull);
      expect(r.orderId, isNull);
      expect(r.signature, isNull);
    });

    test('null values are null-safe', () {
      final r = parseWebSuccessPayload({
        'razorpay_payment_id': null,
        'razorpay_order_id': 12345,
      });
      expect(r.paymentId, isNull);
      expect(r.orderId, '12345'); // non-string coerced via toString
      expect(r.signature, isNull);
    });

    test('field names are EXACTLY the checkout.js contract (writer/reader pin)',
        () {
      // Guards against renaming to payment_id/order_id — the JS side of this
      // contract is Razorpay's, not ours; drift here silently nulls the id
      // that verify-payment polls by.
      final r = parseWebSuccessPayload({'payment_id': 'x'});
      expect(r.paymentId, isNull); // wrong key name must NOT be read
    });
  });
}
