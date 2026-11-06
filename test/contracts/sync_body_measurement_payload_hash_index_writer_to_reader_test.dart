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

  test('a confirmed measurement push is recorded under '
      'sync_measurement_payload_hash_index in healthBox, and the SAME function '
      'reads it back to skip', () async {
    await HiveService.instance.healthBox
        .put('measurement_2026-09-22', {'date': '2026-09-22', 'waist': 81.0, 'updated_at_ms': 1758000000000});
    await SyncService.instance.pushMeasurementsForSyncDomain();
    expect(SyncSkipIndex.readIndex(HiveService.instance.healthBox, SyncSkipDomain.measurement.indexKey),
        contains('2026-09-22'));
    h.server.clear();
    await SyncService.instance.pushMeasurementsForSyncDomain();
    expect(h.server.writesTo('body_measurements'), isEmpty);
  });
}
