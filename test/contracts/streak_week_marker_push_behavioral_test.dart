// C2 (diagnose a3c8f1) — the week marker (`last_counted_week_key`) goes to the
// cloud through `raise_streak_week_marker`, best effort, after a successful
// progress snapshot push. Drives the REAL SyncService against the local stub
// server (`rpcResponders`), so a failure in one rpc can be injected per function.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import '../sync/sync_domain_skip_harness.dart';

const _snapshot = 'update_user_progress_snapshot';
const _marker = 'raise_streak_week_marker';
const _memoryKey = 'streak_week_marker_pushed';
const _otherUser = '7c1b24d9-aaaa-bbbb-cccc-eeeeeeeeeeee';

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    // One stub server for the whole file: start every test from a clean log
    // and no leftover responders.
    h.server.clear();
    h.server.rpcResponders.clear();
    h.server.getResponders.clear();
  });
  tearDown(h.tearDown);

  Future<void> seed({Object? marker = 20731}) async {
    await HiveService.instance.userBox.put('progress', {
      'current_phase': 1,
      'total_workouts_done': 3,
      'current_streak_weeks': 2,
      'streak_progress_version': 5,
      if (marker != null) 'last_counted_week_key': marker,
    });
  }

  Iterable<StubRequest> markerCalls() =>
      h.server.requests.where((r) => r.path == '/rest/v1/rpc/$_marker');

  // The snapshot RPC answers a version (success); the marker rpc answers 200.
  void snapshotSucceeds() {
    h.server.rpcResponders[_snapshot] = (_) => const StubRpcReply(200, 6);
    h.server.rpcResponders[_marker] = (_) => const StubRpcReply(200, 20731);
  }

  Future<void> run() => SyncService.instance.syncUserProgressForTest(kTestUserId);

  group('push', () {
    test('after a non-null first-attempt version the marker is pushed', () async {
      await seed();
      snapshotSucceeds();
      await run();
      final calls = markerCalls().toList();
      expect(calls, hasLength(1));
      final body = calls.single.body! as Map;
      expect(body['p_user_id'], kTestUserId);
      expect(body['p_week_key'], 20731);
      expect(HiveService.instance.configBox.get(_memoryKey),
          '$kTestUserId:20731:${istDateStr(nowWall())}',
          reason: 'the memory carries the user id (configBox is shared) and '
              'the IST day (a stale memory heals within a day)');
    });

    test('a conflict followed by a successful retry still pushes it', () async {
      await seed();
      var snapshotCalls = 0;
      h.server.rpcResponders[_snapshot] = (_) {
        snapshotCalls++;
        return snapshotCalls == 1
            ? const StubRpcReply(200, null) // version mismatch
            : const StubRpcReply(200, 7);
      };
      h.server.rpcResponders[_marker] = (_) => const StubRpcReply(200, 20731);
      h.server.getResponders['user_progress'] =
          (_) => {'streak_progress_version': 6};
      await run();
      expect(snapshotCalls, 2);
      expect(markerCalls(), hasLength(1),
          reason: 'seat B round-1 P2-1: the retry path must push it too');
    });

    test('two consecutive conflicts push nothing', () async {
      await seed();
      h.server.rpcResponders[_snapshot] = (_) => const StubRpcReply(200, null);
      h.server.rpcResponders[_marker] = (_) => const StubRpcReply(200, 20731);
      h.server.getResponders['user_progress'] =
          (_) => {'streak_progress_version': 6};
      await run();
      expect(markerCalls(), isEmpty);
    });

    test('an absent, negative or non-numeric marker is not pushed', () async {
      snapshotSucceeds();
      for (final m in <Object?>[null, -1, 'x']) {
        h.server.clear();
        await seed(marker: m);
        await run();
        expect(markerCalls(), isEmpty, reason: 'marker=$m');
      }
    });

    test('an unchanged marker is pushed once, a raised one again', () async {
      snapshotSucceeds();
      await seed();
      await run();
      await run();
      expect(markerCalls(), hasLength(1),
          reason: 'the memory stops a round trip on every progress sync');
      await seed(marker: 20738);
      await run();
      expect(markerCalls(), hasLength(2));
    });

    test('a memory from an earlier IST day re-pushes (the cloud may have been '
        'reset out of band), a memory from today does not', () async {
      snapshotSucceeds();
      await seed();
      await HiveService.instance.configBox
          .put(_memoryKey, '$kTestUserId:20731:2000-01-01');
      await run();
      expect(markerCalls(), hasLength(1));
      expect(HiveService.instance.configBox.get(_memoryKey),
          '$kTestUserId:20731:${istDateStr(nowWall())}');
      await run();
      expect(markerCalls(), hasLength(1), reason: 'same IST day: skipped');
    });

    test('the kill switch skips the call', () async {
      snapshotSucceeds();
      await seed();
      await HiveService.instance.configBox
          .put('disable_streak_week_marker_push', true);
      await run();
      expect(markerCalls(), isEmpty);
      expect(HiveService.instance.configBox.get(_memoryKey), isNull);
    });

    test('a push for a user who is not the session owner is skipped', () async {
      snapshotSucceeds();
      await seed();
      await SyncService.instance.syncUserProgressForTest(_otherUser);
      expect(markerCalls(), isEmpty);
    });

    test('the marker sent is the PRE-await value, not a re-read', () async {
      await seed();
      h.server.rpcResponders[_snapshot] = (_) async {
        // A write landing during the snapshot await must not change what the
        // marker push sends (the push reads the pre-await map).
        await HiveService.instance.userBox.put('progress', {
          'current_phase': 1,
          'last_counted_week_key': 99999,
        });
        return const StubRpcReply(200, 6);
      };
      h.server.rpcResponders[_marker] = (_) => const StubRpcReply(200, 20731);
      await run();
      expect((markerCalls().single.body! as Map)['p_week_key'], 20731);
    });
  });

  group('failure is contained', () {
    test('a missing function (PGRST202) is swallowed, not remembered, retried',
        () async {
      await seed();
      h.server.rpcResponders[_snapshot] = (_) => const StubRpcReply(200, 6);
      h.server.rpcResponders[_marker] = (_) => const StubRpcReply(404, {
            'code': 'PGRST202',
            'message': 'Could not find the function',
          });
      await run(); // must not throw
      expect(markerCalls(), hasLength(1));
      expect(HiveService.instance.configBox.get(_memoryKey), isNull,
          reason: 'memory is written only on success');
      await run();
      expect(markerCalls(), hasLength(2),
          reason: 'a failed push is retried by the next progress sync');
    });

    test('a transport error is swallowed and enqueues nothing', () async {
      await seed();
      h.server.rpcResponders[_snapshot] = (_) => const StubRpcReply(200, 6);
      h.server.rpcResponders[_marker] =
          (_) => const StubRpcReply(0, null, dropConnection: true);
      await run(); // must not throw
      expect(HiveService.instance.configBox.get(_memoryKey), isNull);
      expect(SyncQueue.instance.hasPendingMarker('sync_user_progress', kTestUserId),
          isFalse,
          reason: 'a marker-push failure must not enqueue a progress marker');
    });

    test('a failed marker push does not fail a queue drain', () async {
      await seed();
      h.server.rpcResponders[_snapshot] = (_) => const StubRpcReply(200, 6);
      h.server.rpcResponders[_marker] =
          (_) => const StubRpcReply(500, {'message': 'boom'});
      await SyncService.instance
          .syncUserProgressForTest(kTestUserId, fromQueue: true);
      expect(SyncQueue.instance.hasPendingMarker('sync_user_progress', kTestUserId),
          isFalse);
    });

    test('an owner swap during the await writes no memory', () async {
      await seed();
      h.server.rpcResponders[_snapshot] = (_) => const StubRpcReply(200, 6);
      h.server.rpcResponders[_marker] = (_) async {
        await HiveUserSession.openForUser(_otherUser);
        return const StubRpcReply(200, 20731);
      };
      await run();
      expect(markerCalls(), hasLength(1));
      expect(HiveService.instance.configBox.get(_memoryKey), isNull,
          reason: "A's memory must not land in B's session (shared configBox)");
    });
  });
}
