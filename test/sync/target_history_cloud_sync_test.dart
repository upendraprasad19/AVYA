// BEHAVIORAL TEST: cloud backup of the nutrition target history
// (docs/plans/target-history-cloud.md). The real Supabase client is pointed
// at a local stub server (SyncHarness), so every request is a real PostgREST
// call. The SQL side of `merge_target_history` is proven by
// test/sql/target_history_merge_local.sh; the stub only records calls.
//
// P  push (`pushTargetHistory`): after the profile upsert, never before or
//    without it; the day-bound memory; `false` (no row) and failures keep no
//    memory; kill switch; owner; sign-out.
// R  restore (`_restoreUserProfile` -> `TargetHistoryService.adoptFromCloud`):
//    merged BEFORE the profile write; the profile map never holds the list;
//    owner swap; kill switch; the bootstrapper merge strips too.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_retry_controller.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/profile/services/profile_cloud_merge.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _rpc = 'merge_target_history';

Map<String, dynamic> _entry(String from, int cal, int atMs,
        {String strategy = 'balanced'}) =>
    {
      'from': from,
      'calories': cal,
      'protein': 140,
      'carbs': 300,
      'fat': 70,
      'strategy': strategy,
      'at_ms': atMs,
    };

Map<String, dynamic> _profile(int cal) => {
      'id': kTestUserId,
      'daily_calories': cal,
      'protein_grams': 140,
      'carb_grams': 300,
      'fat_grams': 70,
      'current_weight_kg': 80.0,
    };

void main() {
  final h = SyncHarness();
  final today = istDateStr(nowWall());

  setUp(() async {
    await h.setUp();
    h.server
      ..clear()
      ..failWritesTo.clear();
    h.server.rpcResponders.clear();
    h.server.getResponders.clear();
    SyncRetryController.instance.reset();
    await HiveService.instance.syncBox.delete('sync_sweep_owed');
    DietStrategyFlags.debugEnabledOverride = false;
  });
  tearDown(() async {
    DietStrategyFlags.debugEnabledOverride = null;
    SyncRetryController.instance.reset();
    await h.tearDown();
  });

  final userBox = () => HiveService.instance.userBox;
  Iterable<StubRequest> rpcCalls() =>
      h.server.requests.where((r) => r.rpcName == _rpc);
  bool sweepOwed() =>
      HiveService.instance.syncBox.get('sync_sweep_owed') == true;
  Future<void> setList(List<Map<String, dynamic>> l) =>
      userBox().put(TargetHistoryService.boxKey, l);
  List<(String, int, int)> list() => [
        for (final e in TargetHistoryService.read())
          (e.from, e.calories, e.atMs),
      ];
  Object? memory() => userBox().get(TargetHistoryService.pushedKey);
  void rpcReturns(Object? body, [int status = 200]) =>
      h.server.rpcResponders[_rpc] = (_) => StubRpcReply(status, body);
  final push = SyncService.instance.pushTargetHistory;

  group('P: push', () {
    test('sends the local list, oldest first, and remembers it for the day',
        () async {
      rpcReturns(true);
      await setList([_entry('2026-01-05', 2400, 1), _entry('2026-03-01', 2500, 2)]);
      await push(kTestUserId);
      final body = rpcCalls().single.body! as Map;
      expect(body.keys, ['p_entries']);
      expect(body['p_entries'],
          [_entry('2026-01-05', 2400, 1), _entry('2026-03-01', 2500, 2)]);
      final expected = SyncFingerprint.of(
          [_entry('2026-01-05', 2400, 1), _entry('2026-03-01', 2500, 2)]);
      expect(memory(), '$expected|$today');
    });

    test('the memory skips a repeat; a changed list or a new day is sent',
        () async {
      rpcReturns(true);
      await setList([_entry('2026-01-05', 2400, 1)]);
      await push(kTestUserId);
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(1));

      await setList([_entry('2026-01-05', 2400, 2)]);
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(2), reason: 'only at_ms changed: sent');

      // The same list remembered on ANOTHER day is sent again (heals a cloud
      // value lost out of band).
      final fp = (memory()! as String).split('|').first;
      await userBox().put(TargetHistoryService.pushedKey, '$fp|2020-01-01');
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(3));
      expect(memory(), '$fp|$today');
    });

    test('false from the function (no user_profile row) keeps no memory',
        () async {
      rpcReturns(false);
      await setList([_entry('2026-01-05', 2400, 1)]);
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(1));
      expect(memory(), isNull);
      expect(sweepOwed(), isFalse, reason: 'not a failure');
      rpcReturns(null);
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(2), reason: 'retried: nothing remembered');
      expect(memory(), isNull, reason: 'only an explicit true is a confirm');
    });

    test('an outage-shaped failure reports upsert_target_history, no memory',
        () async {
      rpcReturns({'message': 'Service Unavailable'}, 503);
      await setList([_entry('2026-01-05', 2400, 1)]);
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(1));
      expect(sweepOwed(), isTrue, reason: 'a swept push arms the sweep');
      expect(memory(), isNull);
    });

    test('a request that does not answer is abandoned after pushTimeout',
        () async {
      final saved = TargetHistoryService.pushTimeout;
      TargetHistoryService.pushTimeout = const Duration(milliseconds: 200);
      addTearDown(() => TargetHistoryService.pushTimeout = saved);
      h.server.rpcResponders[_rpc] = (_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return const StubRpcReply(200, true);
      };
      await setList([_entry('2026-01-05', 2400, 1)]);
      final sw = Stopwatch()..start();
      await push(kTestUserId);
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 1500)));
      expect(memory(), isNull);
      expect(sweepOwed(), isTrue, reason: 'a timeout is outage-shaped');
      // Let the late reply land: it must not write the memory afterwards.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(memory(), isNull);
    });

    test('from sign-out: a failure is only logged, a success keeps no memory',
        () async {
      rpcReturns({'message': 'Service Unavailable'}, 503);
      await setList([_entry('2026-01-05', 2400, 1)]);
      await push(kTestUserId, fromSignOut: true);
      expect(rpcCalls(), hasLength(1));
      expect(sweepOwed(), isFalse);
      rpcReturns(true);
      await push(kTestUserId, fromSignOut: true);
      expect(rpcCalls(), hasLength(2));
      expect(memory(), isNull);
    });

    test('an owner change DURING the call: no memory, no sweep for the next user',
        () async {
      await setList([_entry('2026-01-05', 2400, 1)]);
      for (final reply in [
        const StubRpcReply(200, true),
        const StubRpcReply(503, {'message': 'Service Unavailable'}),
      ]) {
        HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
        h.server.rpcResponders[_rpc] = (_) {
          HiveUserSession.debugCurrentUidResolverForTests =
              () => 'someone-else';
          return reply;
        };
        await push(kTestUserId);
        expect(memory(), isNull);
        expect(sweepOwed(), isFalse);
      }
      expect(rpcCalls(), hasLength(2));
    });

    test('nothing is sent: empty list, kill switch, another owner', () async {
      rpcReturns(true);
      await push(kTestUserId);
      expect(rpcCalls(), isEmpty, reason: 'empty list');

      await setList([_entry('2026-01-05', 2400, 1)]);
      await HiveService.instance.configBox
          .put(TargetHistoryService.cloudKillSwitch, true);
      await push(kTestUserId);
      expect(rpcCalls(), isEmpty, reason: 'kill switch');
      await HiveService.instance.configBox
          .delete(TargetHistoryService.cloudKillSwitch);

      await push('someone-else');
      expect(rpcCalls(), isEmpty, reason: 'not the open session');
      HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
      await push(kTestUserId);
      expect(rpcCalls(), isEmpty, reason: 'the live account changed');
      // Live account X while the OPEN boxes are still the test user's: the
      // list on disk is not X's and must not be sent under X's session.
      await push('someone-else');
      expect(rpcCalls(), isEmpty, reason: 'the open boxes are not this user\'s');
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(1), reason: 'control: now it is sent');
    });

    group('rides the profile sync', () {
      Future<void> seed() async {
        await userBox().put('profile', _profile(2400));
        await setList([_entry('2026-01-05', 2400, 1)]);
      }

      int profileUpsertAt() => h.server.requests
          .indexWhere((r) => r.isWrite && r.table == 'user_profile');
      int rpcAt() => h.server.requests.indexWhere((r) => r.rpcName == _rpc);

      for (final reliability in [true, false]) {
        test('after a successful upsert (sync_reliability_v1=$reliability)',
            () async {
          rpcReturns(true);
          await HiveService.instance.configBox
              .put('sync_reliability_v1', reliability);
          await seed();
          await SyncService.instance.syncProfileNow(kTestUserId);
          expect(profileUpsertAt(), greaterThanOrEqualTo(0));
          expect(rpcAt(), greaterThan(profileUpsertAt()),
              reason: 'the row must exist before the merge');
          expect(rpcCalls(), hasLength(1));
        });

        test('NOT after a failed upsert (sync_reliability_v1=$reliability)',
            () async {
          rpcReturns(true);
          await HiveService.instance.configBox
              .put('sync_reliability_v1', reliability);
          await seed();
          h.server.failWritesTo.add('user_profile');
          await SyncService.instance.syncProfileNow(kTestUserId);
          expect(profileUpsertAt(), greaterThanOrEqualTo(0),
              reason: 'precondition: the upsert was attempted');
          expect(rpcCalls(), isEmpty);
        });
      }

      test('no local profile: no push', () async {
        rpcReturns(true);
        await setList([_entry('2026-01-05', 2400, 1)]);
        await SyncService.instance.syncProfileNow(kTestUserId);
        expect(rpcCalls(), isEmpty);
      });
    });

    test('the sign-out teardown pushes BEFORE the wipe, bounded, from sign-out',
        () {
      // `_teardown` has no behavioural harness: this pins the ORDER and the
      // bound; the push itself is proven above.
      final src = File('lib/features/auth/providers/auth_provider.dart')
          .readAsStringSync();
      final start = src.indexOf('Future<void> _teardown()');
      final wipe = src.indexOf('clearAllData()', start);
      final pushAt = src.indexOf('pushTargetHistory(', start);
      expect(start, greaterThan(0));
      expect(pushAt, greaterThan(start));
      expect(pushAt, lessThan(wipe));
      final call = src.substring(pushAt, wipe);
      expect(call, contains('fromSignOut: true'));
      expect(call, contains('.timeout(const Duration(seconds: 2))'));
    });
  });

  group('R: restore', () {
    Future<void> restore(Object? cloudHistory,
        {Map<String, dynamic> extra = const {}}) =>
        SyncService.instance.restoreUserProfileForTest(
          kTestUserId,
          preFetched: [
            {
              'user_id': kTestUserId,
              ..._profile(2400),
              'target_history': cloudHistory,
              ...extra,
            }..remove('id'),
          ],
          preFetchedUsers: {'full_name': 'T', 'email': 't@example.com'},
        );
    Map profile() => userBox().get('profile') as Map;

    test('a fresh device adopts the cloud list; the profile write adds nothing',
        () async {
      await restore(
          [_entry('2026-01-05', 2300, 1), _entry('2026-03-01', 2400, 2)]);
      expect(profile()['daily_calories'], 2400, reason: 'precondition');
      // Adopted BEFORE the profile write: its reconcile saw 2400 in force
      // since 2026-03-01 and recorded nothing for today.
      expect(list(), [('2026-01-05', 2300, 1), ('2026-03-01', 2400, 2)]);
    });

    test('without a cloud list the profile write records today (control)',
        () async {
      await restore(null);
      expect(list().map((e) => (e.$1, e.$2)), [(today, 2400)]);
    });

    test('local and cloud are merged: union, newer at_ms per day', () async {
      await setList([
        _entry('2026-02-01', 2350, 5),
        _entry('2026-03-01', 2400, 9),
      ]);
      await userBox().put('profile', _profile(2400));
      await restore([
        _entry('2026-01-05', 2300, 1),
        _entry('2026-02-01', 9999, 4),
        _entry('2026-03-01', 2450, 10),
      ], extra: {'daily_calories': 2450});
      expect(list(), [
        ('2026-01-05', 2300, 1),
        ('2026-02-01', 2350, 5),
        ('2026-03-01', 2450, 10),
      ]);
    });

    test('adopted also when the profile itself is unchanged (early return)',
        () async {
      await restore(null);
      await setList([_entry('2026-03-01', 2400, 2)]);
      final before = Map.of(profile());
      await restore([_entry('2026-01-05', 2300, 1)]);
      expect(Map.of(profile())..remove('updated_at'),
          before..remove('updated_at'),
          reason: 'precondition: nothing about the profile changed');
      expect(list(), [('2026-01-05', 2300, 1), ('2026-03-01', 2400, 2)]);
    });

    test('the profile map never holds the list: cloud key and a stale local key',
        () async {
      await userBox().put('profile', {
        ..._profile(2300),
        'target_history': [_entry('2025-01-01', 1, 1)],
      });
      await restore([_entry('2026-01-05', 2300, 1)]);
      expect(profile()['daily_calories'], 2400, reason: 'precondition: merged');
      expect(profile().containsKey('target_history'), isFalse);
    });

    test('kill switch: nothing adopted, the key is still stripped', () async {
      await HiveService.instance.configBox
          .put(TargetHistoryService.cloudKillSwitch, true);
      await restore([_entry('2026-01-05', 2300, 1)]);
      expect(list().map((e) => e.$1), [today],
          reason: 'only the local recording of the profile write');
      expect(profile().containsKey('target_history'), isFalse);
    });

    test('another account became live before the adopt: nothing is merged',
        () async {
      HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
      await restore([_entry('2026-01-05', 2300, 1)]);
      expect(list().where((e) => e.$1 == '2026-01-05'), isEmpty);
    });

    test('a restore for a user whose boxes are NOT the open ones merges nothing',
        () async {
      // Live account X, open boxes still the test user's: X's cloud list must
      // not land in the test user's box.
      HiveUserSession.debugCurrentUidResolverForTests = () => 'user-x';
      await SyncService.instance.restoreUserProfileForTest(
        'user-x',
        preFetched: [
          {
            'user_id': 'user-x',
            'target_history': [_entry('2026-01-05', 2300, 1)],
          },
        ],
        preFetchedUsers: {'full_name': 'X', 'email': 'x@example.com'},
      );
      expect(list().where((e) => e.$1 == '2026-01-05'), isEmpty);
    });

    test('adoptFromCloud refuses a session that is not the given owner', () {
      expect(
          TargetHistoryService.adoptFromCloud([_entry('2026-01-05', 2300, 1)],
              ownerId: 'someone-else'),
          isFalse);
      expect(list(), isEmpty);
      expect(
          TargetHistoryService.adoptFromCloud([_entry('2026-01-05', 2300, 1)],
              ownerId: kTestUserId),
          isTrue);
      expect(list(), [('2026-01-05', 2300, 1)]);
      expect(
          TargetHistoryService.adoptFromCloud([_entry('2026-01-05', 2300, 1)],
              ownerId: kTestUserId),
          isFalse,
          reason: 'nothing new: no write');
      expect(
          TargetHistoryService.adoptFromCloud('junk', ownerId: kTestUserId),
          isFalse);
    });

    test('a cloud entry dated after today is not adopted', () async {
      await restore([_entry('2999-01-01', 2300, 1), _entry('2026-03-01', 2400, 2)]);
      expect(list(), [('2026-03-01', 2400, 2)]);
    });

    test('a merged list that the cloud lacks is pushed by the next profile sync',
        () async {
      h.server.rpcResponders[_rpc] = (_) => const StubRpcReply(200, true);
      await setList([_entry('2026-02-01', 2350, 5)]);
      await userBox().put('profile', _profile(2400));
      await push(kTestUserId);
      expect(rpcCalls(), hasLength(1));
      await restore([_entry('2026-01-05', 2300, 1)]);
      await SyncService.instance.syncProfileNow(kTestUserId);
      expect(rpcCalls(), hasLength(2));
      final sent = ((rpcCalls().last.body! as Map)['p_entries'] as List)
          .map((e) => (e as Map)['from']);
      expect(sent, containsAll(['2026-01-05', '2026-02-01']));
    });

    test('stated limit (plan R7): PRO unknown at the restore write records '
        'Balanced for today over a cloud Keto entry; the next reconcile heals',
        () async {
      // Documents the limit: the flag is on, PRO reads false in this harness,
      // so the profile write resolves the Balanced split.
      DietStrategyFlags.debugEnabledOverride = true;
      await restore([
        {..._entry(today, 2400, 1, strategy: 'keto'), 'carbs': 30, 'fat': 190},
      ], extra: {'diet_strategy': 'keto'});
      final e = TargetHistoryService.read().single;
      expect((e.from, e.strategy, e.carbs), (today, 'balanced', 300));
      expect(e.atMs, greaterThan(1), reason: 'newer: it would win a push');
    });

    test('the bootstrapper merge strips the cloud list too', () {
      final merged = mergeCloudProfileWithTargets(
        existing: {'daily_calories': 2300, 'target_history': const [1]},
        cloud: {
          'daily_calories': 2400,
          'target_history': [_entry('2026-01-05', 2300, 1)],
        },
        now: DateTime(2026, 11, 25),
        bodyFatCalcDisabled: false,
        recomputeDisabled: true,
      );
      expect(merged['daily_calories'], 2400);
      expect(merged.containsKey('target_history'), isFalse);
    });
  });
}
