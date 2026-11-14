@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('sleep_logs (per-day path): push/skip/edit/retry/kill-switch contract', () async {
    var hours = 7.0;
    await HiveService.instance.healthBox.put('sleep_log_2026-09-20', {
      'date': '2026-09-20',
      'sleep_hours': hours,
      'duration_hrs': hours,
      'quality': 'good',
      'source': 'manual',
      'updated_at_ms': 1758000000000,
      'created_at': '2026-09-20T07:00:00.000Z',
    });
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.sleep,
      table: 'sleep_logs',
      seed: () async {},
      runPass: () => SyncService.instance.pushSleepLogsForSyncDomain(),
      editOne: (gen) async {
        hours = 7.0 + gen;
        await HiveService.instance.healthBox.put('sleep_log_2026-09-20', {
          'date': '2026-09-20',
          'sleep_hours': hours,
          'duration_hrs': hours,
          'quality': 'good',
          'source': 'manual',
          'updated_at_ms': 1758000000000,
          'created_at': '2026-09-20T07:00:00.000Z',
        });
      },
    );
  });

  test('a per-day sleep row missing created_at derives it from updated_at_ms, '
      'never DateTime.now() (closes-diagnose f4c7a9)', () async {
    // The shared SyncStubServer (sync_domain_skip_harness.dart) is
    // constructed ONCE for this whole file, not per test -- tearDown never
    // clears `requests`, so the previous test's kill-switch-phase tail
    // requests are still present here (established pattern, see
    // saved_meal_skip_test.dart).
    h.server.clear();
    await HiveService.instance.healthBox.put('sleep_log_2026-09-21', {
      'date': '2026-09-21',
      'duration_hrs': 6.5,
      'quality': 'fair',
      'updated_at_ms': 1758100000000, // 2026-09-17T09:06:40.000Z
      // no 'created_at'
    });
    await SyncService.instance.pushSleepLogsForSyncDomain();
    final row = h.server.writesTo('sleep_logs').single.rows.single;
    expect(row['created_at'], DateTime.fromMillisecondsSinceEpoch(1758100000000, isUtc: true).toIso8601String());
  });

  test('a per-day sleep row missing BOTH created_at and updated_at_ms omits the field', () async {
    h.server.clear(); // see the first added test's comment -- shared server.
    await HiveService.instance.healthBox
        .put('sleep_log_2026-09-22', {'date': '2026-09-22', 'duration_hrs': 8.0});
    await SyncService.instance.pushSleepLogsForSyncDomain();
    final row = h.server.writesTo('sleep_logs').single.rows.single;
    expect(row.containsKey('created_at'), isFalse);
  });

  test('D18: the legacy sleep_logs LIST is never pushed by syncSleepNow any '
      'more — only the per-day path pushes, and a stray list entry from an '
      'old device is silently left alone (no crash, no upsert for it)', () async {
    h.server.clear(); // see the first added test's comment -- shared server.
    await HiveService.instance.healthBox.put('sleep_log_2026-09-23', {
      'date': '2026-09-23',
      'duration_hrs': 7.0,
      'updated_at_ms': 1758200000000,
    });
    await HiveService.instance.healthBox.put('sleep_logs', [
      {'date': '2026-09-24', 'duration_hrs': 6.0, 'quality': 'ok'}
    ]);
    await SyncService.instance.syncSleepNow();
    // Exactly ONE write — the per-day row. The list entry for 2026-09-24 is
    // never pushed (its writer has not existed since build +28).
    final writes = h.server.writesTo('sleep_logs');
    expect(writes, hasLength(1));
    expect(writes.single.rows.single['date'], '2026-09-23');
    final idx = SyncSkipIndex.readIndex(
        HiveService.instance.healthBox, SyncSkipDomain.sleep.indexKey);
    expect(idx.keys, ['2026-09-23']);
  });
}
