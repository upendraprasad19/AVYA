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

  test('water_logs: push/skip/edit/retry/kill-switch contract', () async {
    var ml = 750;
    await HiveService.instance.healthBox.put('water_ml_2026-09-20', ml);
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.water,
      table: 'water_logs',
      seed: () async {},
      runPass: () => SyncService.instance.pushWaterLogsForSyncDomain(),
      editOne: (gen) async {
        ml = 750 + gen * 100;
        await HiveService.instance.healthBox.put('water_ml_2026-09-20', ml);
      },
      touchSentAtOnly: () async {
        // total_ml/glasses unchanged; only wall-clock time advances, so the
        // next push's `updated_at` differs. Global Constraint: water's
        // `updated_at` is a sent-at stamp, excluded from the fingerprint.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
    );
  });

  test('the pushed row carries total_ml, glasses and updated_at (unchanged payload shape)', () async {
    // The shared SyncStubServer (sync_domain_skip_harness.dart) is
    // constructed ONCE for this whole file, not per test -- tearDown never
    // clears `requests`, so the previous test's kill-switch-phase tail
    // requests are still present here (established pattern, see
    // sync_exercise_log_payload_hash_index_writer_to_reader_test.dart).
    h.server.clear();
    await HiveService.instance.healthBox.put('water_ml_2026-09-21', 1000);
    await SyncService.instance.pushWaterLogsForSyncDomain();
    final row = h.server.writesTo('water_logs').single.rows.single;
    expect(row['total_ml'], 1000);
    expect(row['glasses'], 4);
    expect(row['updated_at'], isA<String>());
  });
}
