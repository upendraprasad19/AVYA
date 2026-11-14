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

  test('a confirmed per-day sleep push is recorded under '
      'sync_sleep_payload_hash_index (plain date row key, D18) in healthBox, '
      'and the SAME function reads it back to skip', () async {
    await HiveService.instance.healthBox.put('sleep_log_2026-09-22',
        {'date': '2026-09-22', 'duration_hrs': 7.5, 'updated_at_ms': 1758000000000});
    await SyncService.instance.pushSleepLogsForSyncDomain();
    expect(SyncSkipIndex.readIndex(HiveService.instance.healthBox, SyncSkipDomain.sleep.indexKey),
        contains('2026-09-22'));
    h.server.clear();
    await SyncService.instance.pushSleepLogsForSyncDomain();
    expect(h.server.writesTo('sleep_logs'), isEmpty);
  });
}
