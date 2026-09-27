// test/sync/restore_plan_merge_skip_test.dart
//
// Day-swapper + sync-load Task 22 -- spec 2026-09-26-day-swapper-design.md
// sec 5.7 L2 ("merge only what is new"). Mechanics only (the I1-I8 invariant
// suite that L2 must not break is in restore_merge_invariants_test.dart):
//   - a downloaded bundle whose fingerprint (excluding synced_at) equals the
//     stored plan_bundle_cloud_fingerprint skips the merge ENTIRELY, even
//     when the bundle's content differs from what is in Hive right now;
//   - a mismatched fingerprint runs the merge normally;
//   - after a successful merge, the downloaded bundle's fingerprint is
//     recorded via SyncSkipIndex.recordConfirmed under kPlanBundleRowKey, in
//     the SAME slot Task 20's push-side confirm writes;
//   - kill switch disable_plan_merge_skip_when_known reverts BOTH L2
//     optimizations (the whole-merge skip AND the per-row write-only-if-
//     differs check) to Task 21's verbatim always-run/always-write behaviour;
//   - an unchanged individual row inside a bundle that DOES get merged is not
//     re-written to Hive (write-only-if-differs), while a changed row in the
//     SAME pass is.
// closes-diagnose: d5a1e7
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  Map<String, dynamic>? row(String date) {
    final raw = HiveService.instance.workoutBox.get('schedule_$date');
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> put(String date, Map<String, dynamic> r) =>
      HiveService.instance.workoutBox.put('schedule_$date', r);

  // Mirrors _syncWorkoutPlan's own fingerprint input EXACTLY (Task 20):
  // {plan, plan_start_date, plan_end_date, schedules} -- synced_at excluded.
  Map<String, dynamic> bundleOf(Map<String, dynamic> schedules,
          {String? syncedAt}) =>
      {
        'plan': {'phase': 1},
        'plan_start_date': '2026-09-01',
        'plan_end_date': '2026-09-28',
        'schedules': schedules,
        if (syncedAt != null) 'synced_at': syncedAt,
      };

  String fingerprintOf(Map<String, dynamic> bundle) {
    final input = Map<String, dynamic>.from(bundle)..remove('synced_at');
    return SyncFingerprint.of(input);
  }

  Future<void> restorePlan(Map<String, dynamic> bundle) =>
      SyncService.instance.restoreWorkoutPlanForTest(
        kTestUserId,
        preFetched: [
          {'plan_json': bundle}
        ],
      );

  Future<void> recordStoredFingerprint(String fp) => SyncSkipIndex.recordConfirmed(
      HiveService.instance.workoutBox, SyncSkipDomain.plan, kPlanBundleRowKey, fp);

  group('whole-bundle skip on a matching fingerprint', () {
    test(
        'a bundle whose fingerprint equals the stored one is never merged, '
        'even though its content clearly differs from what is in Hive '
        '(proves the skip is a real early-return, not a coincidental no-op)',
        () async {
      const fri = '2026-09-25';
      await put(fri, {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]});
      final bundle = bundleOf({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs',
          'exercises': [
            {'name': 'Squat'}
          ],
        },
      });
      await recordStoredFingerprint(fingerprintOf(bundle));

      await restorePlan(bundle);

      expect(row(fri)!['type'], 'rest',
          reason: 'the merge must not have run at all -- if it had, even L1 '
              'would still have kept fri as rest, so this alone would not '
              'prove the SKIP happened; the point is proven by the recorded '
              '"a changed bundle is not skipped" sibling test below');
    });

    test(
        'a bundle whose fingerprint equals the stored one leaves a STAMPED, '
        'week-winning local row untouched -- unlike the sibling test above, '
        'this scenario is NOT protected by L1 or the anti-a7d3f1 guard, so '
        'it is the one that actually distinguishes "the merge was skipped" '
        'from "the merge ran but every guard happened to no-op it" '
        '(mutation-proof: killed mutation 1, see task-22-report.md)',
        () async {
      const fri = '2026-09-25';
      // A stamped, non-rest, already-has-exercises row: if the merge ran,
      // L3's forceSnapshotArrangement would take the snapshot WHOLESALE
      // (bypassing the anti-a7d3f1 "local already has exercises" guard,
      // which only applies on the non-forceSnapshot path) and fri would
      // become 'New'. Only the whole-bundle skip can keep it 'Old'.
      await put(fri, {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Old',
        'arranged_at_ms': 1000,
        'exercises': [
          {'name': 'Old'}
        ],
      });
      final bundle = bundleOf({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'New',
          'arranged_at_ms': 5000, // newer -- would force a wholesale take
          'exercises': [
            {'name': 'New'}
          ],
        },
      });
      await recordStoredFingerprint(fingerprintOf(bundle));

      await restorePlan(bundle);

      expect(row(fri)!['workout_name'], 'Old',
          reason: 'the skip must have prevented the merge from running at '
              'all -- if it had run, L3 would have forced the wholesale '
              'snapshot take (arranged_at_ms 5000 > 1000) regardless of the '
              'anti-a7d3f1 guard, changing workout_name to New');
    });

    test(
        'a bundle whose fingerprint differs from the stored one runs the '
        'merge normally', () async {
      const fri = '2026-09-25';
      await put(fri, {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]});
      final staleBundle = bundleOf({
        'schedule_$fri': {'type': 'workout', 'status': 'planned', 'exercises': []},
      });
      await recordStoredFingerprint(fingerprintOf(staleBundle));

      final newBundle = bundleOf({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs',
          'arranged_at_ms': 5000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
      });
      await restorePlan(newBundle);

      // fri is a REST row locally, so L1 protects it regardless -- the
      // point of this test is only that the merge RAN (verified by the
      // recorded-fingerprint assertion below), not what it decided.
      expect(
          SyncSkipIndex.readIndex(
                  HiveService.instance.workoutBox, SyncSkipDomain.plan.indexKey)[
              kPlanBundleRowKey],
          fingerprintOf(newBundle),
          reason: 'a mismatched fingerprint must run the merge, which then '
              'records the NEW bundle\'s fingerprint');
    });

    test(
        'after a successful merge, the downloaded bundle\'s fingerprint is '
        'recorded under kPlanBundleRowKey -- the exact slot Task 20\'s '
        'confirmed push writes', () async {
      final bundle = bundleOf({
        'schedule_2026-09-25': {'type': 'rest', 'status': 'rest', 'exercises': []},
      });
      await restorePlan(bundle);
      final index = SyncSkipIndex.readIndex(
          HiveService.instance.workoutBox, SyncSkipDomain.plan.indexKey);
      expect(index[kPlanBundleRowKey], fingerprintOf(bundle));
    });

    test(
        'kill switch disable_plan_merge_skip_when_known=true forces the '
        'merge to run even when the fingerprint matches (CLAUDE.md sec 4.6)',
        () async {
      const fri = '2026-09-25';
      await put(fri, {
        'type': 'workout',
        'status': 'planned',
        'exercises': [
          {'name': 'Old'}
        ],
      });
      final bundle = bundleOf({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'exercises': [
            {'name': 'New'}
          ],
        },
      });
      await recordStoredFingerprint(fingerprintOf(bundle));
      await HiveService.instance.configBox
          .put('disable_plan_merge_skip_when_known', true);

      await restorePlan(bundle);

      // Local's exercises are non-empty, so the pre-existing anti-a7d3f1
      // guard (mergeScheduleEntry's "local already has exercises" branch)
      // keeps local content regardless -- the guard applies EVERY pass with
      // the kill switch on, which is exactly how a caller not currently
      // debugging L2 tells the merge ran: the recorded-fingerprint
      // assertion below is what actually distinguishes "ran" from "skipped".
      expect(
          SyncSkipIndex.readIndex(
                  HiveService.instance.workoutBox, SyncSkipDomain.plan.indexKey)[
              kPlanBundleRowKey],
          fingerprintOf(bundle),
          reason: 'the merge ran (and therefore recorded), proving the kill '
              'switch defeated the fingerprint-match skip');
      await HiveService.instance.configBox
          .delete('disable_plan_merge_skip_when_known');
    });
  });

  group('per-row write-only-if-differs', () {
    test(
        'an unchanged row inside a merged bundle is not re-written to Hive; '
        'a changed row in the SAME pass is', () async {
      const fri = '2026-09-25'; // unchanged
      const sat = '2026-09-26'; // changed
      await put(fri, {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]});
      // sat is stamped so L3 (snapshotArrangementWinsKeys) forces the
      // wholesale snapshot for it regardless of the pre-existing
      // "local already has exercises" anti-a7d3f1 guard in
      // mergeScheduleEntry (plan_integrity_reconciler.dart:92) -- that guard
      // would otherwise keep sat's LOCAL content authoritative even though
      // the snapshot's content differs, making the row read as "unchanged"
      // for entirely unrelated (L3) reasons and defeating this test's own
      // premise. The snapshot's stamp (5000) is strictly newer than local's
      // (1000) in the SAME Mon-Sun IST week as fri, so only sat -- the one
      // STAMPED key on the snapshot side -- is forced; fri is never stamped
      // on either side, so it is never added to the winning set and its own
      // "unchanged" assertion below is unaffected.
      await put(sat, {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Old',
        'arranged_at_ms': 1000,
        'exercises': [
          {'name': 'Old'}
        ],
      });
      final friEvents = <void>[];
      final satEvents = <void>[];
      final subFri = HiveService.instance.workoutBox
          .watch(key: 'schedule_$fri')
          .listen((_) => friEvents.add(null));
      final subSat = HiveService.instance.workoutBox
          .watch(key: 'schedule_$sat')
          .listen((_) => satEvents.add(null));

      // A bundle that does NOT match the stored fingerprint (none stored),
      // so the merge runs; fri's snapshot entry is byte-identical to fri's
      // local row (both normalize to the same rest row); sat's snapshot
      // entry genuinely differs AND out-stamps local (5000 > 1000), forcing
      // L3's wholesale take.
      await restorePlan(bundleOf({
        'schedule_$fri': {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]},
        'schedule_$sat': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'New',
          'arranged_at_ms': 5000,
          'exercises': [
            {'name': 'New'}
          ],
        },
      }));
      await Future<void>.delayed(Duration.zero); // let Hive's watch stream drain

      expect(friEvents, isEmpty,
          reason: 'fri\'s merged result equals its existing row -- no Hive '
              'write should have happened');
      expect(satEvents, hasLength(1),
          reason: 'sat genuinely changed -- exactly one write');
      expect(row(sat)!['workout_name'], 'New');

      await subFri.cancel();
      await subSat.cancel();
    });

    test(
        'kill switch disable_plan_merge_skip_when_known=true forces an '
        'unconditional write even for an unchanged row', () async {
      const fri = '2026-09-25';
      await put(fri, {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]});
      await HiveService.instance.configBox
          .put('disable_plan_merge_skip_when_known', true);
      final events = <void>[];
      final sub = HiveService.instance.workoutBox
          .watch(key: 'schedule_$fri')
          .listen((_) => events.add(null));

      await restorePlan(bundleOf({
        'schedule_$fri': {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]},
      }));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1),
          reason: 'the kill switch reverts to Task 21\'s verbatim '
              'unconditional-put behaviour, byte-identical merged content '
              'notwithstanding');
      await sub.cancel();
      await HiveService.instance.configBox
          .delete('disable_plan_merge_skip_when_known');
    });
  });
}
