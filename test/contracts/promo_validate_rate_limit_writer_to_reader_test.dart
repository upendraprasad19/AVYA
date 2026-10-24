// test/contracts/promo_validate_rate_limit_writer_to_reader_test.dart
//
// payment-hardening U3 (OI-366, diagnose f2c9a8). Writer: validate-promo's
// consume_quota('promo_validate', <1-hour UTC bucket>, 20), right after the JWT check. Readers: its own refusals,
// which are HTTP 200 {valid:false, reason}; the paywall, which shows `reason` when `valid` is not true and shows
// "Network error" for ANY non-2xx (so a 429 would hide the reason); the digest (DIGEST_KEYS promo_validate).
// Behaviour: supabase/functions/validate-promo/index_test.ts.
//
// Run: flutter test test/contracts/promo_validate_rate_limit_writer_to_reader_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _fn = 'supabase/functions/validate-promo/index.ts';
const _paywall = 'lib/shared/widgets/paywall_sheet.dart';
const _digest = 'supabase/functions/_shared/founder_digest_content.ts';

String _code(String ts) => ts
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  group('promo_validate_rate_limit', () {
    final code = _code(File(_fn).readAsStringSync());

    test('key, limit, 1-hour bucket; the counter runs before the body and the lookup', () {
      expect(code, contains('const PROMO_QUOTA_KEY = "promo_validate";'));
      expect(code, contains('const PROMO_QUOTA_LIMIT = 20;'));
      expect(code, contains('const PROMO_RATE_WINDOW_MS = 60 * 60 * 1000;'));
      final counter = code.indexOf('p_quota_key: PROMO_QUOTA_KEY,');
      expect(counter, greaterThan(0));
      expect(counter, lessThan(code.indexOf('await req.json()')));
      expect(counter, lessThan(code.indexOf('.from("promo_codes")')));
    });

    test('every refusal is an HTTP 200 {valid:false, reason}, never a non-2xx the paywall would hide', () {
      expect(code, contains('return answer({ valid: false, reason: RATE_LIMITED_REASON });'));
      expect(code, contains('return answer({ valid: false, reason: CHECK_UNAVAILABLE_REASON });'));
      expect(code, contains('function answer(payload: Record<string, unknown>, status = 200): Response {'));
    });

    test('the paywall shows `reason` when valid is not true, and "Network error" only for a thrown call', () {
      final src = File(_paywall).readAsStringSync();
      expect(src, contains("if (data['valid'] == true) {"));
      expect(src, contains("_promoError = data['reason'] as String? ?? 'Invalid code';"));
    });

    test('the digest lists the key (subday, no cap)', () {
      expect(File(_digest).readAsStringSync(),
          contains('{ key: "promo_validate", label: "validate-promo", kind: "subday" },'));
    });
  });
}
