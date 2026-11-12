// BEHAVIORAL TEST — OI-479 "Clear conversation" marker, cloud leg
// (diagnose 5970aa; plan docs/plans/2026-11-12-oi479-clear-conversation.md,
// tests T6 and T7). The real Supabase client is pointed at a local stub
// server (SyncHarness), so every request below is a real PostgREST call.
//
// T6 restore adoption (`_restoreUserPreferences`): max(local, min(cloud,
//    device now)); never lowered; the column never lands in
//    userBox['preferences']; a clear made DURING the fetch survives; an owner
//    swap after the existing sink check writes nothing.
// T7 push (`pushCoachChatClearedAt`): `clear()` pushes the marker through
//    raise_coach_chat_cleared_at; the IST-day memory skips a repeat; an
//    outage-shaped failure reports `upsert_coach_chat_cleared_at` (arms the
//    sweep) except from sign-out; `_syncUserPreferences` pushes even when its
//    own upsert fails; the sign-out teardown pushes BEFORE the wipe.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/coach_chat_clear.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_retry_controller.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _rpc = 'raise_coach_chat_cleared_at';

void main() {
  final h = SyncHarness();

  setUp(() async {
    await h.setUp();
    h.server
      ..clear()
      ..failWritesTo.clear();
    h.server.rpcResponders.clear();
    h.server.getResponders.clear();
    SyncRetryController.instance.reset();
    await HiveService.instance.syncBox.delete('sync_sweep_owed');
  });
  tearDown(() async {
    SyncRetryController.instance.reset();
    await h.tearDown();
  });

  DateTime? marker() => CoachChatClear.clearedAt();
  Future<void> setMarker(DateTime at) => HiveService.instance.userBox.put(
    CoachChatClear.markerKey,
    at.toUtc().toIso8601String(),
  );
  Iterable<StubRequest> rpcCalls() =>
      h.server.requests.where((r) => r.rpcName == _rpc);
  bool sweepOwed() =>
      HiveService.instance.syncBox.get('sync_sweep_owed') == true;

  Future<void> restoreWithCloud(Object? cloudValue) {
    h.server.getResponders['user_preferences'] = (_) => [
      {
        'user_id': kTestUserId,
        'motivational_style': 'tough',
        'coach_chat_cleared_at': cloudValue,
      },
    ];
    return SyncService.instance.restoreUserPreferencesForTest(kTestUserId);
  }

  final t0 = DateTime.utc(2026, 7, 20, 4, 30);

  group('T6 — restore adoption', () {
    test('a newer cloud value raises the local marker', () async {
      await setMarker(t0);
      await restoreWithCloud('2026-07-20T05:30:00.123456+00:00');
      expect(marker(), DateTime.utc(2026, 7, 20, 5, 30, 0, 123, 456));
    });

    test('an older cloud value never lowers it', () async {
      await setMarker(t0);
      await restoreWithCloud('2026-07-19T00:00:00+00:00');
      expect(marker(), t0);
    });

    test('a device with no marker adopts the cloud value', () async {
      await restoreWithCloud('2026-07-20T04:30:00+00:00');
      expect(marker(), t0);
    });

    test(
      'a cloud value later than the device clock is capped at device now',
      () async {
        final before = DateTime.now().toUtc();
        await restoreWithCloud('2100-01-01T00:00:00+00:00');
        final m = marker()!;
        expect(m.isAfter(DateTime.now().toUtc()), isFalse);
        expect(m.isBefore(before), isFalse);
      },
    );

    test('the column never lands in userBox["preferences"]', () async {
      await restoreWithCloud('2026-07-20T04:30:00+00:00');
      final prefs = HiveService.instance.userBox.get('preferences') as Map;
      expect(
        prefs['motivational_style'],
        'tough',
        reason: 'precondition: merged',
      );
      expect(prefs.containsKey('coach_chat_cleared_at'), isFalse);
    });

    test(
      'a clear made DURING the fetch is not lowered by an older cloud value',
      () async {
        await setMarker(t0);
        final duringFetch = t0.add(const Duration(hours: 2));
        h.server.getResponders['user_preferences'] = (_) {
          // The user taps CLEAR while the GET is in flight (Hive's put registers
          // the value synchronously).
          HiveService.instance.userBox.put(
            CoachChatClear.markerKey,
            duringFetch.toIso8601String(),
          );
          return [
            {
              'user_id': kTestUserId,
              'coach_chat_cleared_at': '2026-07-20T05:00:00+00:00',
            },
          ];
        };
        await SyncService.instance.restoreUserPreferencesForTest(kTestUserId);
        expect(marker(), duringFetch);
      },
    );

    test('an account swap after the preferences write adopts nothing', () async {
      // The swap lands while `userBox.put('preferences')` is in flight: the
      // box's change event fires before that put completes, AFTER the method's
      // existing owner check. Only the adoption block's own fresh check can
      // stop the marker.
      final sub = HiveService.instance.userBox.watch(key: 'preferences').listen(
        (_) {
          // ignore: invalid_use_of_visible_for_testing_member
          HiveUserSession.debugCurrentUidResolverForTests = () =>
              'someone-else';
        },
      );
      addTearDown(sub.cancel);
      await restoreWithCloud('2026-07-20T04:30:00+00:00');
      expect(
        HiveService.instance.userBox.get('preferences'),
        isNotNull,
        reason: 'precondition: the swap happened after the preferences write',
      );
      expect(marker(), isNull);
    });
  });

  group('T7 — push', () {
    Future<void> waitForRpc(int n) async {
      for (var i = 0; i < 200 && rpcCalls().length < n; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('clear() stamps the marker and pushes it through the RPC', () async {
      h.server.rpcResponders[_rpc] = (_) => const StubRpcReply(200, null);
      expect(await CoachChatClear.clear(), isTrue);
      await waitForRpc(1);
      // The push is fire-and-forget: wait for its memory write after the reply.
      for (
        var i = 0;
        i < 200 &&
            HiveService.instance.userBox.get(CoachChatClear.pushedKey) == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final m = marker()!;
      expect(rpcCalls(), hasLength(1));
      final body = rpcCalls().single.body;
      expect(body, isA<Map>());
      expect((body! as Map)['p_at'], m.toIso8601String());
      expect(
        HiveService.instance.userBox.get(CoachChatClear.pushedKey),
        startsWith('${m.toIso8601String()}|'),
      );
    });

    test('the pushed-memory skips a repeat push the same IST day', () async {
      h.server.rpcResponders[_rpc] = (_) => const StubRpcReply(200, null);
      await setMarker(t0);
      await SyncService.instance.pushCoachChatClearedAt(kTestUserId);
      await SyncService.instance.pushCoachChatClearedAt(kTestUserId);
      expect(rpcCalls(), hasLength(1));
      await setMarker(t0.add(const Duration(minutes: 1)));
      await SyncService.instance.pushCoachChatClearedAt(kTestUserId);
      expect(rpcCalls(), hasLength(2), reason: 'a newer marker is pushed');
    });

    test(
      'an outage-shaped failure reports upsert_coach_chat_cleared_at and keeps '
      'no memory',
      () async {
        h.server.rpcResponders[_rpc] = (_) =>
            const StubRpcReply(503, {'message': 'Service Unavailable'});
        await setMarker(t0);
        await SyncService.instance.pushCoachChatClearedAt(kTestUserId);
        expect(rpcCalls(), hasLength(1));
        expect(sweepOwed(), isTrue, reason: 'a swept push arms the sweep');
        expect(
          HiveService.instance.userBox.get(CoachChatClear.pushedKey),
          isNull,
        );
      },
    );

    test(
      'from sign-out a failure is only logged: no sweep armed for the next user',
      () async {
        h.server.rpcResponders[_rpc] = (_) =>
            const StubRpcReply(503, {'message': 'Service Unavailable'});
        await setMarker(t0);
        await SyncService.instance.pushCoachChatClearedAt(
          kTestUserId,
          fromSignOut: true,
        );
        expect(rpcCalls(), hasLength(1));
        expect(sweepOwed(), isFalse);
        expect(
          HiveService.instance.userBox.get(CoachChatClear.pushedKey),
          isNull,
        );
      },
    );

    test(
      'from sign-out a success writes no memory either (the box is wiped next)',
      () async {
        h.server.rpcResponders[_rpc] = (_) => const StubRpcReply(200, null);
        await setMarker(t0);
        await SyncService.instance.pushCoachChatClearedAt(
          kTestUserId,
          fromSignOut: true,
        );
        expect(rpcCalls(), hasLength(1));
        expect(
          HiveService.instance.userBox.get(CoachChatClear.pushedKey),
          isNull,
        );
      },
    );

    test(
      '_syncUserPreferences pushes the marker even when its own upsert fails',
      () async {
        h.server.rpcResponders[_rpc] = (_) => const StubRpcReply(200, null);
        await HiveService.instance.userBox.put('preferences', {
          'motivational_style': 'tough',
        });
        h.server.failWritesTo.add('user_preferences');
        await setMarker(t0);
        await SyncService.instance.syncUserPreferencesForTest(kTestUserId);
        expect(
          h.server.writesTo('user_preferences'),
          isNotEmpty,
          reason: 'precondition: the upsert was attempted and failed',
        );
        expect(rpcCalls(), hasLength(1));
      },
    );

    test('no marker, no push', () async {
      await SyncService.instance.pushCoachChatClearedAt(kTestUserId);
      expect(rpcCalls(), isEmpty);
    });

    test(
      'the sign-out teardown pushes BEFORE the wipe, bounded, from sign-out',
      () {
        // `_teardown` is private and has no behavioural harness (plan T7): this
        // pin holds the ORDER and the bound; the push itself is proven above.
        final src = File(
          'lib/features/auth/providers/auth_provider.dart',
        ).readAsStringSync();
        final start = src.indexOf('Future<void> _teardown()');
        final end = src.indexOf('\n  /// OI-51', start);
        expect(start, greaterThan(0));
        expect(end, greaterThan(start));
        final body = src.substring(start, end);
        final push = body.indexOf('pushCoachChatClearedAt(');
        final wipe = body.indexOf('clearAllData()');
        expect(push, greaterThan(0));
        expect(
          push,
          lessThan(wipe),
          reason: 'the marker must leave before the wipe',
        );
        final call = body.substring(push, wipe);
        expect(call, contains('fromSignOut: true'));
        expect(call, contains('.timeout(const Duration(seconds: 2))'));
      },
    );
  });
}
