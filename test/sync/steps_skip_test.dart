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

  test('daily_steps: push/skip/edit/retry/kill-switch contract', () async {
    var steps = 5000;
    await HiveService.instance.healthBox
        .put('step_2026-09-20', {'type': 'step_log', 'date': '2026-09-20', 'steps': steps, 'source': 'health_connect'});
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.steps,
      table: 'daily_steps',
      seed: () async {},
      runPass: () => SyncService.instance.pushStepsLogsForSyncDomain(),
      editOne: (gen) async {
        steps = 5000 + gen * 500;
        await HiveService.instance.healthBox.put('step_2026-09-20',
            {'type': 'step_log', 'date': '2026-09-20', 'steps': steps, 'source': 'health_connect'});
      },
      touchSentAtOnly: () async {
        // steps/source unchanged; only `synced_at` (excluded from the
        // fingerprint) differs between passes.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
    );
  });
}
