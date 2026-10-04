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

  test('a confirmed weight push is recorded under sync_weight_payload_hash_index '
      'in healthBox, and the SAME function reads it back to skip', () async {
    await HiveService.instance.healthBox.put('weight_2026-09-22',
        {'type': 'weight_log', 'date': '2026-09-22', 'weight_kg': 74.0, 'updated_at_ms': 1758000000000});
    await SyncService.instance.pushWeightLogsForSyncDomain();
    expect(SyncSkipIndex.readIndex(HiveService.instance.healthBox, SyncSkipDomain.weight.indexKey),
        contains('2026-09-22'));
    h.server.clear();
    await SyncService.instance.pushWeightLogsForSyncDomain();
    expect(h.server.writesTo('weight_logs'), isEmpty);
  });
}
