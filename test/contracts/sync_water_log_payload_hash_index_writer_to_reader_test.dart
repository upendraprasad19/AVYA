// SoT contract: sync_water_log_payload_hash_index (docs/sot_registry.yaml,
// added Task 29). Writer AND reader are the SAME method
// (SyncServiceNutrition._syncWaterLogs) — the skip decision reads its own
// index, so writer/reader drift here is structurally impossible; this test
// pins the BEHAVIOUR (write -> push -> confirmed-in-index -> unchanged pass
// skips), not just the field name.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('a confirmed water push is recorded under sync_water_payload_hash_index '
      'in healthBox, and the SAME function reads it back to skip', () async {
    await HiveService.instance.healthBox.put('water_ml_2026-09-22', 600);
    await SyncService.instance.pushWaterLogsForSyncDomain();
    expect(
      SyncSkipIndex.readIndex(
          HiveService.instance.healthBox, SyncSkipDomain.water.indexKey),
      contains('2026-09-22'),
    );
    h.server.clear();
    await SyncService.instance.pushWaterLogsForSyncDomain();
    expect(h.server.writesTo('water_logs'), isEmpty,
        reason: 'the writer read its own index and skipped the unchanged row');
  });
}
