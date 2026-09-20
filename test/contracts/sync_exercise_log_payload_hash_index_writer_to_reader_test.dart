import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  group('exlogPayloadFingerprint', () {
    test('same payload -> same fingerprint, 36-char UUID shape', () {
      final summary = {'exercise_id': 'squat', 'reps': 30};
      final sets = [
        {'set_number': 1, 'reps': 10},
        {'set_number': 2, 'reps': 10},
      ];
      final fp1 = SyncService.exlogPayloadFingerprint(summary, sets);
      final fp2 = SyncService.exlogPayloadFingerprint(
          Map.of(summary), sets.map((s) => Map.of(s)).toList());
      expect(fp1, fp2);
      expect(fp1.length, 36);
      expect(fp1[8], '-');
    });

    test('a changed summary field flips the fingerprint', () {
      final sets = [
        {'set_number': 1, 'reps': 10}
      ];
      final fp1 = SyncService.exlogPayloadFingerprint({'reps': 30}, sets);
      final fp2 = SyncService.exlogPayloadFingerprint({'reps': 31}, sets);
      expect(fp1, isNot(fp2));
    });

    test('a changed per-set field flips the fingerprint (this is the edit-not-skipped proof)',
        () {
      final summary = {'exercise_id': 'squat'};
      final fp1 = SyncService.exlogPayloadFingerprint(
          summary, [{'set_number': 1, 'weight_kg': 60}]);
      final fp2 = SyncService.exlogPayloadFingerprint(
          summary, [{'set_number': 1, 'weight_kg': 65}]); // edited weight
      expect(fp1, isNot(fp2));
      expect(
        SyncService.exlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: fp1,
          currentFingerprint: fp2,
        ),
        isFalse,
      );
    });

    test('an added/removed set flips the fingerprint (key-set change, not just value)', () {
      final summary = {'exercise_id': 'squat'};
      final fp1 = SyncService.exlogPayloadFingerprint(
          summary, [{'set_number': 1, 'reps': 10}]);
      final fp2 = SyncService.exlogPayloadFingerprint(summary, [
        {'set_number': 1, 'reps': 10},
        {'set_number': 2, 'reps': 8},
      ]);
      expect(fp1, isNot(fp2));
    });
  });

  group('exlogShouldSkipUpsert', () {
    test('matching fingerprint -> skip', () {
      expect(
        SyncService.exlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: 'abc',
          currentFingerprint: 'abc',
        ),
        isTrue,
      );
    });

    test('null stored fingerprint (never pushed) -> always push', () {
      expect(
        SyncService.exlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: null,
          currentFingerprint: 'abc',
        ),
        isFalse,
      );
    });

    test('kill-switch enabled -> always push, even on exact match', () {
      expect(
        SyncService.exlogShouldSkipUpsert(
          killSwitchDisabled: true,
          storedFingerprint: 'abc',
          currentFingerprint: 'abc',
        ),
        isFalse,
      );
    });
  });

  group('exlogPrunedHashIndex', () {
    test('drops entries for keys no longer present, keeps live ones intact', () {
      final pruned = SyncService.exlogPrunedHashIndex(
        {'exlog_a': 'fp_a', 'exlog_b': 'fp_b', 'exlog_deleted': 'fp_x'},
        {'exlog_a', 'exlog_b'},
      );
      expect(pruned, {'exlog_a': 'fp_a', 'exlog_b': 'fp_b'});
    });

    test('empty liveKeys -> empty index', () {
      expect(SyncService.exlogPrunedHashIndex({'exlog_a': 'fp'}, {}), isEmpty);
    });
  });

  group('Hive round-trip', () {
    // Matches the sched template's own setUp/tearDown + createTemp shape
    // (plan-review round 1, finding M5) — a fixed directory path carries
    // state across runs; setUpAll/tearDownAll run once for the whole group
    // instead of once per test.
    late Directory tempDir;
    late Box box;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exlog_hash_index_test_');
      Hive.init(tempDir.path);
      box = await Hive.openBox('exlog_hash_index_roundtrip_test');
    });
    tearDown(() async {
      await box.close();
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('a fingerprint stored, read back through dynamic-typed Hive Map, still drives the skip decision', () async {
      final fp = SyncService.exlogPayloadFingerprint({'a': 1}, []);
      await box.put('sync_exlog_payload_hash_index', {'exlog_x': fp});

      final rawIndex = box.get('sync_exlog_payload_hash_index');
      final index = <String, String>{};
      (rawIndex as Map).forEach((k, v) {
        if (k is String && v is String) index[k] = v;
      });

      expect(
        SyncService.exlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: index['exlog_x'],
          currentFingerprint: fp,
        ),
        isTrue,
      );
    });
  });

  group('resetJourney clears the index (source contract)', () {
    test('sync_exlog_payload_hash_index is cleared by resetJourney, mirroring '
        'the sched key it sits beside', () {
      final src =
          File('lib/features/dev/simulation_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> resetJourney(');
      expect(start, isNot(-1), reason: 'resetJourney must exist at this name');
      final end = src.indexOf('\n  }\n', start);
      final body = src.substring(start, end == -1 ? src.length : end);
      expect(body, contains("'sync_exlog_payload_hash_index'"),
          reason: 'a stale fingerprint entry survives a sim reset and '
              'mis-skips the re-drive push — see the sync_sched_payload_hash_index '
              'precedent this mirrors');
    });
  });

  // OI-204 Step 7b — spec §8's atomicity behavioral test requires simulating a
  // per-set network failure and asserting no fingerprint is stored. Checked
  // (grep): `_supabase` is `final SupabaseService _supabase =
  // SupabaseService.instance;` (sync_service.dart:219) — a singleton with no
  // constructor injection, and `grep -rln "MockSupabase|FakeSupabase|_supabase
  // = Mock|SupabaseService(" test/` returns NOTHING. `_syncScheduledWorkouts`
  // itself has no such test either — its own "store-on-200-only" group
  // (sync_scheduled_payload_hash_index_writer_to_reader_test.dart) is this
  // SAME call-site-count source-grep, not a live failure simulation. No DI
  // seam exists anywhere in this codebase today; adding one is a separate,
  // reviewed refactor decision, out of scope for this delta-sync fix (per the
  // brief's explicit instruction not to invent one here). This test covers
  // the "exactly one store site" half of the atomicity property mechanically;
  // the "only reached when the flag is true" half is covered statically by
  // scripts/check_sync_hash_skip_atomicity.dart (mutation-proven,
  // docs/audit/gate_test_ledger.yaml). See docs/sot_registry.yaml's
  // `sync_exercise_log_payload_hash_index` entry, `presence_only: true` on
  // the atomicity sub-property, for the corresponding `presence_only_reason:`.
  group('exact store call-site count (spec §8 item 4)', () {
    test('the guarded exlogHashIndex[key] = fp store appears exactly once in '
        'sync_workout.dart -- a second site would bypass the single-guard-scan '
        'scripts/check_sync_hash_skip_atomicity.dart depends on', () {
      final src =
          File('lib/core/services/sync/sync_workout.dart').readAsStringSync();
      final matches =
          RegExp(r'exlogHashIndex\[key\]\s*=\s*fp\s*;').allMatches(src);
      expect(matches.length, 1);
    });
  });
}
