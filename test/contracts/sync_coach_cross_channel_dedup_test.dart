// Regression test for audit 2026-05-16 / F6-4
// (sync_coach cross-channel duplicate dedup).
//
// Bug: `_syncCoachInteractions` in `sync_coach.dart` walks Hive `coach_*`
// entries and upserts them with `channel='in_app_orphan'` when they lack a
// server-issued UUID. The server-side 60s dedup at `ai-proxy/index.ts:222-254`
// only catches intra-channel duplicates — it can't see the client orphan
// path. When a user paste the same meal text into BOTH the AI Coach chat
// (→ Hive coach_<ms> → orphan upsert) AND the Nutrition AI Text tab
// (→ server inserts `food_text_analysis` placeholder) within ~90s, the
// table ends up with TWO rows for one logical turn.
//
// Live audit found 8 such cross-channel pairs (2026-05-11 → 2026-05-15).
//
// Fix: before the orphan upsert, SELECT for ANY existing row from this user
// with the same `user_message` within the last 5 minutes. If hit, skip the
// orphan write — the server row IS the source of truth for that turn
// regardless of channel. Stamp the Hive entry with the cloud id so future
// cold restores collapse cleanly on the `coach_<ts>` derivation path.
//
// This is a source-grep contract test that scans `sync_coach.dart` for the
// canonical pattern. If any future edit removes the cross-channel SELECT
// from the orphan path, the test fails before ship.
//
// closes-diagnose: 2026-05-16-sync-coach-cross-channel-dedup

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sync_coach _syncCoachInteractions cross-channel dedup', () {
    late String src;
    late String methodSlice;

    setUpAll(() {
      final file = File('lib/core/services/sync/sync_coach.dart');
      expect(file.existsSync(), isTrue);
      src = file.readAsStringSync();

      final start = src.indexOf('Future<void> _syncCoachInteractions(');
      expect(start, isNot(-1),
          reason: '_syncCoachInteractions method must exist');
      final end = (start + 4500).clamp(0, src.length);
      methodSlice = src.substring(start, end);
    });

    test('method SELECTs from ai_coach_interactions before orphan upsert', () {
      // The dedup query must select from ai_coach_interactions, filtered by
      // user_id + user_message + a recent created_at cutoff.
      final hasSelect = methodSlice.contains(".select('id");
      expect(hasSelect, isTrue,
          reason:
              '_syncCoachInteractions must SELECT existing rows before the '
              'orphan upsert. Otherwise cross-channel duplicates accumulate '
              '(audit F6-4: 8 pairs in 5 days).');
    });

    test('dedup window is bounded (5 minute lookback)', () {
      // Anti-regression: the lookback must be a finite duration, not
      // open-ended. 5 minutes is the documented window (long enough to
      // catch user double-pastes, short enough that a separate intentional
      // log of identical text 10 min later goes through).
      final hasMinutes = methodSlice.contains('Duration(minutes:');
      expect(hasMinutes, isTrue,
          reason:
              'Cross-channel dedup must use a bounded Duration(minutes: ...) '
              'lookback. Open-ended dedup would silently drop legitimate '
              'repeated logs (e.g. user re-logs the same breakfast next day).');
    });

    test('on dedup hit, skip orphan upsert via continue', () {
      // The dedup hit path must use `continue` to skip the orphan upsert
      // (not just early-return — the for loop must continue to next entry).
      // Detect by ensuring `continue` appears between the dedup SELECT and
      // the orphan upsert literal.
      final selectIdx = methodSlice.indexOf(".select('id");
      final upsertIdx = methodSlice.indexOf("'channel': 'in_app_orphan'");
      expect(selectIdx, isNot(-1));
      expect(upsertIdx, isNot(-1));
      expect(selectIdx, lessThan(upsertIdx),
          reason: 'SELECT dedup must happen BEFORE the orphan upsert');
      final between = methodSlice.substring(selectIdx, upsertIdx);
      expect(between.contains('continue;'), isTrue,
          reason:
              'On dedup hit, must `continue;` to skip the orphan upsert. '
              'Without the continue, the orphan write proceeds and produces '
              'the duplicate row the test is meant to prevent.');
    });

    test('on dedup hit, Hive entry is stamped with cloud id (for restore collapse)', () {
      // Stamping the Hive entry with `existing['id']` lets future cold
      // restores collapse cloud→local round-trips (Test #12.8 / Bug #1
      // pattern in _restoreCoachInteractions). Without it, future restores
      // would create a new sibling Hive key.
      final selectIdx = methodSlice.indexOf(".select('id");
      final upsertIdx = methodSlice.indexOf("'channel': 'in_app_orphan'");
      final between = methodSlice.substring(selectIdx, upsertIdx);
      expect(between.contains("existing['id']"), isTrue,
          reason:
              'On dedup hit, the Hive entry must be re-put with the cloud '
              "row's id so subsequent restores collapse rather than create "
              'sibling rows.');
      expect(between.contains('coachBox.put('), isTrue,
          reason:
              'The cloud-id stamp must be persisted via coachBox.put(key, ...).');
    });
  });
}
