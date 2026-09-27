import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import '../sync/sync_domain_skip_harness.dart';

void main() {
  group('exlogPayloadFingerprint (kept byte-identical -- plan D4, no re-push burst)', () {
    test('same payload -> same fingerprint, 36-char UUID shape', () {
      final summary = {'exercise_id': 'squat', 'reps': 30};
      final sets = [
        {'set_number': 1, 'reps': 10},
        {'set_number': 2, 'reps': 10},
      ];
      final fp1 = SyncService.exlogPayloadFingerprint(summary, sets);
      final fp2 = SyncService.exlogPayloadFingerprint(
          Map.of(summary), sets.map((s) => Map.of(s)).toList());
      expect(fp1, fp2);
      expect(fp1.length, 36);
      expect(fp1[8], '-');
    });

    test('a changed summary field flips the fingerprint', () {
      final sets = [
        {'set_number': 1, 'reps': 10}
      ];
      final fp1 = SyncService.exlogPayloadFingerprint({'reps': 30}, sets);
      final fp2 = SyncService.exlogPayloadFingerprint({'reps': 31}, sets);
      expect(fp1, isNot(fp2));
    });

    test('a changed per-set field flips the fingerprint (edit-not-skipped proof)', () {
      final summary = {'exercise_id': 'squat'};
      final fp1 = SyncService.exlogPayloadFingerprint(
          summary, [{'set_number': 1, 'weight_kg': 60}]);
      final fp2 = SyncService.exlogPayloadFingerprint(
          summary, [{'set_number': 1, 'weight_kg': 65}]);
      expect(fp1, isNot(fp2));
    });

    test('an added/removed set flips the fingerprint (key-set change, not just value)', () {
      final summary = {'exercise_id': 'squat'};
      final fp1 = SyncService.exlogPayloadFingerprint(
          summary, [{'set_number': 1, 'reps': 10}]);
      final fp2 = SyncService.exlogPayloadFingerprint(summary, [
        {'set_number': 1, 'reps': 10},
        {'set_number': 2, 'reps': 8},
      ]);
      expect(fp1, isNot(fp2));
    });
  });

  group('exlog behavioral skip contract (day-swapper + sync-load Task 13)', () {
    final h = SyncHarness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    // Carries a `sets` list (WorkoutWriteService shape) so `_resolvePerSetList`
    // (sync_service.dart:2216) yields a non-empty `pendingSetRows` -- without
    // it the per-set upsert never runs at all, and the second test's
    // `failWritesTo.add('workout_log_sets')` premise would be a no-op.
    Map<String, dynamic> row(int weightKg) => {
          'date': '2026-09-20',
          'exercise_name': 'Squat',
          'weight_kg': weightKg,
          'reps_completed': 5,
          'set_number': 1,
          'created_at': '2026-09-20T10:00:00.000Z',
          'sets': [
            {'weight_kg': weightKg, 'reps': 5},
          ],
        };

    test('the full skip contract (first pass / unchanged skip / edit re-pushes / '
        'retry after failure / kill switch)', () async {
      await expectSkipContract(
        h: h,
        domain: SyncSkipDomain.exlog,
        table: 'workout_log_exercises',
        seed: () => HiveService.instance.workoutBox.put('exlog_2026-09-20_a1b2', row(100)),
        runPass: () => SyncService.instance.pushExerciseLogsForSyncDomain(),
        editOne: (generation) => HiveService.instance.workoutBox
            .put('exlog_2026-09-20_a1b2', row(100 + generation)),
      );
    });

    test('a per-set upsert failure abandons the bundle: nothing recorded, retried whole', () async {
      // The shared SyncHarness's SyncStubServer instance (test/sync/
      // sync_domain_skip_harness.dart) is constructed ONCE for this whole
      // `group`, not per test (test/sync/sync_stub_server_test.dart's own
      // multi-test group relies on the same fact) -- `tearDown` never clears
      // `requests`, so a prior test's un-cleared tail requests are still
      // present here. Clear first so `hasLength` assertions below count only
      // this test's own writes.
      h.server.clear();
      await HiveService.instance.workoutBox.put('exlog_2026-09-20_a1b2', row(100));
      h.server.failWritesTo.add('workout_log_sets');
      await SyncService.instance.pushExerciseLogsForSyncDomain();
      expect(h.server.writesTo('workout_log_exercises'), hasLength(1),
          reason: 'the summary write is attempted even though the sets write will fail');
      expect(
          SyncSkipIndex.readIndex(
              skipBoxOf(SyncSkipDomain.exlog), SyncSkipDomain.exlog.indexKey),
          isEmpty,
          reason: 'a failed per-set write must not confirm the bundle');
      h.server
        ..clear()
        ..failWritesTo.remove('workout_log_sets');
      await SyncService.instance.pushExerciseLogsForSyncDomain();
      expect(h.server.writesTo('workout_log_exercises'), hasLength(1),
          reason: 'the WHOLE bundle (summary + sets) re-pushes next pass, not just the sets');
      expect(h.server.writesTo('workout_log_sets'), hasLength(1));
    });

    test('an account switch between the summary and the sets writes no sets '
        '(guard at the sink; round-3 review S F1)', () async {
      h.server.clear(); // see the previous test's comment -- shared server.
      await HiveService.instance.workoutBox.put('exlog_2026-09-20_a1b2', row(100));
      // The live owner changes the moment the summary write has landed.
      HiveUserSession.debugCurrentUidResolverForTests = () =>
          h.server.writesTo('workout_log_exercises').isEmpty
              ? kTestUserId
              : 'someone-else';
      await SyncService.instance.pushExerciseLogsForSyncDomain();
      expect(h.server.writesTo('workout_log_exercises'), hasLength(1));
      expect(h.server.writesTo('workout_log_sets'), isEmpty,
          reason: 'the sets must not be written under the previous owner');
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
    });
  });

  group('resetJourney clears the index (source contract)', () {
    test('SyncSkipDomain.exlog.indexKey is referenced by resetJourney (day-swapper + '
        'sync-load Task 13 -- repointed from the raw literal to the symbol, since G1 '
        "(check_sync_hash_skip_atomicity.dart's index_literal_outside_helper rule, spec "
        'section 7) forbids a payload_hash_index literal outside sync_skip_index.dart)', () {
      final src = File('lib/features/dev/simulation_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> resetJourney(');
      expect(start, isNot(-1), reason: 'resetJourney must exist at this name');
      final end = src.indexOf('\n  }\n', start);
      final body = src.substring(start, end == -1 ? src.length : end);
      expect(body, contains('SyncSkipDomain.exlog.indexKey'),
          reason: 'a stale fingerprint entry survives a sim reset and mis-skips the '
              're-drive push -- see the sync_sched_payload_hash_index precedent this mirrors');
    });
  });
}
