// OI-162 slice 4 (f2c8d5) — delete-account's 5/60min rate limit had NEVER
// FUNCTIONED and is fixed to enforce atomically via usage_counters.
//
// THE BUG: the fire-and-forget insert targeted `prompt_snippet` /
// `response_snippet`, two columns that do not exist on
// `ai_coach_interactions`, and left `user_message` (NOT NULL, no default)
// unset — every insert failed on both PGRST204 and 23502 into a handler that
// only `console.warn`'d. `attemptCount` was structurally always 0, so the
// `>= RATE_LIMIT_MAX` check could never fire. Diagnose f2c8d5; original limit
// 7ad009 (2026-05-11).
//
// SCOPE — presence only, deliberately. These are source greps over one Edge
// Function. They prove the code SAYS the right thing; they cannot prove live
// Deno BEHAVES that way, and there is no Deno on this machine. CI's
// `deno-edge-functions` job is the only compile proof. Live-ledger behavior
// (limit-1/limit/limit+1, bucket isolation) is proven separately in
// `test/sql/` inside a rolled-back transaction.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Edge Function source, `//` comments stripped so an assertion can never
/// be satisfied by prose ABOUT the code (this file's own header comment names
/// the retired channel and the phantom columns explicitly, by design — a
/// naive un-stripped grep for their absence would fail against itself).
String _ef() {
  final raw =
      File('supabase/functions/delete-account/index.ts').readAsStringSync();
  return raw
      .split('\n')
      .map((l) {
        // Must not eat `https://` — the naive indexOf('//') truncates every
        // import/URL line at the protocol separator.
        final i = RegExp(r'(?<!:)//').firstMatch(l)?.start ?? -1;
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('OI-162 slice 4 — delete-account rate limit', () {
    late String src;

    setUpAll(() => src = _ef());

    test('consumes the ledger under the delete_account quota key', () {
      expect(src, contains('consume_quota'),
          reason: 'the limit must delegate to the atomic ledger entry point');

      // ASSOCIATION, not membership — pin the RPC argument to the constant,
      // and the constant to its value, as two separate links. A prior slice
      // in this same batch (migration 130) shipped a fix that COPIED a
      // pattern by analogy without re-deriving it; presence-only tests are
      // exactly the class of assertion that misses drift like that.
      expect(
        RegExp(r'p_quota_key:\s*RATE_LIMIT_QUOTA_KEY').hasMatch(src),
        isTrue,
        reason: 'the RPC must be called with the quota-key constant, not '
            'some other literal',
      );
      expect(
        RegExp(r'RATE_LIMIT_QUOTA_KEY\s*=\s*"delete_account"').hasMatch(src),
        isTrue,
        reason: 'and that constant must still name the delete_account quota',
      );
      expect(
        RegExp(r'p_limit:\s*RATE_LIMIT_MAX').hasMatch(src),
        isTrue,
        reason: 'the cap must be passed through, not hard-coded at the call',
      );
      expect(
        RegExp(r'RATE_LIMIT_MAX\s*=\s*5').hasMatch(src),
        isTrue,
        reason: 'the 5-attempt cap must be unchanged',
      );
    });

    test('p_user_id and p_window_start are wired to the validated variables', () {
      // Hermes L1 F1 (2026-09-11): the test above pins p_quota_key/p_limit by
      // ASSOCIATION, but p_user_id/p_window_start were pinned by MEMBERSHIP
      // only (the RPC call block contains "userId" and "bucketStart"
      // somewhere) — proven exploitable by two live mutations that left the
      // whole file green: p_window_start -> new Date().toISOString()
      // (unfloored, defeats the fixed-bucket property) and p_user_id -> a
      // fixed dummy UUID (defeats per-user isolation entirely).
      expect(
        RegExp(r'p_user_id:\s*userId\b').hasMatch(src),
        isTrue,
        reason: 'p_user_id must be wired to the validated JWT user id — a '
            'literal, a body field, or any other source silently breaks '
            'per-user isolation while every OTHER assertion in this file '
            'stays green',
      );
      expect(
        RegExp(r'p_window_start:\s*bucketStart\b').hasMatch(src),
        isTrue,
        reason: 'p_window_start must be wired to the FLOORED bucket '
            'variable — passing Date.now() or a fresh ISO timestamp here '
            'makes every call its own bucket of one',
      );
      expect(
        RegExp(r'const\s+bucketStart\s*=\s*new Date\(bucketStartMs\)'
                r'\.toISOString\(\)')
            .hasMatch(src),
        isTrue,
        reason: 'and bucketStart itself must be derived from the floored '
            'bucketStartMs (pinned separately below), not built '
            'independently — otherwise this test could pass while the RPC '
            'still received an unfloored timestamp under a different name',
      );
    });

    test('uses a FIXED hourly bucket, not a rolling window', () {
      // The pre-fix code computed `Date.now() - RATE_LIMIT_WINDOW_MINUTES *
      // 60_000` — a genuinely rolling window. consume_quota's PK includes
      // window_start, so it needs a FLOORED bucket; reverting to rolling
      // arithmetic here would pass a different p_window_start on every call,
      // defeating the ledger (every call becomes its own bucket of one).
      expect(
        RegExp(r'RATE_LIMIT_WINDOW_MS\s*=\s*60\s*\*\s*60\s*\*\s*1000')
            .hasMatch(src),
        isTrue,
        reason: 'the window must be expressed in milliseconds for the '
            'bucket-floor computation, and must still be one hour',
      );
      expect(
        RegExp(r'Math\.floor\(\s*Date\.now\(\)\s*/\s*RATE_LIMIT_WINDOW_MS\s*\)'
                r'\s*\*\s*RATE_LIMIT_WINDOW_MS')
            .hasMatch(src),
        isTrue,
        reason:
            'the bucket start must be a FLOOR, not a rolling subtraction — '
            'Date.now() - WINDOW_MS is the old, wrong shape',
      );
      expect(
        RegExp(r'Date\.now\(\)\s*-\s*RATE_LIMIT_WINDOW_M').hasMatch(src),
        isFalse,
        reason: 'the rolling-window computation must be gone entirely',
      );
    });

    test('a -1 return refuses with 429 and an exact Retry-After', () {
      expect(
        RegExp(r'usedCount\s*===?\s*-1').hasMatch(src),
        isTrue,
        reason: 'the exhaustion sentinel must gate the refusal',
      );
      expect(src, contains('"rate_limited"'),
          reason: 'the refusal error code must be unchanged');
      // Retry-After must be computed from the bucket's true remaining time,
      // not a fixed constant — a refusal early in a bucket must not report
      // the FULL window as the wait.
      expect(
        RegExp(r'Math\.ceil\(\s*\(\s*bucketStartMs\s*\+\s*'
                r'RATE_LIMIT_WINDOW_MS\s*-\s*Date\.now\(\)\s*\)\s*/\s*1000\s*\)')
            .hasMatch(src),
        isTrue,
        reason: 'Retry-After must reflect the bucket boundary, not a '
            'hard-coded window length',
      );
      expect(
        src.contains('RATE_LIMIT_WINDOW_MINUTES * 60'),
        isFalse,
        reason: 'the old fixed-constant Retry-After computation must be gone',
      );
    });

    test('fails OPEN on a consume_quota error — deliberately, unlike verify-payment', () {
      // A DPDP erasure is a legal right; it must not be blocked by a ledger
      // outage. This is the SAME posture the pre-fix code had, preserved
      // through the fix rather than accidentally flipped.
      final rpcIdx = src.indexOf('consume_quota');
      expect(rpcIdx, greaterThanOrEqualTo(0));
      final after = src.substring(rpcIdx);
      final rateErrGuard = RegExp(r'if\s*\(\s*rateErr\s*\)').firstMatch(after);
      expect(rateErrGuard, isNotNull,
          reason: 'the error path must be checked explicitly');
      // Between the error check and the next `else if` there must be NO
      // `return` — a fail-CLOSED mutation would insert one here.
      final elseIfIdx = after.indexOf('else if', rateErrGuard!.end);
      expect(elseIfIdx, greaterThan(rateErrGuard.end),
          reason: 'the fail-open branch must fall through to the '
              'usedCount check, not short-circuit into it');
      final errorBranch = after.substring(rateErrGuard.end, elseIfIdx);
      expect(
        RegExp(r'\breturn\b').hasMatch(errorBranch),
        isFalse,
        reason: 'a `return` inside the error branch would make this fail '
            'CLOSED — the deliberate choice here is fail OPEN',
      );
      expect(errorBranch, contains('console.warn'),
          reason: 'a fail-open outcome must still be observable in logs');
    });

    test('the retired channel and its phantom-column insert are GONE', () {
      // Comment-stripped source: this file's own header (uncommented copy)
      // still names both for historical explanation, so this assertion runs
      // against `src`, not the raw file, or it would fail against itself.
      expect(src.contains('delete_account_attempt'), isFalse,
          reason: 'the dead channel literal must not appear in live code');
      expect(src.contains('prompt_snippet'), isFalse,
          reason: 'the phantom column must not appear in live code');
      expect(src.contains('response_snippet'), isFalse,
          reason: 'the second phantom column must not appear in live code');
      // NARROWLY scoped to ai_coach_interactions — delete-account still
      // legitimately writes an audit row to account_deletion_log (step 7,
      // unrelated to this fix), and a bare `.insert({` check would match
      // that too.
      expect(
        RegExp(r'\.from\("ai_coach_interactions"\)').hasMatch(src),
        isFalse,
        reason: 'no read or write of ai_coach_interactions must remain in '
            'this file at all — consume_quota is the only rate-limit write '
            'now, and the audit insert below goes to account_deletion_log',
      );
    });

    test('the source-counter allowlist is ratcheted to 0', () {
      // sweep() flags count > allowed, so an allowlist left at 1 would let a
      // REVERT to the count-then-insert pattern pass silently. 0 converts the
      // entry from permissive to proof-of-landing.
      final lib =
          File('scripts/usage_counter_source_lib.dart').readAsStringSync();
      expect(
        RegExp(r"'supabase/functions/delete-account/index\.ts':\s*0")
            .hasMatch(lib),
        isTrue,
        reason: 'delete-account must hold ZERO legacy quota counters now',
      );
    });
  });
}
