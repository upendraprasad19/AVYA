// OI-530 Landing A (docs/plans/oi530-landing-a-one-plan-read.md): the legacy
// full restore (restoreFromCloudForUser step A, and restoreFromCloud) reads the
// `user_progress` row ONCE and hands it to both _restoreUserProgress and
// _restoreWorkoutPlan. That row carries the whole `plan_json` bundle
// (0.3-1 MB live, 2.28 MB at two years); before this landing each op read it
// itself, so the bundle crossed the wire twice.
//
// Pins: (1) one bare `user_progress` select and no `select=plan_json` read;
// (2) the kill switch `disable_restore_single_plan_fetch` restores today's two
// reads; (3) a failed shared read fails BOTH ops, so the restore-settled marker
// stays closed and the reason names both (the shared read must be STRICT: the
// lightweight helper's swallow-to-[] would have settled the marker over an
// unrestored progress row); (4) restoreFromCloud keeps _restoreWorkoutPlan
// awaited before the Future.wait (APK #12.9), source pin (no harness reaches
// restoreFromCloud: it runs only from checkAndSync on an empty Hive).
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/sync_stub_server.dart' show StubReadReply, StubRequest;
import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.readReplies.clear();
    h.server.clear();
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
  });
  tearDown(() async {
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    await HiveService.instance.configBox
        .delete(SyncService.kDisableRestoreSinglePlanFetchKey);
    await h.tearDown();
  });

  // The PostgREST `select` of each user_progress GET ('*' when absent).
  List<String> progressGets() => [
        for (final StubRequest r in h.server.requests)
          if (r.method == 'GET' && r.path == '/rest/v1/user_progress')
            (r.query['select'] == null || r.query['select']!.isEmpty)
                ? '*'
                : r.query['select']!,
      ];

  test('restoreFromCloudForUser: ONE bare user_progress select, no plan_json '
      'select', () async {
    final r = await SyncService.instance.restoreFromCloudForUser();
    expect(r.succeeded, isTrue, reason: 'error=${r.error}');
    final gets = progressGets().toList();
    expect(gets.where((g) => g == '*'), hasLength(1),
        reason: 'the shared read: before Landing A there were two');
    expect(gets.where((g) => g == 'plan_json'), isEmpty,
        reason: "_restoreWorkoutPlan's own plan_json read must not run");
  });

  test('kill switch ON: today\'s two reads, verbatim', () async {
    await HiveService.instance.configBox
        .put(SyncService.kDisableRestoreSinglePlanFetchKey, true);
    final r = await SyncService.instance.restoreFromCloudForUser();
    expect(r.succeeded, isTrue, reason: 'error=${r.error}');
    final gets = progressGets().toList();
    expect(gets.where((g) => g == '*'), hasLength(1));
    expect(gets.where((g) => g == 'plan_json'), hasLength(1));
  });

  test('a failed shared read fails BOTH ops: the marker is withheld and the '
      'reason names restore_workout_plan AND restore_user_progress', () async {
    h.server.readReplies['user_progress'] =
        const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
    final r = await SyncService.instance.restoreFromCloudForUser();
    expect(r.succeeded, isTrue, reason: 'error=${r.error}');
    expect(SyncService.instance.restoreSettledForCurrentUser, isFalse);
    final why = SyncService.instance.lastRestoreWithheldReason ?? '';
    expect(why, contains('restore_user_progress'));
    expect(why, contains('restore_workout_plan'));
  });

  test('restoreFromCloud: the plan op is awaited BEFORE the Future.wait that '
      'holds the scheduled_workouts overlay (APK #12.9), and the progress op '
      'reuses the same shared read', () {
    final src =
        File('lib/core/services/sync_service.dart').readAsStringSync();
    final start = src.indexOf('Future<void> restoreFromCloud(String userId)');
    expect(start, greaterThan(0));
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    final shared = body.indexOf('_legacyPlanAndProgressRestores(userId)');
    final plan =
        body.indexOf("await _safeRestoreOp('workout_plan', planAndProgress.plan())");
    final wait = body.indexOf('await Future.wait(');
    final progress =
        body.indexOf("_safeRestoreOp('user_progress', planAndProgress.progress())");
    final overlay = body.indexOf("_safeRestoreOp('scheduled_workouts'");
    expect([shared, plan, wait, progress, overlay].every((i) => i > 0), isTrue,
        reason: 'shared=$shared plan=$plan wait=$wait progress=$progress '
            'overlay=$overlay');
    expect(shared < plan && plan < wait && wait < progress && wait < overlay,
        isTrue);
  });
}
