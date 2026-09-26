import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  group('nlogPayloadFingerprint', () {
    test('same payload -> same fingerprint, 36-char UUID shape', () {
      final parent = {'date': '2026-09-19', 'meal_type': 'lunch', 'total_calories': 500};
      final items = [
        {'name': 'rice', 'quantity_g': 150},
      ];
      final fp1 = SyncService.nlogPayloadFingerprint(parent, items);
      final fp2 = SyncService.nlogPayloadFingerprint(
          Map.of(parent), items.map((i) => Map.of(i)).toList());
      expect(fp1, fp2);
      expect(fp1.length, 36);
      expect(fp1[8], '-');
    });

    test('a changed parent field flips the fingerprint', () {
      final items = [{'name': 'rice'}];
      final fp1 = SyncService.nlogPayloadFingerprint({'total_calories': 500}, items);
      final fp2 = SyncService.nlogPayloadFingerprint({'total_calories': 550}, items);
      expect(fp1, isNot(fp2));
    });

    test('an edited item quantity flips the fingerprint (edit-not-skipped proof)', () {
      final parent = {'date': '2026-09-19', 'meal_type': 'lunch'};
      final fp1 = SyncService.nlogPayloadFingerprint(
          parent, [{'name': 'rice', 'quantity_g': 150}]);
      final fp2 = SyncService.nlogPayloadFingerprint(
          parent, [{'name': 'rice', 'quantity_g': 200}]); // edited portion
      expect(fp1, isNot(fp2));
      expect(
        SyncService.nlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: fp1,
          currentFingerprint: fp2,
        ),
        isFalse,
      );
    });

    test('an added item flips the fingerprint', () {
      final parent = {'date': '2026-09-19', 'meal_type': 'lunch'};
      final fp1 = SyncService.nlogPayloadFingerprint(parent, [{'name': 'rice'}]);
      final fp2 = SyncService.nlogPayloadFingerprint(
          parent, [{'name': 'rice'}, {'name': 'dal'}]);
      expect(fp1, isNot(fp2));
    });
  });

  group('nlogShouldSkipUpsert', () {
    test('matching fingerprint -> skip', () {
      expect(
        SyncService.nlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: 'abc',
          currentFingerprint: 'abc',
        ),
        isTrue,
      );
    });

    test('null stored fingerprint -> always push', () {
      expect(
        SyncService.nlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: null,
          currentFingerprint: 'abc',
        ),
        isFalse,
      );
    });

    test('kill-switch enabled -> always push', () {
      expect(
        SyncService.nlogShouldSkipUpsert(
          killSwitchDisabled: true,
          storedFingerprint: 'abc',
          currentFingerprint: 'abc',
        ),
        isFalse,
      );
    });
  });

  group('nlogPrunedHashIndex', () {
    test('drops slots no longer present, keeps live ones intact', () {
      final pruned = SyncService.nlogPrunedHashIndex(
        {'2026-09-19 lunch': 'fp1', '2026-09-19 dinner': 'fp2', '2026-09-01 lunch': 'fpOld'},
        {'2026-09-19 lunch', '2026-09-19 dinner'},
      );
      expect(pruned, {'2026-09-19 lunch': 'fp1', '2026-09-19 dinner': 'fp2'});
    });

    test('empty liveSlots -> empty index', () {
      expect(
          SyncService.nlogPrunedHashIndex({'2026-09-19 lunch': 'fp'}, {}), isEmpty);
    });
  });

  group('Hive round-trip', () {
    // Matches Task 2's exlog test setup, which mirrors the sched template
    // (plan-review round 1, finding M5).
    late Directory tempDir;
    late Box box;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nlog_hash_index_test_');
      Hive.init(tempDir.path);
      box = await Hive.openBox('nlog_hash_index_roundtrip_test');
    });
    tearDown(() async {
      await box.close();
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('fingerprint round-trips through dynamic-typed Hive Map and drives the skip decision',
        () async {
      final fp = SyncService.nlogPayloadFingerprint({'a': 1}, []);
      await box.put('sync_nlog_payload_hash_index', {'2026-09-19 lunch': fp});

      final rawIndex = box.get('sync_nlog_payload_hash_index');
      final index = <String, String>{};
      (rawIndex as Map).forEach((k, v) {
        if (k is String && v is String) index[k] = v;
      });

      expect(
        SyncService.nlogShouldSkipUpsert(
          killSwitchDisabled: false,
          storedFingerprint: index['2026-09-19 lunch'],
          currentFingerprint: fp,
        ),
        isTrue,
      );
    });
  });

  group('nlogHashSkipDisabledFor (spec §5.2 composition)', () {
    test('all 4 combinations', () {
      expect(
          SyncService.nlogHashSkipDisabledFor(
              killSwitchDisabled: false, mergeEnabled: true),
          isFalse);
      expect(
          SyncService.nlogHashSkipDisabledFor(
              killSwitchDisabled: true, mergeEnabled: true),
          isTrue);
      expect(
          SyncService.nlogHashSkipDisabledFor(
              killSwitchDisabled: false, mergeEnabled: false),
          isTrue);
      expect(
          SyncService.nlogHashSkipDisabledFor(
              killSwitchDisabled: true, mergeEnabled: false),
          isTrue);
    });
  });

  // OI-204 Step 7 / plan-review round 1 finding I9 — while the merge-disable
  // emergency kill switch is active, the postamble must CLEAR the stored
  // index (not merely skip reading it), or a stale index survives a
  // disable/re-enable cycle and mis-skips re-pushing slots the legacy
  // per-key path may have corrupted in cloud. Source-grep form used here
  // (not behavioral): `_syncNutritionLogs` needs a live `_supabase.client`
  // (a singleton with no constructor injection — `grep -rln
  // "MockSupabase|FakeSupabase|_supabase = Mock|SupabaseService(" test/`
  // returns nothing anywhere in this repo, the same no-DI-seam finding
  // already established for the atomicity sub-property in
  // docs/sot_registry.yaml's sync_exercise_log_payload_hash_index entry) and
  // `ownerChangedSince`/HiveUserSession auth state neither of which this
  // pure-function test file's "Hive round-trip" group's real-box setup
  // provides — it opens a bare temp Hive box, never invokes
  // _syncNutritionLogs itself. A live-Supabase behavioral drive of the
  // postamble is therefore not feasible here; falls back to the source-grep
  // form, same as the atomicity sub-property's own presence_only reasoning.
  group('I9 clear-on-revert (plan-review round 1, finding I9)', () {
    test(
        'while the merge-disable kill switch is active, the postamble '
        'CLEARS the stored index rather than merely skipping the read of '
        'it -- a stale index surviving the revert would fingerprint-match '
        'unchanged local content and mis-skip re-pushing the slots the '
        'legacy per-key path may have corrupted', () {
      final src = File('lib/core/services/sync/sync_nutrition.dart')
          .readAsStringSync();
      // `if (!nlogHashSkipDisabled) {` appears TWICE — once in the preamble
      // (index-hydration, no else) and once in the postamble (persist-or-
      // clear, WITH the else this test targets). lastIndexOf anchors on the
      // postamble occurrence, which is structurally last in the file.
      final ifStart = src.lastIndexOf('if (!nlogHashSkipDisabled) {');
      expect(ifStart, isNot(-1),
          reason: 'postamble nlogHashSkipDisabled branch must exist');
      // Generous window (comments included) from the if-branch through the
      // else-branch body — same windowed-anchor technique
      // sync_natural_key_guard_test.dart already uses in this repo.
      final window =
          src.substring(ifStart, (ifStart + 2000).clamp(0, src.length));
      expect(window, contains('} else {'),
          reason: 'the disabled-path branch must be an else, not a silent '
              'no-op');
      final elseBodyStart = window.indexOf('} else {') + '} else {'.length;
      final elseBody = window.substring(elseBodyStart);
      expect(
        elseBody,
        contains('_hive.nutritionBox.delete(SyncService._nlogHashIndexKey)'),
        reason: 'the else branch must DELETE the index key, not merely '
            'leave it unread (spec, plan-review round 1 finding I9)',
      );
    });
  });

  group('resetJourney clears the index (source contract)', () {
    test('sync_nlog_payload_hash_index is cleared by resetJourney, mirroring '
        'the sched/exlog keys it sits beside', () {
      final src =
          File('lib/features/dev/simulation_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> resetJourney(');
      expect(start, isNot(-1), reason: 'resetJourney must exist at this name');
      final end = src.indexOf('\n  }\n', start);
      final body = src.substring(start, end == -1 ? src.length : end);
      expect(body, contains("'sync_nlog_payload_hash_index'"),
          reason: 'a stale fingerprint entry survives a sim reset and '
              'mis-skips the re-drive push — see the sync_sched_payload_hash_index '
              '/ sync_exlog_payload_hash_index precedent this mirrors');
    });
  });

  // OI-204 Step 7b — spec §8's atomicity behavioral-test requirement (simulate
  // a per-slot network failure, assert no fingerprint is stored) needs a
  // test-time fault-injection seam that does not exist in this codebase
  // today (same no-DI-seam finding as Task 2's exlog sibling; see that
  // group's header comment above for the full grep evidence). This test
  // covers the "exactly one store site" half of the atomicity property
  // mechanically; the "only reached when the flag is true" half is covered
  // statically by scripts/check_sync_hash_skip_atomicity.dart
  // (mutation-proven, docs/audit/gate_test_ledger.yaml). See
  // docs/sot_registry.yaml's sync_nutrition_log_payload_hash_index entry,
  // `presence_only: true` on the atomicity sub-property.
  group('exact store call-site count (spec §8 item 4)', () {
    test('the guarded nlogHashIndex[slotId] = nlogFp store appears exactly '
        'once in sync_nutrition.dart', () {
      final src =
          File('lib/core/services/sync/sync_nutrition.dart').readAsStringSync();
      final matches =
          RegExp(r'nlogHashIndex\[slotId\]\s*=\s*nlogFp\s*;').allMatches(src);
      expect(matches.length, 1);
    });
  });
}
