// Writer -> reader contract for the SoT concept `usage_quota_ledger`
// (OI-162 slice 1, diagnose d3a7f1).
//
// WRITER: `consume_quota()` — the ONLY thing that may write usage_counters.
// DELETER: `cleanup_usage_counters()` — the ONLY thing that may delete from it.
// READERS: none yet. Slice 1 is deliberately inert infrastructure.
//
// THE CONTRACT SLICE 1 ESTABLISHES: exactly one writer, exactly one deleter, and
// no direct table access from anywhere else. The whole point of the ledger is
// that quota state stops being an incidental by-product of a table other code
// writes for unrelated reasons — which is precisely how `ai_coach_interactions`
// became a quota source that a nightly prune could reset.
//
// ⚠ THE "NO READERS YET" ASSERTION IS EXPECTED TO FAIL IN SLICE 2, BY DESIGN.
// When the first call site migrates, update this file to name that reader —
// do NOT delete the assertion. Its value is that slice 1's "nothing calls it"
// claim is mechanically true rather than merely asserted in a plan.
//
// ⚠ THAT PREDICTION CAME TRUE IN SLICE 3a (2026-09-07), one slice later than
// forecast: slice 2 wired the three cap TRIGGERS, which live in-database and so
// never appeared in `_appSources()`. `weekly-report/index.ts` is the FIRST
// application-code caller, and it broke both absolutes below — in the full
// suite, in a file this batch never opened, exactly the class CLAUDE.md §4.9
// warns about twice and whose slice-2 row literally says "expect this again in
// slices 3-4".
//
// The absolutes are now ALLOWLISTS rather than `isEmpty`. That is deliberately
// STRONGER than what they replaced, not weaker: an `isEmpty` assertion has to
// be destroyed the moment any legitimate caller appears, and destroying it
// removes the guard entirely. An allowlist survives every legitimate migration
// and still fails on an UNEXPECTED one — which is the thing actually worth
// catching. Add a slice's new call site here in the SAME commit that migrates
// it, with the reason; never widen it to make a red run green.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripSqlComments(String sql) => sql
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

String _stripDartLikeComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

/// Every `.dart` under lib/ and every Edge Function `index.ts`, comment-stripped.
Iterable<MapEntry<String, String>> _appSources() sync* {
  for (final d in ['lib', 'supabase/functions']) {
    final dir = Directory(d);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart') && !p.endsWith('.ts')) continue;
      yield MapEntry(p, _stripDartLikeComments(f.readAsStringSync()));
    }
  }
}

void main() {
  group('usage_quota_ledger — writer side', () {
    late String migration;

    setUpAll(() {
      migration = _stripSqlComments(
          File('supabase/migrations/128_usage_counters.sql').readAsStringSync());
    });

    test('consume_quota is the only INSERT into usage_counters', () {
      final inserts =
          RegExp(r'INSERT\s+INTO\s+public\.usage_counters', caseSensitive: false)
              .allMatches(migration)
              .length;
      expect(inserts, 1,
          reason: 'Exactly one INSERT — inside consume_quota. A second write '
              'path would reintroduce the defect the ledger exists to remove: '
              'quota state written by something that is not the quota gate.');
    });

    test('cleanup_usage_counters is the only DELETE', () {
      final deletes =
          RegExp(r'DELETE\s+FROM\s+public\.usage_counters', caseSensitive: false)
              .allMatches(migration)
              .length;
      expect(deletes, 1,
          reason: 'Exactly one DELETE — the retention job. Any other deleter '
              'is an unaudited way for a quota to reset, which is the entire '
              'bug class (OI-162).');
    });

    test('no UPDATE statement touches the table outside the upsert', () {
      // The ON CONFLICT DO UPDATE inside consume_quota is the only mutation of
      // an existing row. A standalone `UPDATE public.usage_counters` would be a
      // second, unguarded increment path.
      expect(
          RegExp(r'^\s*UPDATE\s+public\.usage_counters', multiLine: true,
                  caseSensitive: false)
              .hasMatch(migration),
          isFalse);
    });
  });

  group('usage_quota_ledger — reader side (slice 2: three, all in-database)',
      () {
    // ⚠ Slice 1 predicted these assertions would FAIL in slice 2. They did not,
    // and the reason is worth keeping: slice 2's three readers are Postgres
    // TRIGGERS (migration 129), and `_appSources()` scans lib/ +
    // supabase/functions/ only. So "no APPLICATION code reads the ledger"
    // remains true and is still the contract worth pinning — the ledger is
    // reached through consume_quota, never by a direct client/EF query.
    // A prediction that misses in a benign direction still has to be corrected,
    // or the next reader trusts the stale half.
    test('only the named call sites touch usage_counters directly', () {
      // WHY weekly-report is allowed a direct SELECT: its gate must answer
      // "has this user ever had their one free report?" BEFORE spending a
      // Gemini 2.5 Pro call. consume_quota is a WRITE -- asking it that question
      // burns the lifetime unit on every model outage, with no refund path. So
      // the read is ADVISORY and the write stays authoritative: .maybeSingle()
      // feeds the 403, consume_quota's -1 is what actually enforces. The
      // atomicity concern below is untouched, because no quota is DECIDED from
      // the direct read alone.
      //
      // ai-media-proxy (OI-162 slice 3b) is the SAME shape for the same
      // reason: its gate must answer "has this free user spent all 5 lifetime
      // image analyses?" BEFORE paying for a Gemini call, and asking
      // consume_quota that question would burn a lifetime unit on every model
      // outage with no refund path. Advisory .maybeSingle() read; authoritative
      // consume_quota after the insert.
      const allowed = {
        'supabase/functions/weekly-report/index.ts',
        'supabase/functions/ai-media-proxy/index.ts',
      };
      final offenders = <String>[];
      for (final e in _appSources()) {
        if (e.value.contains('usage_counters') && !allowed.contains(e.key)) {
          offenders.add(e.key);
        }
      }
      expect(offenders, isEmpty,
          reason: 'The ledger is reached through consume_quota() inside the '
              'database, never by a direct query from client or Edge Function '
              'code. An ADVISORY read paired with an authoritative '
              'consume_quota (the weekly-report shape) is the ONLY accepted '
              'exception and belongs in `allowed`, with its reason, in the '
              'same commit that adds it. Found: $offenders');

      // MIRROR: an allowlist must not outlive what it exempts. A stale entry is
      // invisible -- it silently exempts a file that no longer needs it, and
      // the next reader takes it as evidence the file still does this.
      for (final a in allowed) {
        expect(File(a).readAsStringSync(), contains('usage_counters'),
            reason: '$a is allowlisted but no longer touches usage_counters -- '
                'remove the dead exemption rather than leaving it.');
      }
    });

    test('only the named call sites invoke consume_quota directly', () {
      // A trigger is the enforcement point wherever a trigger CAN be one. It
      // cannot be here: nothing is INSERTed at the moment weekly-report decides
      // to spend the lifetime unit, so there is no row for a trigger to fire
      // on. The EF calls the RPC itself, which keeps the atomic
      // ON CONFLICT ... WHERE used < p_limit guard that is the whole point.
      //
      // ai-media-proxy (slice 3b) DOES have an INSERT a trigger could hang off,
      // so the reasoning differs and is worth stating rather than assuming.
      // A trigger was rejected on two specific grounds: it cannot return the
      // new count to the EF, so the "X of 5 left" display would need a THIRD
      // round trip (the double-count collapse is half the slice's value); and
      // it RAISES on exhaustion, which would make the unconditional
      // conversation-log insert throw and force the refusal path to be
      // restructured around an exception.
      const allowed = {
        'supabase/functions/weekly-report/index.ts',
        'supabase/functions/ai-media-proxy/index.ts',
      };
      final offenders = <String>[];
      for (final e in _appSources()) {
        if (e.value.contains('consume_quota') && !allowed.contains(e.key)) {
          offenders.add(e.key);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Slice 2 wires the three cap TRIGGERS, which call '
              'consume_quota in-database. A direct call is permitted only '
              'where no INSERT exists for a trigger to hang off -- add it to '
              '`allowed` with that reason. Found: $offenders');
      for (final a in allowed) {
        expect(File(a).readAsStringSync(), contains('consume_quota'),
            reason: '$a is allowlisted but no longer calls consume_quota -- '
                'remove the dead exemption.');
      }
    });

    test('the THREE remaining legacy quota readers are still on the old table',
        () {
      // Stated as an invariant so no batch can be misread as having fixed the
      // whole bug. Nine quota readers existed; slice 2 moved THREE (the chat /
      // vision / food_text cap triggers), slice 3a moved ONE (weekly-report),
      // and slice 3b moved TWO (ai-media-proxy's free-image lifetime meter and
      // its dead client twin, which was DELETED rather than repointed —
      // repointing a method with zero callers would be inventing a reader).
      // THREE remain, across three files.
      //
      // ⚠ THIS TEST WAS GREEN WHILE ITS OWN TITLE WAS FALSE. It said SIX and
      // checked exactly ONE representative file (ai-media-proxy), so slice 3a
      // moving weekly-report off the old table changed nothing it observed.
      // That is membership-is-not-completeness: a contains() over one member of
      // a set cannot see another member leave. Every remaining surface is now
      // pinned BY NAME, and the count is asserted from the list rather than
      // written in prose.
      //
      // ⚠ SECOND-ORDER, found in slice 3b: the paragraph above CLAIMED the
      // count was asserted from the list, and it was not — the number lived
      // only in the title and in this comment, both prose. The claim is now
      // true (see the length expectation below). A comment describing a
      // protection that does not exist is worse than no comment: it stops the
      // next reader from adding the protection.
      const stillLegacy = <String, String>{
        'supabase/functions/ai-media-proxy/index.ts':
            'countProImageAnalysesToday only — the dormant PRO image cap '
                '(OI-153). Its free-image sibling moved in slice 3b.',
        'supabase/functions/delete-account/index.ts':
            'delete-attempt rate limit (slice 4, catastrophic)',
        'supabase/functions/verify-payment/index.ts':
            'payment-verify rate limit (slice 4, catastrophic)',
      };
      expect(stillLegacy, hasLength(3),
          reason: 'The title says THREE. If a slice migrated one, move it out '
              'of the map AND update the title in the same commit -- a count '
              'in prose that no assertion reads is exactly how this test went '
              'stale before.');
      for (final e in stillLegacy.entries) {
        expect(File(e.key).readAsStringSync(), contains('ai_coach_interactions'),
            reason: '${e.key} was expected to STILL derive a quota from '
                'ai_coach_interactions (${e.value}). If a slice migrated it, '
                'update this map and the count in the title -- do not delete '
                'the entry.');
      }

      // MIRROR, and the half whose absence let this test go stale: weekly-report
      // must NOT be back on the old table for its QUOTA. It still INSERTs the
      // report row there (that insert is the sole persisted copy), so the file
      // legitimately contains the table name -- what must never return is a
      // COUNT of that channel feeding the gate.
      final weekly =
          File('supabase/functions/weekly-report/index.ts').readAsStringSync();
      expect(weekly.contains('.eq("channel", "weekly_report")'), isFalse,
          reason: 'weekly-report is counting its own channel again -- slice 3a '
              'reverted and the one free report will regenerate.');
      expect(weekly, contains('usage_counters'),
          reason: 'weekly-report must still read the ledger.');

      // MIRROR for slice 3b, and it is REQUIRED for the same reason the
      // weekly-report one is. ai-media-proxy legitimately still contains
      // 'ai_coach_interactions' -- the unconditional conversation-log insert
      // AND the OI-153 PRO counter -- so the stillLegacy contains() above
      // cannot distinguish "the free meter came back" from "the file still
      // has its other two legitimate uses". Pin what must never return.
      final media =
          File('supabase/functions/ai-media-proxy/index.ts').readAsStringSync();
      expect(media.contains('.eq("channel", "free_image_analysis")'), isFalse,
          reason: 'ai-media-proxy is counting the free-image channel again -- '
              'slice 3b reverted, and the 5 lifetime free analyses will reset '
              'every time rolling-context prunes the log.');
      expect(media.contains('countFreeImageAnalyses'), isFalse,
          reason: 'the row-counting gate is back by name. A revert restores '
              'the old function, so pin the symbol as well as the query '
              'shape -- either one alone is one rename away from silent.');
      expect(media, contains('usage_counters'),
          reason: 'ai-media-proxy must still READ the ledger (advisory gate).');
      expect(media, contains('consume_quota'),
          reason: 'ai-media-proxy must still WRITE the ledger. Losing this '
              'while keeping the read leaves a gate that can never fire: '
              'used stays 0 forever and every analysis is granted.');
    });
  });
}
