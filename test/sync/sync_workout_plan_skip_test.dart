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

import 'package:icanbefitter/core/services/migrated_key.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
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

  test(
      'Hermes L39 2026-09-28: two devices converge — after a STALE device '
      'overwrites the cloud plan, the device holding the newer swap re-pushes '
      'on its next plan pass (restore records the CLOUD fingerprint, so the '
      'local one no longer matches)', () async {
    Map<String, dynamic> day(String date, String name, int arrangedAt) => {
          'date': date,
          'type': 'workout',
          'status': 'planned',
          'workout_name': name,
          'exercises': [
            {'name': '$name lift'}
          ],
          'is_swapped': true,
          'arranged_at_ms': arrangedAt,
        };
    const fri = '2026-09-25', sat = '2026-09-26';
    final wb = HiveService.instance.workoutBox;
    await wb.put('current_plan', {'phase': 1});
    await MigratedKey.write('plan_start_date', '2026-09-21');
    await MigratedKey.write('plan_end_date', '2026-10-18');

    // Device A swapped Fri/Sat at t=2000 and pushed it.
    await wb.put('schedule_$fri', day(fri, 'Legs', 2000));
    await wb.put('schedule_$sat', day(sat, 'Pull', 2000));
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    expect(h.server.writesTo('user_progress'), hasLength(1));

    // Device B, holding an OLDER arrangement of that week (t=1000), pushed
    // its whole bundle afterwards: that is what A now downloads.
    await SyncService.instance.restoreWorkoutPlanForTest(kTestUserId,
        preFetched: [
          {
            'plan_json': {
              'plan': {'phase': 1},
              'plan_start_date': '2026-09-21',
              'plan_end_date': '2026-10-18',
              'schedules': {
                'schedule_$fri': day(fri, 'Pull', 1000),
                'schedule_$sat': day(sat, 'Legs', 1000),
              },
              'synced_at': '2026-09-27T10:00:00Z',
            }
          }
        ]);
    expect((wb.get('schedule_$fri') as Map)['workout_name'], 'Legs',
        reason: "L3: A's newer arrangement of the week survives the merge");

    h.server.clear();
    await SyncService.instance.pushWorkoutPlanForSyncDomain();
    final writes = h.server.writesTo('user_progress');
    expect(writes, hasLength(1),
        reason: 'the cloud holds B\'s stale week, so A must re-push');
    final schedules = (writes.single.rows.single['plan_json']
        as Map)['schedules'] as Map;
    expect((schedules['schedule_$fri'] as Map)['workout_name'], 'Legs');
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
