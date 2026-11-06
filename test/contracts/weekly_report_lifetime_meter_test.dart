// OI-162 slice 3a — `weekly-report`'s first-free gate reads `usage_counters`,
// not a log that `rolling-context` prunes.
//
// THE BUG: the gate counted rows in `ai_coach_interactions` with
// channel='weekly_report' and no date bound. Those rows are non-`app_event`, so
// `rolling-context` summarises and DELETES all but the newest 10 once a user
// passes 50 — and a LIFETIME quota has no window to survive deletion on. The
// one free Gemini 2.5 Pro report silently regenerated.
//
// SCOPE — presence only, deliberately. These are source greps over one Edge
// Function. They prove the code SAYS the right thing; they cannot prove live
// Deno BEHAVES that way, and there is no Deno on this machine.
//
// ⚠ WHAT THE OTHER HALF DOES AND DOES NOT COVER, stated precisely because this
// header previously claimed coverage that did not exist — it cited
// `oi46_daily_cap_triggers_live_verify.sql`'s `slice3a_*` labels when that file
// contained ZERO occurrences of the string. The labels exist now (added in this
// same commit, run live, mutation-proven on both halves of the retention
// pairing), but they verify the LEDGER — the 'epoch' sentinel, the one-then-
// refused meter, retention's two-sided predicate. They execute no Edge Function
// and would pass unchanged against the PRE-slice-3a weekly-report.
//
// So nothing anywhere yet proves the EF itself reads the ledger at runtime.
// That is the post-deploy read-path check in the plan's §5, and it has NOT run
// — the deploy needs its own explicit authorization. Until it does, this
// slice's EF half rests on source greps, exactly as rule 21 says to assume.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Edge Function source, with `//` comments stripped so an assertion can
/// never be satisfied by prose ABOUT the code instead of the code.
String _ef() {
  final raw =
      File('supabase/functions/weekly-report/index.ts').readAsStringSync();
  return raw
      .split('\n')
      .map((l) {
        // ⚠ Must not eat `https://`. The naive indexOf('//') truncates every
        // import line at the protocol separator, silently shrinking the
        // haystack every later assertion greps. Caught by this file's own
        // first red run, whose output showed `from "https:` with the rest gone.
        final i = RegExp(r'(?<!:)//').firstMatch(l)?.start ?? -1;
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('OI-162 slice 3a — weekly-report lifetime meter', () {
    late String src;

    setUpAll(() => src = _ef());

    test('consumes the ledger under the free-tier quota key', () {
      expect(src, contains('consume_quota'),
          reason: 'the gate must delegate to the atomic ledger entry point');
      // ⚠ ASSOCIATION, not membership. B-pass 4d7054d4 finding 1
      // mutation-proved the presence form worthless: retargeting the RPC's
      // `p_quota_key` to a different hardcoded literal — genuine writer/reader
      // drift, the exact class OI-162 exists to fix — left every assertion
      // GREEN, because each side independently contained a right-looking
      // string. Both sides must be pinned to the SAME CONSTANT.
      expect(
        RegExp('const WEEKLY_REPORT_FREE_QUOTA_KEY = [\'"]weekly_report_free[\'"]')
            .hasMatch(src),
        isTrue,
        reason: 'the key is declared exactly once, as a constant',
      );
      expect(
        RegExp(r'p_quota_key:\s*WEEKLY_REPORT_FREE_QUOTA_KEY').hasMatch(src),
        isTrue,
        reason: 'the WRITER must pass the CONSTANT, never a literal — a '
            'hardcoded literal here is drift no presence check can see',
      );
      expect(
        RegExp(r'\.eq\(\s*"quota_key"\s*,\s*WEEKLY_REPORT_FREE_QUOTA_KEY\s*\)')
            .hasMatch(src),
        isTrue,
        reason: 'the READER must filter on the SAME constant',
      );
    });

    test('uses the epoch sentinel, so retention can never delete the row', () {
      // cleanup_usage_counters()'s predicate is TWO-SIDED:
      //   window_start <> 'epoch' AND window_start < now() - interval '7 days'
      // An epoch row is excluded by the FIRST conjunct, permanently. A windowed
      // timestamp here would make a LIFETIME quota expire after 7 days —
      // exactly the bug this slice fixes, reintroduced inside the new table.
      expect(src, contains('1970-01-01T00:00:00+00:00'),
          reason: 'lifetime quotas use the epoch sentinel window_start');
    });

    test('the gate READS usage_counters, not the prunable log', () {
      // The whole point of the slice. Without this the ledger would increment
      // while the refusal decision kept reading the pruned table — the meter
      // moving and nothing reading it.
      expect(src, contains('.from("usage_counters")'),
          reason: 'the advisory read must target the ledger');
      expect(
        RegExp(r'\.eq\(\s*"channel"\s*,\s*"weekly_report"\s*\)').hasMatch(src),
        isFalse,
        reason: 'no quota read may still count ai_coach_interactions rows by '
            'channel — that is the defect',
      );
    });

    test('the advisory read is .maybeSingle(), never .single()', () {
      // ⚠ THE LOCKOUT GUARD. A value-select has THREE outcomes where the old
      // count query had two: row / error / ABSENT (`data: null, error: null`).
      // `.single()` throws PGRST116 on an absent row, which arrives as an error
      // and trips the fail-closed branch. Every user is in the absent state at
      // cutover, so that would refuse EVERY first-time free user permanently.
      final readBlock = RegExp(
        r'\.from\("usage_counters"\)[\s\S]{0,400}?;',
      ).firstMatch(src);
      expect(readBlock, isNotNull,
          reason: 'could not locate the usage_counters read at all');
      expect(readBlock!.group(0), contains('.maybeSingle()'));
      expect(
        readBlock.group(0)!.contains('.single()') &&
            !readBlock.group(0)!.contains('.maybeSingle()'),
        isFalse,
        reason: '.single() throws on an absent row; an absent row is a '
            'legitimate used=0 and must be GRANTED',
      );
    });

    test('an absent row yields used=0, and only an error denies', () {
      // `?? 0` is what makes an absent row a grant. Dropping it — or widening
      // the error ternary to cover absence — is the lockout.
      expect(
        RegExp(r'freeReportQuota\?\.used\s*\?\?\s*0').hasMatch(src),
        isTrue,
        reason: 'an absent ledger row must read as used=0 (GRANT), not as '
            'unreadable (DENY)',
      );
      expect(
        RegExp(r'previousReportError\s*\n?\s*\?\s*false').hasMatch(src),
        isTrue,
        reason: 'a POPULATED error must fail CLOSED — this is the branch the '
            'absent-row case must NOT fall into',
      );
    });

    test('PRO does not consume', () {
      // :118 never refuses PRO, and reports_screen fires on every screen open,
      // so an unconditional consume would burn a PRO user's lifetime key on
      // their first visit. Same exemption-before-consume shape as
      // enforce_chat_app_daily_limit (migration 129).
      // ⚠ The guard must WRAP the call, not merely appear somewhere above it.
      // B-pass 4d7054d4 finding 2 mutation-proved the weaker form worthless: a
      // decoy `if (!hasPro) {}` elsewhere plus the real guard changed to
      // `if (true)` — PRO burning the free-tier unit, the exact regression the
      // code's own comment warns about — left all 9 assertions GREEN.
      final consumeIdx = src.indexOf('consume_quota');
      expect(consumeIdx, greaterThanOrEqualTo(0));
      // ⚠ PROXIMITY IS NOT CONTAINMENT — and the first fix for this finding got
      // that wrong. A gap check (`consumeIdx - guard.end < 200`) is still
      // satisfied by a decoy `if (!hasPro && !reportLogError) { }` sitting just
      // above an `if (true) {` that actually wraps the RPC. Re-running the
      // B-pass's own mutation caught it: reds=0.
      //
      // What actually holds: between the guard and the RPC there must be NO
      // other `if (`. Anything intervening means the guard found is not the one
      // in force.
      final guard = RegExp(r'if\s*\(\s*!hasPro\s*&&\s*!reportLogError\s*\)')
          .firstMatch(src);
      expect(guard, isNotNull,
          reason: 'the consume must be gated on !hasPro AND on the insert '
              'having succeeded');
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
      // ⚠ Deliberately STRICTER than the invariant: this also reddens on an
      // intervening `if` nested legitimately INSIDE the real guard, which would
      // still wrap the call correctly. Verified by mutation — inserting
      // `if (Math.random() > 2) { }` between the guard and the RPC reddens it.
      // That conservatism is the right trade for a source grep (it errs toward
      // flagging, never toward missing a decoy), but a future refactor that
      // legitimately needs a branch in there should REPOINT this at the guard's
      // matching brace rather than loosen it back to a proximity check — that
      // is the form the B-pass already mutation-proved worthless.
    });

    test('the ai_coach_interactions insert survives, unconditional', () {
      // It is the ONLY persisted copy of the report text
      // (reports_screen.dart:47 caches one, not a list) and the row a reinstall
      // restores (sync_coach.dart:178-181 restores every channel unfiltered).
      // Replacing it with the consume would be data loss.
      expect(src, contains('channel: "weekly_report"'),
          reason: 'the conversation/report row must still be written');
      expect(src, contains('.from("ai_coach_interactions")'),
          reason: 'the insert target must be unchanged');
    });

    test('the insert PRECEDES the consume', () {
      // ⚠ ORDER IS THE INVARIANT, and nine other assertions stay green on a
      // swap. Consume-then-insert-fails permanently burns a LIFETIME unit AND
      // loses the only copy of the report; insert-then-consume-fails merely
      // under-counts. Source position is a valid proxy for execution order
      // here: the file contains no Promise.all — every query is a sequential
      // await.
      expect(src.contains('Promise.all'), isFalse,
          reason: 'if concurrency is introduced, source order stops proving '
              'execution order and this assertion must be rewritten');
      final insertIdx = src.indexOf('channel: "weekly_report"');
      final consumeIdx = src.indexOf('consume_quota');
      expect(insertIdx, greaterThanOrEqualTo(0));
      expect(consumeIdx, greaterThan(insertIdx),
          reason: 'the insert must run BEFORE the consume');
    });

    test('the OI-162 gate is ratcheted to 0 for this file', () {
      // `sweep()` only flags `count > allowed`, so an allowlist left at 1 would
      // let a REVERT to the old ai_coach_interactions count pass silently.
      // A 0 converts the entry from permissive to proof-of-landing.
      final lib =
          File('scripts/usage_counter_source_lib.dart').readAsStringSync();
      expect(
        RegExp(r"'supabase/functions/weekly-report/index\.ts':\s*0")
            .hasMatch(lib),
        isTrue,
        reason: 'weekly-report now holds ZERO quota counters on the old table',
      );
    });
  });
}
