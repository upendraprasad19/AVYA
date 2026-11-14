// test/contracts/create_order_rate_limit_writer_to_reader_test.dart
//
// payment-hardening U3 (OI-366, diagnose f2c9a8). Writer: create-razorpay-order's
// consume_quota('create_order', <1-hour UTC bucket>, 30), right after the JWT check, before any other read.
// Readers: its own -1 / error refusals (429, fails CLOSED); the client, which shows the `error` text of any
// non-409 non-2xx (RazorpayService._extractServerError); the founder digest (DIGEST_KEYS create_order, subday).
// Behaviour: the "U3:" Deno tests in supabase/functions/create-razorpay-order/index_test.ts. The key and limit
// literals are also read by founder_digest_caps_mirror_test.dart.
//
// Run: flutter test test/contracts/create_order_rate_limit_writer_to_reader_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _fn = 'supabase/functions/create-razorpay-order/index.ts';
const _client = 'lib/core/services/razorpay_service.dart';
const _digest = 'supabase/functions/_shared/founder_digest_content.ts';
const _inventory = 'docs/operations/SECRET_INVENTORY.md';

String _code(String ts) => ts
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  group('create_order_rate_limit', () {
    final code = _code(File(_fn).readAsStringSync());

    test('key, limit and a 1-hour bucket; the counter runs before the subscription guard read', () {
      expect(code, contains('const ORDER_QUOTA_KEY = "create_order";'));
      expect(code, contains('const ORDER_QUOTA_LIMIT = 30;'));
      expect(code, contains('const ORDER_RATE_WINDOW_MS = 60 * 60 * 1000;'));
      final counter = code.indexOf('p_quota_key: ORDER_QUOTA_KEY,');
      final guard = code.indexOf('.from("subscriptions")');
      final body = code.indexOf('await req.json()');
      expect(counter, greaterThan(0));
      expect(counter, lessThan(guard));
      expect(counter, lessThan(body));
    });

    test('both refusals are 429 and the RPC error fails CLOSED', () {
      expect(code, contains('return err(429, "Could not start payment right now. Try again shortly.", {'));
      expect(code, contains('error_code: "rate_limit_unavailable",'));
      // The wait is named in minutes (a fixed 1-hour bucket; B-pass beee28f0d9f2 finding 2).
      expect(code, contains('error: `Too many payment attempts. Try again in \${retryMinutes(retryAfterSeconds)}.`,'));
      expect(code, contains('"Retry-After": String(retryAfterSeconds)'));
    });

    test('the client shows the server `error` text for a non-409 failure (so the 429 copy reaches the user)', () {
      final src = File(_client).readAsStringSync();
      expect(src, contains("final err = body['error'];"));
      expect(src, contains('_extractServerError(details)'));
    });

    test('the digest lists the key (subday, no cap) and the kill switch is documented', () {
      expect(File(_digest).readAsStringSync(),
          contains('{ key: "create_order", label: "create-razorpay-order", kind: "subday" },'));
      expect(File(_inventory).readAsStringSync(), contains('`DISABLE_ORDER_ABUSE_GUARDS`'));
    });
  });
}
