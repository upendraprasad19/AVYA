// Contract test — every `.from("subscriptions").upsert(...)` or `.insert(...)`
// payload in `verify-payment/index.ts` MUST include every NOT NULL column
// declared on `public.subscriptions`.
//
// Closes OI-27 (audit-2026-05-17 Hermes F2). Migration 052 (2026-05-13)
// added NOT NULL to `razorpay_order_id`, `razorpay_payment_id`, and
// `razorpay_signature`. verify-payment validates via Razorpay REST API
// (not HMAC) and never sent the signature column — every fallback path
// after webhook lag threw 23502. Combined with OI-26 webhook TDZ this
// was a complete payment failure: user pays, webhook throws, fallback
// throws, PRO never unlocks.
//
// Lens L22 (schema-vs-payload parity) precedent. When a future migration
// adds a NOT NULL column to subscriptions, extend `_requiredColumns`
// below in the same PR.
//
// closes-diagnose: see `docs/diagnoses/2026-05-17-oi-27-verify-payment-not-null-*.md`

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/verify-payment/index.ts';

// NOT NULL columns on public.subscriptions as of migration 052 (2026-05-13).
// Extend when a future migration adds more.
const _requiredColumns = <String>[
  'user_id',
  'plan',
  'status',
  'start_date',
  'end_date',
  'razorpay_payment_id',
  'razorpay_order_id',
  'razorpay_signature',
];

void main() {
  group('verify-payment subscription payload completeness', () {
    test('both upsert + fallback insert payloads include all NOT NULL columns',
        () {
      final src = File(_path).readAsStringSync();

      // Match every `.from("subscriptions")` chain and capture the object
      // literal passed to the subsequent `.upsert({...})` or `.insert({...})`.
      // We use a brace-balanced scan to handle nested objects.
      final chainStart = RegExp(r'\.from\(\s*["' "'" r']subscriptions["' "'" r']\s*\)');
      final payloads = <String>[];

      for (final m in chainStart.allMatches(src)) {
        // Search forward for either `.upsert(` or `.insert(` then balance
        // braces until we have the literal.
        final tail = src.substring(m.end);
        final callMatch = RegExp(r'\.(upsert|insert)\s*\(\s*\{').firstMatch(tail);
        if (callMatch == null) continue;
        final openBraceAbs = m.end + callMatch.end - 1; // position of `{`
        // Brace-balance scan.
        int depth = 0;
        int? closeIdx;
        for (int i = openBraceAbs; i < src.length; i++) {
          final c = src[i];
          if (c == '{') depth++;
          if (c == '}') {
            depth--;
            if (depth == 0) {
              closeIdx = i;
              break;
            }
          }
        }
        if (closeIdx != null) {
          payloads.add(src.substring(openBraceAbs, closeIdx + 1));
        }
      }

      expect(
        payloads.length,
        greaterThanOrEqualTo(2),
        reason:
            'expected ≥2 subscription insert/upsert payloads (primary upsert + '
            'fallback insert); found ${payloads.length}. If the fallback was '
            'intentionally removed, update this test.',
      );

      for (final payload in payloads) {
        for (final col in _requiredColumns) {
          // Match `<col>:` (long form) OR `<col>,` / `<col>}` (object
          // shorthand `plan,` etc.). Both forms are valid TS object keys.
          final keyRegex = RegExp(
            '(^|[\\s,{])\\s*$col\\s*(:|,|\\})',
            multiLine: true,
          );
          expect(
            keyRegex.hasMatch(payload),
            isTrue,
            reason:
                'subscription payload missing required NOT NULL column "$col". '
                'Payload follows:\n$payload',
          );
        }
      }
    });

    test('razorpay_signature uses the verified_via_api sentinel pattern', () {
      // Defends against someone setting `razorpay_signature: ''` to silence
      // the column-presence test above. The sentinel is grep-able for later
      // analytics on which subscriptions were created via verify-payment vs
      // the HMAC-verified webhook (which stores the real signature).
      final src = File(_path).readAsStringSync();
      final sentinelRegex = RegExp(
        r'verified_via_api:',
      );
      expect(
        sentinelRegex.hasMatch(src),
        isTrue,
        reason:
            'expected "verified_via_api:" sentinel for razorpay_signature value. '
            'If the sentinel format changed, update both the source and this test.',
      );
    });
  });
}
