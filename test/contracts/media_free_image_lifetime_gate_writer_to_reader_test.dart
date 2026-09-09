// OI-162 slice 3b — `ai-media-proxy`'s free-image LIFETIME meter reads
// `usage_counters`, not a log that `rolling-context` prunes.
//
// THE BUG: the gate counted rows in `ai_coach_interactions` with
// channel='free_image_analysis' and NO date bound. Those rows are
// non-`app_event`, so `rolling-context` summarises and DELETES all but the
// newest 10 once a user passes 50 — and a LIFETIME quota has no window to
// survive deletion on. A free user who chatted enough silently regained all 5
// free Gemini image analyses, repeatedly.
//
// SECOND, INDEPENDENT DEFECT fixed in the same change: the old reader was
// fail-OPEN (`if (error) return 0`, `catch (_) { return 0 }`) with a docstring
// arguing fail-open was "safer ... because 0 < 5" — which is precisely when the
// gate does NOT fire. Audit finding CODE-3.
//
// SCOPE — presence only, deliberately. These are source greps over one Edge
// Function. They prove the code SAYS the right thing; they cannot prove live
// Deno BEHAVES that way, and there is no Deno on this machine. CI's
// `deno-edge-functions` job is the only compile proof.
//
// ⚠ WHAT THE OTHER HALF DOES AND DOES NOT COVER. The `slice3b_*` labels in
// `test/sql/oi46_daily_cap_triggers_live_verify.sql` verify the LEDGER — the
// 'epoch' sentinel, the one-then-refused meter, retention's two-sided
// predicate. They execute no Edge Function and would pass unchanged against
// the PRE-slice-3b ai-media-proxy. They are behaviour-invariants, NOT evidence
// this slice landed. Nothing anywhere yet proves the EF reads the ledger at
// RUNTIME; that needs a deploy, which needs its own explicit authorization.
// Until then this slice's EF half rests on source greps, exactly as rule 21
// says to assume.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Edge Function source, with `//` comments stripped so an assertion can
/// never be satisfied by prose ABOUT the code instead of the code. This file
/// is comment-heavy by design, which makes the stripping load-bearing rather
/// than cosmetic: nearly every literal asserted below also appears in a
/// comment explaining it.
String _ef() {
  final raw =
      File('supabase/functions/ai-media-proxy/index.ts').readAsStringSync();
  return raw
      .split('\n')
      .map((l) {
        // ⚠ Must not eat `https://` — the naive indexOf('//') truncates every
        // import line at the protocol separator, silently shrinking the
        // haystack every later assertion greps.
        final i = RegExp(r'(?<!:)//').firstMatch(l)?.start ?? -1;
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('OI-162 slice 3b — ai-media-proxy free-image lifetime meter', () {
    late String src;

    setUpAll(() => src = _ef());

    test('consumes the ledger under the free-image quota key', () {
      expect(src, contains('consume_quota'),
          reason: 'the meter must delegate to the atomic ledger entry point');

      // ⚠ ASSOCIATION, not membership. Slice 3a's B-pass mutation-proved the
      // presence form worthless: retargeting `p_quota_key` to a different
      // literal — genuine writer/reader drift, the exact class OI-162 exists
      // to fix — left every presence assertion green. So pin the ARGUMENT to
      // the constant, and the constant to its value, as two separate links.
      expect(
        RegExp(r'p_quota_key:\s*FREE_IMAGE_ANALYSIS_QUOTA_KEY')
            .hasMatch(src),
        isTrue,
        reason: 'the RPC must be called with the free-image key constant, not '
            'some other literal — retargeting it is silent drift',
      );
      expect(
        RegExp(r'FREE_IMAGE_ANALYSIS_QUOTA_KEY\s*=\s*"free_image_analysis"')
            .hasMatch(src),
        isTrue,
        reason: 'and that constant must still name the free-image quota. '
            'Pinning only the symbol lets its VALUE be changed freely.',
      );
    });

    test('uses the epoch sentinel, so retention can never delete the row', () {
      // `cleanup_usage_counters()`'s predicate is two-sided — `window_start <>
      // 'epoch' AND window_start < now() - interval '7 days'`. A lifetime row
      // is excluded by the FIRST conjunct, permanently. A windowed timestamp
      // here would put the quota back on a 7-day expiry, which is the original
      // bug wearing a new table.
      expect(
        RegExp(r'LIFETIME_WINDOW\s*=\s*"1970-01-01T00:00:00\+00:00"')
            .hasMatch(src),
        isTrue,
        reason: 'the lifetime sentinel must be epoch',
      );
      expect(
        RegExp(r'p_window_start:\s*LIFETIME_WINDOW').hasMatch(src),
        isTrue,
        reason: 'and the RPC must actually pass it',
      );
    });

    test('the gate reads usage_counters and no longer counts the channel', () {
      expect(src, contains('.from("usage_counters")'),
          reason: 'the advisory gate must read the durable ledger');
      expect(
        src.contains('.eq("channel", "free_image_analysis")'),
        isFalse,
        reason: 'counting the pruned log is the bug this slice removes',
      );
      expect(src.contains('countFreeImageAnalyses'), isFalse,
          reason: 'the old row-counting reader must be gone by name too — a '
              'revert restores the function, so pin the symbol as well as the '
              'query shape');
    });

    test('the advisory read uses maybeSingle, never single', () {
      // `.single()` throws PGRST116 on zero rows, which would arrive as an
      // ERROR and — under the fail-closed rule below — refuse every user who
      // has never consumed. That is EVERY free user at cutover, permanently.
      final read = RegExp(
        r'\.from\("usage_counters"\)[\s\S]{0,400}?\.maybeSingle\(\)',
      );
      expect(read.hasMatch(src), isTrue,
          reason: 'the usage_counters read must terminate in .maybeSingle()');
      expect(
        RegExp(r'\.from\("usage_counters"\)[\s\S]{0,400}?\.single\(\)')
            .hasMatch(src),
        isFalse,
        reason: '.single() throws on the absent row that every free user has '
            'at cutover',
      );
    });

    test('an unreadable ledger DENIES; an absent row GRANTS', () {
      // The three outcomes of a value-select, and the third is the dangerous
      // one: `data: null, error: null` is a SUCCESSFUL read of a row that is
      // not there, and must mean used = 0.
      expect(
        RegExp(r'if\s*\(\s*error\s*\)\s*return\s+null\s*;').hasMatch(src),
        isTrue,
        reason: 'a populated error must fail CLOSED (return null -> deny). '
            'The pre-fix code returned 0 here, which GRANTED on every '
            'transient PostgREST failure (CODE-3).',
      );
      expect(
        RegExp(r'data\?\.used[\s\S]{0,40}\?\?\s*0').hasMatch(src),
        isTrue,
        reason: 'an ABSENT row must read as 0 and grant, never as a refusal',
      );
      expect(src, contains('gate_reason: "quota_unavailable"'),
          reason: 'the fail-closed refusal needs its OWN reason. Reusing '
              '"free_image_limit_reached" tells a user who spent nothing that '
              'they spent 5 — a lie on a transient error.');
      // MIRROR: the honest reason must not have REPLACED the real paywall.
      expect(src, contains('gate_reason: "free_image_limit_reached"'),
          reason: 'the genuine at-limit refusal must still exist');
    });

    test('the conversation-log insert survives, unconditional', () {
      // This row is the only persisted copy of the exchange and the restore
      // source (`sync_coach.dart` restores every channel unfiltered). It stops
      // feeding the gate; it does not stop existing.
      expect(src, contains('.from("ai_coach_interactions")'),
          reason: 'the conversation log insert must remain');
      expect(src, contains('channel: interactionChannel'),
          reason: 'and must still carry the resolved channel');
      expect(
        RegExp(r'isFreeImageAnalysis\s*=\s*!isVideo\s*&&\s*!isPro')
            .hasMatch(src),
        isTrue,
        reason: 'the free-image predicate must still be free AND non-video',
      );
    });

    test('the insert PRECEDES the consume', () {
      // Ordering is load-bearing: there is no transaction spanning the two.
      // Consume-then-insert-fails burns a LIFETIME unit AND loses the only
      // copy of the analysis that unit paid for. Insert-then-consume-fails
      // merely under-counts — the recoverable direction.
      final insertIdx = src.indexOf('channel: interactionChannel');
      final consumeIdx = src.indexOf('consume_quota');
      expect(insertIdx, greaterThanOrEqualTo(0));
      expect(consumeIdx, greaterThan(insertIdx),
          reason: 'consume_quota must run AFTER the conversation-log insert');
    });

    test('the consume is CONTAINED BY the insert-succeeded guard', () {
      // ⚠ CONTAINMENT, NOT PROXIMITY. Slice 3a shipped a "fix" here that
      // asserted the guard was within 200 characters of the RPC. That is
      // worthless against the mutation it was written for, because a decoy
      // guard is planted ADJACENT to the real call by construction. The
      // working form: between the guard and the RPC there must be NO other
      // `if (`. Anything intervening means the guard matched is not the one
      // wrapping the call.
      final consumeIdx = src.indexOf('consume_quota');
      expect(consumeIdx, greaterThanOrEqualTo(0));

      final guard =
          RegExp(r'if\s*\(\s*isFreeImageAnalysis\s*&&\s*!interactionLogError\s*\)')
              .firstMatch(src);
      expect(guard, isNotNull,
          reason: 'the consume must be gated on BOTH the free-image predicate '
              'and the insert having succeeded. Ordering alone is not enough: '
              'an insert that FAILED while the consume SUCCEEDED reaches the '
              'same bad end state by another route.');
      expect(consumeIdx, greaterThan(guard!.end),
          reason: 'the guard must precede the consume');

      final between = src.substring(guard.end, consumeIdx);
      expect(
        RegExp(r'\bif\s*\(').hasMatch(between),
        isFalse,
        reason: 'another `if (` sits between the guard and the RPC, so the '
            'guard matched here is NOT the one wrapping the call — that is '
            'exactly what a decoy guard looks like',
      );
      // ⚠ KNOWN LIMIT, stated so nobody reads this as stronger than it is:
      // this would also redden on an `if` nested legitimately INSIDE the real
      // guard. That is deliberate — it fails SAFE. A future change that
      // legitimately needs a branch there should REPOINT this at the guard's
      // closing brace, not delete the assertion.
    });

    test('the post-insert RE-COUNT is gone', () {
      // The old code ran a SECOND full table count after the insert purely to
      // render "X of 5 free analyses left". consume_quota already returns the
      // post-write count, so the round trip is pure waste — and it was a
      // second reader of the pruned log.
      expect(
        RegExp(r'freeImageUsed\s*=\s*await\s+count').hasMatch(src),
        isFalse,
        reason: 'the display must derive from the RPC return, not a re-count',
      );
      expect(
        RegExp(r'freeImageUsed\s*=\s*consumedCount').hasMatch(src),
        isTrue,
        reason: "consume_quota's return IS the post-write count",
      );
      // -1 is a SUCCESSFUL return meaning exhausted, not an error.
      expect(
        RegExp(r'consumedCount\s*===?\s*-1').hasMatch(src),
        isTrue,
        reason: 'the exhaustion sentinel must be handled distinctly from an '
            'RPC error — treating -1 as a failure would fire on every '
            'ordinary race and drown the real under-counts',
      );
    });

    test('the source-counter allowlist is ratcheted to 1', () {
      // `sweep()` flags `count > allowed`, so an allowlist left at its old
      // value would let a REVERT to the row-counting gate pass silently.
      // Ratcheting converts the entry from permissive to proof-of-landing.
      final lib =
          File('scripts/usage_counter_source_lib.dart').readAsStringSync();
      expect(
        RegExp(r"'supabase/functions/ai-media-proxy/index\.ts':\s*1")
            .hasMatch(lib),
        isTrue,
        reason: 'ai-media-proxy must hold exactly ONE legacy counter now — '
            'countProImageAnalysesToday, the dormant PRO cap (OI-153)',
      );
    });
  });
}
