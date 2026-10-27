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

  test('a confirmed steps push is recorded under sync_steps_payload_hash_index '
      'in healthBox, and the SAME function reads it back to skip', () async {
    await HiveService.instance.healthBox
        .put('step_2026-09-22', {'type': 'step_log', 'date': '2026-09-22', 'steps': 4000, 'source': 'manual'});
    await SyncService.instance.pushStepsLogsForSyncDomain();
    expect(SyncSkipIndex.readIndex(HiveService.instance.healthBox, SyncSkipDomain.steps.indexKey),
        contains('2026-09-22'));
    h.server.clear();
    await SyncService.instance.pushStepsLogsForSyncDomain();
    expect(h.server.writesTo('daily_steps'), isEmpty);
  });
}
