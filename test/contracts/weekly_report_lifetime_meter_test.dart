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
// Deno BEHAVES that way, and there is no Deno on this machine. The behavioural
// half is `test/sql/oi46_daily_cap_triggers_live_verify.sql`'s `slice3a_*`
// labels plus a branch-deployed read-path check — see the plan's §5. Saying so
// because rule 21 is emphatic that a source-grep counts for PRESENCE only.

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
      // Quote-agnostic: the TypeScript uses double quotes, and pinning one
      // style makes the assertion fail on a purely cosmetic reformat.
      expect(
        RegExp('[\'"]weekly_report_free[\'"]').hasMatch(src),
        isTrue,
        reason: 'the quota_key names the FREE gate specifically — PRO is '
            'exempt, so this key meters only the free tier',
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
      final consumeIdx = src.indexOf('consume_quota');
      expect(consumeIdx, greaterThanOrEqualTo(0));
      final before = src.substring(0, consumeIdx);
      expect(
        RegExp(r'if\s*\(\s*!hasPro\s*\)').hasMatch(before),
        isTrue,
        reason: 'the consume must be gated on !hasPro',
      );
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
