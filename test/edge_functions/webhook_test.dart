@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Layer 3: Razorpay webhook Edge Function tests.
///
/// Tests auth guards and input validation for the razorpay-webhook
/// Edge Function. Does NOT test actual payment processing (would require
/// real Razorpay HMAC secret).
///
/// Run: flutter test test/edge_functions/webhook_test.dart
void main() {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Helper to call the webhook Edge Function.
  Future<http.Response> callWebhook({
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final url = '$supabaseUrl/functions/v1/razorpay-webhook';
    return http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'apikey': anonKey,
        ...?extraHeaders,
      },
      body: json.encode(body ?? {}),
    );
  }

  group('Razorpay Webhook — Validation', () {
    // T25: Invalid signature → rejected
    test('T25: request with invalid signature is rejected', () async {
      final response = await callWebhook(
        body: {
          'razorpay_order_id': 'order_fake123',
          'razorpay_payment_id': 'pay_fake456',
          'razorpay_signature': 'invalid_signature_value',
          'user_id': 'test-user-id',
          'plan': 'monthly',
        },
        extraHeaders: {
          'x-razorpay-signature': 'invalid_hmac_value',
        },
      );

      // Should reject with 401 (bad signature) or 400 (validation error)
      expect(
        [400, 401, 403, 500].contains(response.statusCode),
        isTrue,
        reason:
            'Invalid signature should be rejected (got ${response.statusCode})',
      );
    });

    // T26: Missing required fields → rejected
    test('T26: request with missing fields is rejected', () async {
      final response = await callWebhook(
        body: {
          // Missing razorpay_order_id, razorpay_payment_id, razorpay_signature
          'plan': 'monthly',
        },
      );

      // Should reject with 400 (missing fields) or similar error
      expect(
        response.statusCode != 200,
        isTrue,
        reason: 'Missing fields should not succeed (got ${response.statusCode})',
      );
    });

    // T24: Webhook endpoint is reachable
    test('T24: webhook endpoint responds (does not 404)', () async {
      final response = await callWebhook(body: {});

      // Any response other than 404 means the function is deployed
      expect(
        response.statusCode != 404,
        isTrue,
        reason:
            'Webhook Edge Function should be deployed (got ${response.statusCode})',
      );
    });
  });
}
