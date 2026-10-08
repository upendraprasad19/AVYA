// Gate 9 contract: sync_workout_plan_payload_hash_index (day-swapper +
// sync-load Task 20, spec §5.9 plan row / §8 registry list).
//
// _syncWorkoutPlan's stored fingerprint under kPlanBundleRowKey ('bundle') IN
// HiveService.instance.workoutBox IS `plan_bundle_cloud_fingerprint` (spec
// §5.7 L2) — the exact value Task 22's restore-merge skip reads via
// SyncSkipIndex.readIndex(HiveService.instance.workoutBox,
// SyncSkipDomain.plan.indexKey)[kPlanBundleRowKey].
//
// Behavioural (write -> push -> read index), reusing the Task 5 harness —
// source-grep tests only prove PRESENCE (feedback_source_grep_false_confidence).
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

  Future<void> seedPlan() async {
    await HiveService.instance.workoutBox.put('current_plan', {'phase': 1});
    await HiveService.instance
        .workoutBox
        .put('schedule_2026-09-28', {'type': 'workout', 'status': 'planned'});
  }

  test(
      'an unchanged plan bundle sends nothing on the second pass; an edited '
      'one re-sends exactly once; the kill switch restores the sweep',
      () async {
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.plan,
      table: 'user_progress',
      seed: seedPlan,
      runPass: () => SyncService.instance.pushWorkoutPlanForSyncDomain(),
      editOne: (generation) => HiveService.instance.workoutBox.put(
          'schedule_2026-09-28',
          {'type': 'workout', 'status': 'planned', 'workout_name': 'Push $generation'}),
    );
  });

  test(
      'the stored index row IS the plan_bundle_cloud_fingerprint Task 22 '
      'reads (spec §5.7 L2)', () async {
    await seedPlan();
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    final index = SyncSkipIndex.readIndex(
        HiveService.instance.workoutBox, SyncSkipDomain.plan.indexKey);
    expect(index[kPlanBundleRowKey], isNotNull,
        reason: 'this exact read is what Task 22 performs before merging a '
            'downloaded bundle');
  });
}
