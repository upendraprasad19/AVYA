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

  test('water_logs (urine columns): push/skip/edit/retry/kill-switch contract', () async {
    var idx = 1;
    await HiveService.instance.healthBox
        .put('urine_color_2026-09-20', {'date': '2026-09-20', 'index': idx, 'label': 'Pale straw'});
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.urine,
      table: 'water_logs',
      seed: () async {},
      runPass: () => SyncService.instance.pushUrineColorLogsForSyncDomain(),
      editOne: (gen) async {
        idx = 1 + gen;
        await HiveService.instance.healthBox
            .put('urine_color_2026-09-20', {'date': '2026-09-20', 'index': idx, 'label': 'Dark yellow'});
      },
      touchSentAtOnly: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
    );
  });
}
