// Day-swapper + sync-load Task 20, spec §5.11 "Launch reads" + OI-237 —
// restoreLightweightAlways used to run TWO separate `user_progress` selects
// on every returning-user launch (_restoreUserProgress's bare `.select()`
// AND _restoreWorkoutPlan's `.select('plan_json')`). It now runs ONE and
// hands the same row to both, via their existing `preFetched` injection
// params (the C3 single-call restore's own pattern,
// `_attemptSingleCallRestore` in sync_service.dart).
//
// Also pins: (a) `plan_json` no longer lands in userBox['progress'] (spec
// §5.11 — it used to, via mergeCloudProgress's cloud-non-null-wins loop over
// every key the SELECT returned); (b) the sync_epoch resync lever (spec
// §5.10 rule 3); (c) the disable_restore_single_plan_fetch kill switch
// reverting to today's verbatim two-fetch behaviour (CLAUDE.md §4.6).
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Map<String, dynamic> progressRow({int? syncEpoch}) => {
        'user_id': 'ignored-stripped-by-restore',
        'current_phase': 2,
        'total_workouts_done': 10,
        'current_streak_weeks': 1,
        'plan_json': {
          'plan': {'phase': 2},
          'plan_start_date': '2026-08-01',
          'plan_end_date': '2026-08-28',
          'schedules': <String, dynamic>{},
        },
        if (syncEpoch != null) 'sync_epoch': syncEpoch,
      };

  test('ONE user_progress select feeds both _restoreUserProgress and '
      '_restoreWorkoutPlan', () async {
    // h.server.requests accumulates across every test() in this file (the
    // harness's SyncStubServer instance is shared, per SyncHarness — only
    // clear() resets it, start()/stop() do not); this test asserts a
    // request COUNT, so it must not depend on running first in file order.
    h.server.clear();
    h.server.getResponders['user_progress'] = (_) => [progressRow()];
    h.server.getResponders['user_profile'] = (_) => [];
    h.server.getResponders['user_custom_exercises'] = (_) => [];
    h.server.getResponders['user_custom_foods'] = (_) => [];
    h.server.getResponders['workout_templates'] = (_) => [];
    h.server.getResponders['user_preferences'] = (_) => [];

    await SyncService.instance.restoreLightweightAlways(kTestUserId);

    final selects = h.server.requests.where((r) =>
        r.method == 'GET' && r.path == '/rest/v1/user_progress');
    expect(selects, hasLength(1),
        reason: 'today this is 2 (one per restore step) — OI-237');
    expect(HiveService.instance.userBox.get('progress'),
        containsPair('current_phase', 2));
  });

  test(
      'plan_json does NOT land in userBox["progress"], but its content still '
      'lands via _restoreWorkoutPlan (spec §5.11)', () async {
    h.server.getResponders['user_progress'] = (_) => [progressRow()];
    h.server.getResponders['user_profile'] = (_) => [];
    h.server.getResponders['user_custom_exercises'] = (_) => [];
    h.server.getResponders['user_custom_foods'] = (_) => [];
    h.server.getResponders['workout_templates'] = (_) => [];
    h.server.getResponders['user_preferences'] = (_) => [];

    await SyncService.instance.restoreLightweightAlways(kTestUserId);

    final progress = HiveService.instance.userBox.get('progress') as Map;
    expect(progress.containsKey('plan_json'), isFalse);
    // The plan content itself still lands via _restoreWorkoutPlan (fed by
    // the SAME preFetched row), just not duplicated into the progress map.
    expect(HiveService.instance.workoutBox.get('current_plan'),
        containsPair('phase', 2));
    // MigratedKey.read<String> (lib/core/services/migrated_key.dart:32-56)
    // tries userBox first when a session is open, else falls back to
    // configBox — _restoreWorkoutPlan's own MigratedKey.write (via
    // PlanWindowReanchor.resolve) uses the identical fallback, so whichever
    // box the write landed in is exactly where this read finds it.
    expect(MigratedKey.read<String>('plan_start_date'), '2026-08-01');
  });

  test('the restore kill switch does NOT switch off the sync_epoch lever '
      '(round-1 review D2 F1)', () async {
    await HiveService.instance.configBox
        .put(SyncService.kDisableRestoreSinglePlanFetchKey, true);
    await HiveService.instance.workoutBox.put('sync_epoch_seen', 1);
    await HiveService.instance.workoutBox
        .put(SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-stale'});
    h.server.getResponders['user_progress'] = (_) => [progressRow(syncEpoch: 2)];
    h.server.getResponders['user_profile'] = (_) => [];
    h.server.getResponders['user_custom_exercises'] = (_) => [];
    h.server.getResponders['user_custom_foods'] = (_) => [];
    h.server.getResponders['workout_templates'] = (_) => [];
    h.server.getResponders['user_preferences'] = (_) => [];

    await SyncService.instance.restoreLightweightAlways(kTestUserId);

    expect(HiveService.instance.workoutBox.get('sync_epoch_seen'), 2);
    expect(
        SyncSkipIndex.readIndex(
            HiveService.instance.workoutBox, SyncSkipDomain.sched.indexKey),
        isEmpty);
  });

  test(
      'Hermes L15 2026-09-28: sync_epoch_seen is PER USER — account A\'s '
      'high-water mark on a shared device never masks account B\'s resync',
      () async {
    void stubEpoch(int epoch) {
      h.server.getResponders['user_progress'] =
          (_) => [progressRow(syncEpoch: epoch)];
      h.server.getResponders['user_profile'] = (_) => [];
      h.server.getResponders['user_custom_exercises'] = (_) => [];
      h.server.getResponders['user_custom_foods'] = (_) => [];
      h.server.getResponders['workout_templates'] = (_) => [];
      h.server.getResponders['user_preferences'] = (_) => [];
    }

    // Account A has seen epoch 3.
    stubEpoch(3);
    await SyncService.instance.restoreLightweightAlways(kTestUserId);

    // Account B signs in on the same device: epoch 1 is B's first sight.
    const userB = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';
    HiveUserSession.debugCurrentUidResolverForTests = () => userB;
    await HiveUserSession.openForUser(userB);
    stubEpoch(1);
    await SyncService.instance.restoreLightweightAlways(userB);
    await HiveService.instance.workoutBox
        .put(SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-stale'});

    // The operator bumps B to 2: B's indexes must clear (2 > B's own 1),
    // even though 2 <= A's 3.
    stubEpoch(2);
    await SyncService.instance.restoreLightweightAlways(userB);
    expect(
        HiveService.instance.workoutBox
            .containsKey(SyncSkipDomain.sched.indexKey),
        isFalse,
        reason: "B's resync was masked by A's sync_epoch_seen");
  });

  group('sync_epoch resync lever', () {
    test('first sight (no sync_epoch_seen key yet) just stores the baseline, '
        'no index clear', () async {
      await HiveService.instance.workoutBox
          .put(SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-stale'});
      // Task 20 Step 5 mutation 6's own caution: a `syncEpoch: 0` fixture
      // cannot distinguish "the first-sight guard ran" from "0 does not
      // exceed a first-computed seen=0 anyway" -- a mutation that deletes
      // the guard would come back green here for the WRONG reason. Widened
      // to `syncEpoch: 1` (still the device's first-ever sight, no
      // `sync_epoch_seen` key yet) so the guard's absence is actually
      // exercised: without it, `seen` would read as 0 and 1 > 0 would wipe
      // the sched index on this device's very first launch under the
      // feature.
      h.server.getResponders['user_progress'] = (_) => [progressRow(syncEpoch: 1)];
      h.server.getResponders['user_profile'] = (_) => [];
      h.server.getResponders['user_custom_exercises'] = (_) => [];
      h.server.getResponders['user_custom_foods'] = (_) => [];
      h.server.getResponders['workout_templates'] = (_) => [];
      h.server.getResponders['user_preferences'] = (_) => [];

      await SyncService.instance.restoreLightweightAlways(kTestUserId);

      expect(HiveService.instance.workoutBox.get('sync_epoch_seen'), 1);
      expect(
          SyncSkipIndex.readIndex(
              HiveService.instance.workoutBox, SyncSkipDomain.sched.indexKey),
          {'2026-08-01': 'fp-stale'},
          reason: 'first sight must not wipe a fresh device\'s indexes');
    });

    test('a higher cloud sync_epoch clears every domain index then stores '
        'the new epoch', () async {
      await HiveService.instance.workoutBox.put('sync_epoch_seen', 1);
      await HiveService.instance.workoutBox
          .put(SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-stale'});
      await HiveService.instance.healthBox
          .put(SyncSkipDomain.water.indexKey, {'2026-08-01': 'fp-stale'});
      h.server.getResponders['user_progress'] = (_) => [progressRow(syncEpoch: 2)];
      h.server.getResponders['user_profile'] = (_) => [];
      h.server.getResponders['user_custom_exercises'] = (_) => [];
      h.server.getResponders['user_custom_foods'] = (_) => [];
      h.server.getResponders['workout_templates'] = (_) => [];
      h.server.getResponders['user_preferences'] = (_) => [];

      await SyncService.instance.restoreLightweightAlways(kTestUserId);

      expect(HiveService.instance.workoutBox.get('sync_epoch_seen'), 2);
      expect(
          HiveService.instance.workoutBox
              .containsKey(SyncSkipDomain.sched.indexKey),
          isFalse);
      expect(
          HiveService.instance.healthBox
              .containsKey(SyncSkipDomain.water.indexKey),
          isFalse);
    });

    test('a clearAll failure in one domain does NOT advance sync_epoch_seen, '
        'and the SAME row retries the clear on the next call (diagnose '
        'a9d3f6)', () async {
      await HiveService.instance.workoutBox.put('sync_epoch_seen', 1);
      await HiveService.instance.workoutBox
          .put(SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-stale'});
      await HiveService.instance.healthBox
          .put(SyncSkipDomain.water.indexKey, {'2026-08-01': 'fp-stale'});
      h.server.getResponders['user_progress'] = (_) => [progressRow(syncEpoch: 2)];
      h.server.getResponders['user_profile'] = (_) => [];
      h.server.getResponders['user_custom_exercises'] = (_) => [];
      h.server.getResponders['user_custom_foods'] = (_) => [];
      h.server.getResponders['workout_templates'] = (_) => [];
      h.server.getResponders['user_preferences'] = (_) => [];

      // Force the `water` domain's clear to throw, simulating one bad Hive
      // box among the four SyncSkipIndex.clearAll walks -- exactly the
      // per-domain failure clearAll already catches internally and never
      // rethrows.
      SyncSkipIndex.debugForceClearFailureForTests =
          (d) => d == SyncSkipDomain.water;
      addTearDown(() => SyncSkipIndex.debugForceClearFailureForTests = null);

      await SyncService.instance.restoreLightweightAlways(kTestUserId);

      // Pre-fix bug: sync_epoch_seen was stored unconditionally right after
      // the clearAll attempt, so a partial failure was silently marked
      // "handled" and never retried. It must stay at 1.
      expect(HiveService.instance.workoutBox.get('sync_epoch_seen'), 1,
          reason: 'a failed domain clear must not mark the resync as done');
      // sched (a different box) DID clear -- one domain's forced failure
      // must not abort the rest of the sweep.
      expect(
          HiveService.instance.workoutBox
              .containsKey(SyncSkipDomain.sched.indexKey),
          isFalse);
      // water is the forced-failure domain -- left dirty, exactly as a real
      // failed delete would leave it.
      expect(
          HiveService.instance.healthBox
              .containsKey(SyncSkipDomain.water.indexKey),
          isTrue,
          reason: 'the forced-failure domain is left untouched, not deleted');

      // Re-seed sched (clearAll above already deleted it) so the SECOND
      // call's before-state is unambiguous, remove the forced failure, and
      // run with the SAME cloud row again: since sync_epoch_seen is still 1
      // and cloudEpoch is still 2, the clear must be attempted again.
      SyncSkipIndex.debugForceClearFailureForTests = null;
      await HiveService.instance.workoutBox.put(
          SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-stale-again'});

      await SyncService.instance.restoreLightweightAlways(kTestUserId);

      expect(HiveService.instance.workoutBox.get('sync_epoch_seen'), 2,
          reason: 'the retry succeeds once nothing is forced to fail');
      expect(
          HiveService.instance.workoutBox
              .containsKey(SyncSkipDomain.sched.indexKey),
          isFalse,
          reason: 'the retried clear ran again and cleared it this time');
      expect(
          HiveService.instance.healthBox
              .containsKey(SyncSkipDomain.water.indexKey),
          isFalse,
          reason: 'water also cleared once the forced failure was removed');
    });

    test('cloud sync_epoch <= seen is a no-op', () async {
      await HiveService.instance.workoutBox.put('sync_epoch_seen', 2);
      await HiveService.instance.workoutBox
          .put(SyncSkipDomain.sched.indexKey, {'2026-08-01': 'fp-live'});
      h.server.getResponders['user_progress'] = (_) => [progressRow(syncEpoch: 2)];
      h.server.getResponders['user_profile'] = (_) => [];
      h.server.getResponders['user_custom_exercises'] = (_) => [];
      h.server.getResponders['user_custom_foods'] = (_) => [];
      h.server.getResponders['workout_templates'] = (_) => [];
      h.server.getResponders['user_preferences'] = (_) => [];

      await SyncService.instance.restoreLightweightAlways(kTestUserId);

      expect(
          SyncSkipIndex.readIndex(
              HiveService.instance.workoutBox, SyncSkipDomain.sched.indexKey),
          {'2026-08-01': 'fp-live'});
    });

    test('a missing sync_epoch column (pre-migration-145 / older DB state) '
        'is treated as 0', () async {
      await HiveService.instance.workoutBox.put('sync_epoch_seen', 0);
      h.server.getResponders['user_progress'] =
          (_) => [progressRow()]; // no sync_epoch key at all
      h.server.getResponders['user_profile'] = (_) => [];
      h.server.getResponders['user_custom_exercises'] = (_) => [];
      h.server.getResponders['user_custom_foods'] = (_) => [];
      h.server.getResponders['workout_templates'] = (_) => [];
      h.server.getResponders['user_preferences'] = (_) => [];

      await SyncService.instance.restoreLightweightAlways(kTestUserId);

      expect(HiveService.instance.workoutBox.get('sync_epoch_seen'), 0,
          reason: 'a missing column must never read as "newer than anything"');
    });
  });

  test('disable_restore_single_plan_fetch reverts to the verbatim two-fetch '
      'path (CLAUDE.md §4.6)', () async {
    // See the "ONE user_progress select" test above — requests accumulate
    // across the whole file, and this test asserts a count.
    h.server.clear();
    await HiveService.instance.configBox
        .put('disable_restore_single_plan_fetch', true);
    h.server.getResponders['user_progress'] = (_) => [progressRow()];
    h.server.getResponders['user_profile'] = (_) => [];
    h.server.getResponders['user_custom_exercises'] = (_) => [];
    h.server.getResponders['user_custom_foods'] = (_) => [];
    h.server.getResponders['workout_templates'] = (_) => [];
    h.server.getResponders['user_preferences'] = (_) => [];

    await SyncService.instance.restoreLightweightAlways(kTestUserId);

    final selects = h.server.requests.where((r) =>
        r.method == 'GET' && r.path == '/rest/v1/user_progress');
    // Round-2 review D2 F1: the kill-switch path also makes one extra read
    // so the epoch lever keeps working (round-1 D2 F1). `_fetchSyncEpochRowForRestore`
    // is a BARE `.select()`, not `.select('sync_epoch')` (schema-column-refs
    // gate: `sync_epoch` ships in migration 149, Task 7/U1, which had not
    // landed when this task executed — see that method's own doc comment),
    // so it is no longer distinguishable from the other two by query shape;
    // this asserts the TOTAL count instead (2 old per-writer + 1 epoch).
    expect(selects, hasLength(3),
        reason: 'the kill switch keeps the OLD per-writer double-fetch '
            '(2) plus exactly one extra epoch read, on this path only');
    await HiveService.instance.configBox
        .delete('disable_restore_single_plan_fetch');
  });
}
