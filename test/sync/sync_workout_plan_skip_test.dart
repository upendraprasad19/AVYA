// Day-swapper + sync-load Task 20 — the pushIfChanged wiring itself
// (the Gate 9 file above pins the CONTRACT; this pins the specific
// fingerprint-input shape: `synced_at` excluded, spec §5.9's fingerprint
// table).
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

  test('synced_at alone changing between two pushes of an OTHERWISE identical '
      'bundle sends nothing (it is a sent-at stamp, excluded from the '
      'fingerprint per spec §5.9)', () async {
    await HiveService.instance.workoutBox.put('current_plan', {'phase': 1});
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    expect(h.server.writesTo('user_progress'), hasLength(1));

    h.server.clear();
    // Nothing in Hive changed between these two calls; `synced_at` is
    // recomputed fresh via DateTime.now() inside _syncWorkoutPlan on EVERY
    // call, so if it leaked into the fingerprint this second, byte-identical
    // pass would still push.
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    expect(h.server.writesTo('user_progress'), isEmpty,
        reason: 'synced_at must be excluded from the fingerprint input');
  });

  test('the plan domain kill switch (disable_plan_hash_skip) forces an '
      'unconditional push even with a matching fingerprint', () async {
    await HiveService.instance.workoutBox.put('current_plan', {'phase': 1});
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    h.server.clear();
    await HiveService.instance.configBox.put('disable_plan_hash_skip', true);
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    expect(h.server.writesTo('user_progress'), hasLength(1));
    expect(
        SyncSkipIndex.readIndex(
                HiveService.instance.workoutBox, SyncSkipDomain.plan.indexKey)
            .containsKey(kPlanBundleRowKey),
        isFalse);
    await HiveService.instance.configBox.delete('disable_plan_hash_skip');
  });
}
