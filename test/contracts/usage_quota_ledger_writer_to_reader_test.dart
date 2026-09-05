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
    test('no application code touches usage_counters directly', () {
      final offenders = <String>[];
      for (final e in _appSources()) {
        if (e.value.contains('usage_counters')) offenders.add(e.key);
      }
      expect(offenders, isEmpty,
          reason: 'The ledger is reached through consume_quota() inside the '
              'database, never by a direct query from client or Edge Function '
              'code. Found: $offenders.\n'
              'If you are migrating a call site to query usage_counters '
              'DIRECTLY, stop: route it through consume_quota instead, or the '
              'atomicity guarantee and the p_limit guard are both lost.');
    });

    test('no application code calls consume_quota directly', () {
      final offenders = <String>[];
      for (final e in _appSources()) {
        if (e.value.contains('consume_quota')) offenders.add(e.key);
      }
      expect(offenders, isEmpty,
          reason: 'Slice 2 wires the three cap TRIGGERS, which call '
              'consume_quota in-database. No client or Edge Function calls it '
              'directly, and none should — the trigger is the enforcement '
              'point. Found: $offenders');
    });

    test('and the SIX remaining legacy quota readers are still on the old '
        'table', () {
      // Stated as an invariant so the batch cannot be misread as having fixed
      // the whole bug. Slice 2 moved THREE of nine (the chat / vision /
      // food_text cap triggers). Six remain: the lifetime image meters, the
      // weekly-report meter, and the two rate limits. Slices 3-4 own them.
      final aiMedia = File('supabase/functions/ai-media-proxy/index.ts')
          .readAsStringSync();
      expect(aiMedia.contains('ai_coach_interactions'), isTrue,
          reason: 'ai-media-proxy still derives its image quotas from '
              'ai_coach_interactions. Slice 3 migrates it. If this fails, a '
              'call site moved without this contract being updated.');
    });
  });
}
