import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  group('nlogPayloadFingerprint (kept byte-identical -- plan D4, no re-push burst)', () {
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
          parent, [{'name': 'rice', 'quantity_g': 200}]);
      expect(fp1, isNot(fp2));
    });

    test('an added item flips the fingerprint', () {
      final parent = {'date': '2026-09-19', 'meal_type': 'lunch'};
      final fp1 = SyncService.nlogPayloadFingerprint(parent, [{'name': 'rice'}]);
      final fp2 = SyncService.nlogPayloadFingerprint(
          parent, [{'name': 'rice'}, {'name': 'dal'}]);
      expect(fp1, isNot(fp2));
    });
  });

  group('nlogHashSkipDisabledFor (kept -- composes the kill switch with slot-merge)', () {
    test('all 4 combinations', () {
      expect(SyncService.nlogHashSkipDisabledFor(killSwitchDisabled: false, mergeEnabled: true),
          isFalse);
      expect(SyncService.nlogHashSkipDisabledFor(killSwitchDisabled: true, mergeEnabled: true),
          isTrue);
      expect(SyncService.nlogHashSkipDisabledFor(killSwitchDisabled: false, mergeEnabled: false),
          isTrue);
      expect(SyncService.nlogHashSkipDisabledFor(killSwitchDisabled: true, mergeEnabled: false),
          isTrue);
    });
  });

  group('nlog behavioral skip contract (day-swapper + sync-load Task 13)', () {
    final h = SyncHarness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    Map<String, dynamic> row(int calories) => {
          'date': '2026-09-19',
          'meal_type': 'lunch',
          'total_calories': calories,
          'total_fiber': 2,
          'created_at': '2026-09-19T08:00:00.000Z',
          'items': [
            {'name': 'rice', 'quantity_g': 150, 'calories': calories},
          ],
        };

    // Two items so an "abandon after the FIRST failure" vs. "try every item"
    // distinction is actually observable: the stub server fails every write
    // to 'nutrition_log_items' regardless of which item or the tail-vacuum
    // sent it (SyncStubServer has no per-call/per-method fault injection --
    // see test/helpers/sync_stub_server.dart's own "no query filtering"
    // note), so with a single item the vacuum's OWN independent catch
    // already returns false and masks whether the item catch's `return
    // false;` fired at all (the class this repo calls a zero-red mutation --
    // CLAUDE.md §4.4 rule 21). With two items, "abandon immediately" sends
    // exactly ONE write attempt (item 0) while "try every item" would send
    // two (item 0 AND item 1) before ever reaching the vacuum.
    Map<String, dynamic> twoItemRow(int calories) => {
          'date': '2026-09-19',
          'meal_type': 'lunch',
          'total_calories': calories,
          'total_fiber': 2,
          'created_at': '2026-09-19T08:00:00.000Z',
          'items': [
            {'name': 'rice', 'quantity_g': 150, 'calories': calories},
            {'name': 'dal', 'quantity_g': 100, 'calories': calories},
          ],
        };

    test('the full skip contract', () async {
      // The push closure resolves the cloud-generated parent id via a
      // follow-up SELECT (nutrition_logs.id is omitted from the upsert
      // payload -- diagnose c9f2a7) before it will write any items and
      // confirm the slot. The stub server answers every GET from
      // `getResponders` (default `[]`, i.e. "no such row"), so without this
      // the id lookup always comes back empty and the push is permanently
      // `unconfirmed` -- nothing is ever recorded, regardless of the skip
      // logic under test here.
      h.server.getResponders['nutrition_logs'] = (_) => [
            {'id': 'cloud-parent-1'}
          ];
      await expectSkipContract(
        h: h,
        domain: SyncSkipDomain.nlog,
        table: 'nutrition_logs',
        seed: () => HiveService.instance.nutritionBox.put('nlog_1758259200000', row(500)),
        runPass: () => SyncService.instance.pushNutritionLogsForSyncDomain(),
        editOne: (generation) => HiveService.instance.nutritionBox
            .put('nlog_1758259200000', row(500 + generation)),
      );
    });

    test('an item-upsert failure abandons the slot immediately: nothing recorded, '
        'no partial confirm, retried whole next pass', () async {
      // The shared SyncHarness's SyncStubServer instance is constructed ONCE
      // for this whole `group` (test/sync/sync_domain_skip_harness.dart);
      // `tearDown` never clears `requests`, so the previous test's un-cleared
      // tail requests are still present here (test/sync/sync_stub_server_test.dart's
      // own multi-test group relies on the same fact). Clear first so
      // `hasLength` below counts only this test's own writes.
      h.server.clear();
      await HiveService.instance.nutritionBox.put('nlog_1758259200000', twoItemRow(500));
      h.server.getResponders['nutrition_logs'] = (_) => [
            {'id': 'cloud-parent-1'}
          ];
      h.server.failWritesTo.add('nutrition_log_items');
      await SyncService.instance.pushNutritionLogsForSyncDomain();
      expect(h.server.writesTo('nutrition_logs'), hasLength(1),
          reason: 'the parent upsert lands even though the item write will fail');
      expect(h.server.writesTo('nutrition_log_items'), hasLength(1),
          reason: 'abandon-on-first-failure: item 1 (and the vacuum) must never be '
              'attempted once item 0 fails -- with two items, "try every item" would '
              'send a second write here');
      expect(
          SyncSkipIndex.readIndex(
              skipBoxOf(SyncSkipDomain.nlog), SyncSkipDomain.nlog.indexKey),
          isEmpty);
      h.server
        ..clear()
        ..failWritesTo.remove('nutrition_log_items');
      await SyncService.instance.pushNutritionLogsForSyncDomain();
      expect(h.server.writesTo('nutrition_logs'), hasLength(1),
          reason: 'the parent re-upserts too -- the whole slot re-pushes, not just the item');
      // 3, not 2: a successful slot push issues BOTH per-item upserts (item 0
      // AND item 1) PLUS the tail-vacuum DELETE -- all three are writes to
      // this table (`isWrite` counts any non-GET method).
      expect(h.server.writesTo('nutrition_log_items'), hasLength(3));
    });
  });

  group('resetJourney clears the index (source contract)', () {
    test('SyncSkipDomain.nlog.indexKey is referenced by resetJourney (repointed, see '
        'the exlog sibling test for the full rationale)', () {
      final src = File('lib/features/dev/simulation_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> resetJourney(');
      expect(start, isNot(-1), reason: 'resetJourney must exist at this name');
      final end = src.indexOf('\n  }\n', start);
      final body = src.substring(start, end == -1 ? src.length : end);
      expect(body, contains('SyncSkipDomain.nlog.indexKey'),
          reason: 'a stale fingerprint entry survives a sim reset and mis-skips the '
              're-drive push');
    });
  });
}
