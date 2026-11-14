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

  test('body_measurements: push/skip/edit/retry/kill-switch contract', () async {
    var waist = 80.0;
    await HiveService.instance.healthBox.put('measurement_2026-09-20', {
      'date': '2026-09-20',
      'waist': waist,
      'updated_at_ms': 1758000000000,
      'created_at': '2026-09-20T06:00:00.000Z',
    });
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.measurement,
      table: 'body_measurements',
      seed: () async {},
      runPass: () => SyncService.instance.pushMeasurementsForSyncDomain(),
      editOne: (gen) async {
        waist = 80.0 - gen;
        await HiveService.instance.healthBox.put('measurement_2026-09-20', {
          'date': '2026-09-20',
          'waist': waist,
          'updated_at_ms': 1758000000000,
          'created_at': '2026-09-20T06:00:00.000Z',
        });
      },
    );
  });

  test('a measurement row missing created_at derives it from updated_at_ms', () async {
    // The shared SyncStubServer (sync_domain_skip_harness.dart) is
    // constructed ONCE for this whole file, not per test -- tearDown never
    // clears `requests`, so the previous test's kill-switch-phase tail
    // requests are still present here (established pattern, see
    // saved_meal_skip_test.dart).
    h.server.clear();
    await HiveService.instance.healthBox
        .put('measurement_2026-09-21', {'date': '2026-09-21', 'chest': 100.0, 'updated_at_ms': 1758100000000});
    await SyncService.instance.pushMeasurementsForSyncDomain();
    final row = h.server.writesTo('body_measurements').single.rows.single;
    expect(row['created_at'], DateTime.fromMillisecondsSinceEpoch(1758100000000, isUtc: true).toIso8601String());
  });
}
