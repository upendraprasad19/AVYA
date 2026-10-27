// Source-grep contract for the razorpay-webhook 5-minute replay window.
//
// Originally landed as T-2 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-2 razorpay-webhook 5-min replay window', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/razorpay-webhook/index.ts');
    });

    test('rejects webhooks older than 5 minutes', () {
      // The check uses `paymentEntity.created_at` (epoch seconds) +
      // a 300-second window. Source-grep the constants.
      expect(
        src.contains('300') || src.contains('5 * 60'),
        isTrue,
        reason: 'razorpay-webhook must enforce a 5-min replay window. '
            'Razorpay retries within seconds; older events are either a '
            'replay attack or stale events our idempotency has already '
            'processed.',
      );
      expect(src.contains('created_at'), isTrue);
      expect(
        src.contains('Webhook too old') || src.contains('age_seconds'),
        isTrue,
        reason: 'reject with a descriptive 400 so support can correlate '
            'log lines.',
      );
    });
  });
}
