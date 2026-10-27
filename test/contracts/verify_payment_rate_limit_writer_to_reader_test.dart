// OI-162 slice 4 (f2c8d5) — verify-payment's 20/10min rate limit destructured
// only `{ count }`, never `{ error }`, so a counter-query failure silently
// proceeded as if under the limit (fail-open BY OMISSION). Fixed to enforce
// atomically via usage_counters and to fail CLOSED on error — a deliberate
// choice, the opposite of delete-account's fail-open, because this endpoint
// is background confirmation only (see the source comment this test pins).
//
// SCOPE — presence only, deliberately. See
// delete_account_rate_limit_writer_to_reader_test.dart's header for the full
// caveat (no Deno on this machine; live-ledger behavior proven in
// `test/sql/` separately).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Comment-stripped source — this file's own header comment names the
/// retired channel for historical explanation, so absence assertions must
/// not run against the raw file.
String _ef() {
  final raw =
      File('supabase/functions/verify-payment/index.ts').readAsStringSync();
  return raw
      .split('\n')
      .map((l) {
        final i = RegExp(r'(?<!:)//').firstMatch(l)?.start ?? -1;
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('OI-162 slice 4 — verify-payment rate limit', () {
    late String src;

    setUpAll(() => src = _ef());

    test('consumes the ledger under the verify_payment quota key', () {
      expect(src, contains('consume_quota'),
          reason: 'the limit must delegate to the atomic ledger entry point');
      expect(
        RegExp(r'p_quota_key:\s*RATE_LIMIT_QUOTA_KEY').hasMatch(src),
        isTrue,
        reason: 'the RPC must be called with the quota-key constant',
      );
      expect(
        RegExp(r'RATE_LIMIT_QUOTA_KEY\s*=\s*"verify_payment"').hasMatch(src),
        isTrue,
        reason: 'and that constant must still name the verify_payment quota',
      );
      expect(
        RegExp(r'p_limit:\s*RATE_LIMIT_MAX').hasMatch(src),
        isTrue,
        reason: 'the cap must be passed through, not hard-coded at the call',
      );
      expect(
        RegExp(r'RATE_LIMIT_MAX\s*=\s*20').hasMatch(src),
        isTrue,
        reason: 'the 20-attempt cap must be unchanged',
      );
    });

    test('p_user_id and p_window_start are wired to the validated variables', () {
      // Hermes L1 F2 (2026-09-11) — same gap as delete-account's mirror test:
      // p_quota_key/p_limit were pinned by ASSOCIATION, p_user_id/
      // p_window_start were not, proven exploitable by two live mutations
      // that left the whole file green (p_window_start ->
      // new Date().toISOString(); p_user_id -> a fixed dummy UUID).
      expect(
        RegExp(r'p_user_id:\s*userId\b').hasMatch(src),
        isTrue,
        reason: 'p_user_id must be wired to the validated JWT user id, not '
            'a literal or a body-supplied value',
      );
      expect(
        RegExp(r'p_window_start:\s*bucketStart\b').hasMatch(src),
        isTrue,
        reason: 'p_window_start must be wired to the FLOORED bucket '
            'variable — an unfloored timestamp here makes every call its '
            'own bucket of one',
      );
      expect(
        RegExp(r'const\s+bucketStart\s*=\s*new Date\(bucketStartMs\)'
                r'\.toISOString\(\)')
            .hasMatch(src),
        isTrue,
        reason: 'and bucketStart itself must be derived from the floored '
            'bucketStartMs — otherwise this test could pass while the RPC '
            'received an unfloored timestamp under a different name',
      );
    });

    test('uses a FIXED 10-minute bucket, not a rolling window', () {
      expect(
        RegExp(r'RATE_LIMIT_WINDOW_MS\s*=\s*10\s*\*\s*60\s*\*\s*1000')
            .hasMatch(src),
        isTrue,
        reason: 'the window must be in milliseconds and stay 10 minutes',
      );
      expect(
        RegExp(r'Math\.floor\(\s*Date\.now\(\)\s*/\s*RATE_LIMIT_WINDOW_MS\s*\)'
                r'\s*\*\s*RATE_LIMIT_WINDOW_MS')
            .hasMatch(src),
        isTrue,
        reason: 'the bucket start must be a FLOOR, matching consume_quota\'s '
            'fixed-window PK — a rolling subtraction here would make every '
            'call its own bucket of one',
      );
      expect(
        RegExp(r'Date\.now\(\)\s*-\s*10\s*\*\s*60\s*\*\s*1000').hasMatch(src),
        isFalse,
        reason: 'the old rolling cutoff computation must be gone',
      );
    });

    test('the error path is CHECKED, not silently dropped', () {
      // THE defect this slice fixes: `{ count: recentAttempts }` alone let a
      // query failure read as `count == null`, `(null ?? 0) >= 20` false,
      // and the request proceeded. The destructure must now name `error`.
      expect(
        RegExp(r'const\s*\{\s*data:\s*usedCount,\s*error:\s*rateErr\s*\}')
            .hasMatch(src),
        isTrue,
        reason: 'the RPC result must destructure BOTH data and error — '
            'destructuring count alone (the pre-fix shape) is the exact '
            'defect this test exists to catch',
      );
      expect(
        RegExp(r'const\s*\{\s*count:\s*recentAttempts\s*\}').hasMatch(src),
        isFalse,
        reason: 'the old count-only destructure must be gone entirely',
      );
    });

    test('a consume_quota error FAILS CLOSED with 429', () {
      // Deliberately the OPPOSITE of delete-account: this endpoint is
      // background confirmation only (PRO already activated optimistically
      // in Hive; the webhook is independent; the client retries 3 more
      // times), so a false refusal costs almost nothing, while fail-open
      // under a correlated outage releases the exact brake this limit
      // protects.
      final rpcIdx = src.indexOf('consume_quota');
      expect(rpcIdx, greaterThanOrEqualTo(0));
      final after = src.substring(rpcIdx);
      final errGuard = RegExp(r'if\s*\(\s*rateErr\s*\)').firstMatch(after);
      expect(errGuard, isNotNull,
          reason: 'the error path must be checked explicitly');
      // A `status: 429` must appear between the error guard and the NEXT
      // guard (the -1 check), proving the error branch itself refuses.
      final nextGuardIdx =
          after.indexOf('if (usedCount === -1)', errGuard!.end);
      expect(nextGuardIdx, greaterThan(errGuard.end));
      final errorBranch = after.substring(errGuard.end, nextGuardIdx);
      expect(errorBranch, contains('429'),
          reason: 'the error branch must itself return 429 — fail CLOSED, '
              'not fall through to proceed');
      expect(errorBranch, contains('console.error'),
          reason: 'a fail-closed refusal on a real error must be logged '
              'loudly, not at warn level — this is now an unexpected state');
    });

    test('a -1 return refuses with 429 and an exact Retry-After', () {
      expect(
        RegExp(r'usedCount\s*===?\s*-1').hasMatch(src),
        isTrue,
        reason: 'the exhaustion sentinel must gate the refusal',
      );
      expect(
        RegExp(r'Math\.ceil\(\s*\(\s*bucketStartMs\s*\+\s*'
                r'RATE_LIMIT_WINDOW_MS\s*-\s*Date\.now\(\)\s*\)\s*/\s*1000\s*\)')
            .hasMatch(src),
        isTrue,
        reason: 'Retry-After must reflect the bucket boundary, not the old '
            'hard-coded 600',
      );
      expect(
        src.contains('retry_after_seconds: 600'),
        isFalse,
        reason: 'the old fixed 600-second Retry-After value must be gone',
      );
    });

    test('the -1 refusal is logged server-side (Hermes L29 F2)', () {
      // Pre-fix this branch had NO console call at all — an operator
      // watching prod logs had zero visibility into how often the
      // 20/10min limit actually fires. ASSOCIATION: the log call must sit
      // between the -1 guard and the NEXT guard (the rateErr one is
      // EARLIER, so anchor on the closing brace via the Retry-After header,
      // which only this branch emits).
      final dashIdx = src.indexOf('usedCount === -1');
      expect(dashIdx, greaterThanOrEqualTo(0));
      final retryAfterHeaderIdx = src.indexOf('"Retry-After"', dashIdx);
      expect(retryAfterHeaderIdx, greaterThan(dashIdx));
      final branch = src.substring(dashIdx, retryAfterHeaderIdx);
      expect(
        RegExp(r'console\.(warn|error)\(').hasMatch(branch),
        isTrue,
        reason: 'the rate-limit-exhausted branch must log server-side '
            '(console.warn or console.error) before returning 429 — found '
            'no console call between the -1 check and the Retry-After '
            'header it sets',
      );
    });

    test('the retired channel and its fire-and-forget insert are GONE', () {
      expect(src.contains('verify_payment_attempt'), isFalse,
          reason: 'the dead channel literal must not appear in live code');
      expect(
        RegExp(r'\.insert\(\{[\s\S]{0,120}channel:').hasMatch(src),
        isFalse,
        reason: 'the old fire-and-forget insert into ai_coach_interactions '
            'must be gone entirely — consume_quota is the only write now',
      );
    });

    test('the source-counter allowlist is ratcheted to 0', () {
      final lib =
          File('scripts/usage_counter_source_lib.dart').readAsStringSync();
      expect(
        RegExp(r"'supabase/functions/verify-payment/index\.ts':\s*0")
            .hasMatch(lib),
        isTrue,
        reason: 'verify-payment must hold ZERO legacy quota counters now',
      );
    });
  });
}
