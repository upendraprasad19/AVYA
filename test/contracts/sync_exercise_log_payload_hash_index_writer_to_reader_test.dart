import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import '../sync/sync_domain_skip_harness.dart';

/// Fix round 1 (2026-09-27) helper. `_reportSyncFailure` fires `unawaited`
/// (the fix brief requires the closure return promptly), so its
/// `log-client-error` POST can land a tick or two after the push call
/// returns; `ErrorTelemetry.recordNonFatal` ALSO posts to `log-client-error`
/// on the SAME failure, but with `op_type` set to its own internal `reason`
/// string (e.g. `sync_service_if_7`), not the domain op string -- so the
/// filter must match on `op_type`, not merely count every log-client-error
/// call. Polls briefly rather than a bare delay -- fast on the happy path,
/// robust under full-suite load contention (CLAUDE.md's own documented class
/// of full-suite-only timing flakiness).
///
/// Fix round 2 (F3, 2026-09-27): this call site only ever needs `isNotEmpty`
/// (at least one report), so the "stop once non-empty" loop shape was never
/// wrong the way the nlog sibling's `hasLength(2)` one was -- but its 500ms
/// deadline is not "generous" under full-suite contention, so a genuinely
/// slow (not dropped) post could still time out and read as a false
/// failure. Raised to 10s for parity with the nlog fix; the happy path is
/// unaffected since the loop still exits the instant the first match lands.
Future<List<dynamic>> _logClientErrorReports(SyncHarness h, String opType,
    {int maxWaitMs = 10000}) async {
  List<dynamic> matches() => h.server.requests
      .where((r) =>
          r.path == '/functions/v1/log-client-error' &&
          r.body is Map &&
          (r.body as Map)['op_type'] == opType)
      .toList();
  final deadline = DateTime.now().add(Duration(milliseconds: maxWaitMs));
  var found = matches();
  while (found.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 20));
    found = matches();
  }
  return found;
}

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
      // Fix round 1 (2026-09-27): _reportSyncFailure is the only path to the
      // server-side client_errors row (via the log-client-error Edge
      // Function) that server alerting reads -- the debugPrint + the
      // preceding ErrorTelemetry.recordNonFatal(reason: 'sync_service_if_7')
      // above are Crashlytics-tagged with an INTERNAL reason string, not the
      // domain op_type (see _logClientErrorReports' doc comment above). The
      // call is `unawaited` (the fix brief requires the closure return
      // promptly), so poll for it rather than assuming it has landed the
      // instant the push returns. The count is exact now: this test used to
      // assert only `isNotEmpty` because `_reportSyncFailure` dual-posted
      // (TWO requests per call). Main's B2a-2b dual-write fix (merged
      // 2026-09-28) made its internal recordNonFatal skipServerPost:true, so
      // ONE call is ONE request (pinned by test/sync/sync_telemetry_test.dart).
      final reports =
          await _logClientErrorReports(h, 'upsert_workout_log_sets');
      expect(reports, hasLength(1),
          reason: 'the per-set failure must report to log-client-error '
              'exactly once, with op_type upsert_workout_log_sets');
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
    test(
        'resetJourney delegates to clearJourneyLocalState, which clears '
        'every domain via SyncSkipIndex.clearAll (day-swapper + sync-load '
        'Task 20 generalized Task 13\'s per-domain symbolic reference — '
        'exlog, sched and nlog — to all 17 domains)', () {
      final src = File('lib/features/dev/simulation_service.dart').readAsStringSync();
      final rjStart = src.indexOf('Future<void> resetJourney(');
      expect(rjStart, isNot(-1), reason: 'resetJourney must exist at this name');
      final rjEnd = src.indexOf('\n  }\n', rjStart);
      final rjBody = src.substring(rjStart, rjEnd == -1 ? src.length : rjEnd);
      expect(rjBody, contains('clearJourneyLocalState()'),
          reason: 'a stale fingerprint entry survives a sim reset and mis-skips the '
              're-drive push unless resetJourney routes through the Hive-only '
              'reset helper');

      final clStart = src.indexOf('Future<void> clearJourneyLocalState(');
      expect(clStart, isNot(-1),
          reason: 'clearJourneyLocalState must exist at this name');
      final clEnd = src.indexOf('\n  }\n', clStart);
      final clBody = src.substring(clStart, clEnd == -1 ? src.length : clEnd);
      expect(clBody, contains('SyncSkipIndex.clearAll('),
          reason: 'clearJourneyLocalState must clear every domain via the '
              'shared helper, not just exlog/sched/nlog individually');
    });
  });
}
