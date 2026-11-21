// freeze-refill-sync (T2): the freeze push survives a burst of concurrent
// version bumps. `update_streak_progress` is version-locked (migration 056/096:
// NULL on a mismatch). Pre-fix `_retrySyncFreezesOnceAfterConflict` re-fetched
// once and gave up, so two consecutive bumps (prod 2026-11-02 05:10: expected=198
// then 199) lost the Monday refill push. Now up to SyncFlags.freezePushRetryAttempts
// rounds, each re-fetching the cloud row and re-reading Hive.
//
// Behavioral: the real SyncService.syncFreezes against a stub whose RPC applies
// migration 096's lock verbatim. Positions, not counts: the version carried by
// every request body is asserted IN ORDER.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import '../sync/sync_domain_skip_harness.dart';

const _used = ['2026-10-24', '2026-10-31'];

class _Cloud {
  int avail = 1;
  String? lastRefill = '2026-10-26';
  int version = 196;
  int bumpAfterFetch = 0; // a concurrent writer lands after the next N GETs
  bool rowAbsent = false;
  final List<int> requestVersions = [];
  Map<String, dynamic> row() => {
        'user_id': kTestUserId,
        'streak_freezes_available': avail,
        'streak_freezes_last_refill': lastRefill,
        'streak_freezes_used_dates': _used,
        'streak_freezes_first_pro_grant_done': true,
        'streak_progress_version': version,
      };
}

void main() {
  final h = SyncHarness();
  late _Cloud cloud;
  final events = <String>[];

  setUp(() async {
    await h.setUp();
    h.server.clear();
    cloud = _Cloud();
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests = (op, {String? message}) {
      if (op.startsWith('sync_freezes')) events.add('$op ${message ?? ''}');
    };
    setTestClockTo(DateTime(2026, 11, 2, 10, 40));
    h.server.rpcResponders['update_streak_progress'] = (r) {
      final b = Map<String, dynamic>.from((r.body ?? const {}) as Map);
      final exp = (b['p_expected_version'] as num?)?.toInt() ?? -1;
      cloud.requestVersions.add(exp);
      if (exp != cloud.version) return const StubRpcReply(200, null);
      cloud.avail = b['p_freezes_available'] as int;
      cloud.lastRefill = b['p_freezes_last_refill'] as String?;
      cloud.version++;
      return StubRpcReply(200, cloud.version);
    };
    h.server.getResponders['user_progress'] = (r) {
      if (cloud.rowAbsent) return <Map<String, dynamic>>[];
      final row = cloud.row();
      if (cloud.bumpAfterFetch > 0) {
        cloud.bumpAfterFetch--;
        cloud.version++;
      }
      return [row];
    };
    // Local: the refill just happened ({1, this Monday}); the local version
    // stamp is STALE (190) so the first RPC mismatches, as in prod.
    await HiveService.instance.userBox.put('progress', {
      'streak_freezes_available': 1,
      'streak_freezes_last_refill': '2026-11-02',
      'streak_freeze_used_dates': _used,
      'streak_progress_version': 190,
    });
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    resetTestClock();
    await h.tearDown();
  });

  test('two consecutive bumps are survived: every round carries the re-fetched version, the push lands', () async {
    cloud.bumpAfterFetch = 2;
    await SyncService.instance.syncFreezes();
    expect(cloud.requestVersions, [190, 196, 197, 198]);
    expect(cloud.avail, 1, reason: 'the refilled value reached the cloud');
    expect(cloud.lastRefill, '2026-11-02');
    expect(cloud.version, 199);
    expect(events.where((e) => e.startsWith('sync_freezes_retry_dropped')), isEmpty);
  });

  test('a writer that always wins: bounded to 1 + 3 requests, ONE drop event after the last round', () async {
    cloud.bumpAfterFetch = 99;
    await SyncService.instance.syncFreezes();
    expect(cloud.requestVersions, [190, 196, 197, 198]);
    expect(cloud.avail, 1, reason: 'nothing was written');
    final drops = events.where((e) => e.startsWith('sync_freezes_retry_dropped')).toList();
    expect(drops, hasLength(1));
    expect(drops.single, contains('expected=198'));
    expect(drops.single, contains('3 retries'));
  });

  test('kill switch disable_freeze_push_attempts restores the single retry (same requests, same drop text)', () async {
    await HiveService.instance.configBox.put('disable_freeze_push_attempts', true);
    cloud.bumpAfterFetch = 99;
    await SyncService.instance.syncFreezes();
    expect(cloud.requestVersions, [190, 196]);
    final drops = events.where((e) => e.startsWith('sync_freezes_retry_dropped')).toList();
    expect(drops, hasLength(1));
    expect(drops.single, contains('one retry'));
  });

  test('cloud row absent on the re-fetch: no further RPC and no drop event (a different event)', () async {
    cloud.rowAbsent = true;
    await SyncService.instance.syncFreezes();
    expect(cloud.requestVersions, [190]);
    expect(events.where((e) => e.startsWith('sync_freezes_row_absent_after_conflict')), hasLength(1));
    expect(events.where((e) => e.startsWith('sync_freezes_retry_dropped')), isEmpty);
  });

  test('a same-device write landing during the retry is folded in: each round re-reads Hive fresh', () async {
    // A consume lands between the first RPC and the re-fetch (routine: every
    // commitConsume / commitRefill fires an unawaited syncFreezes).
    h.server.getResponders['user_progress'] = (r) {
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freezes_last_refill': '2026-11-02',
        'streak_freeze_used_dates': _used,
        'streak_progress_version': 190,
      });
      return [cloud.row()];
    };
    await SyncService.instance.syncFreezes();
    expect(cloud.requestVersions, [190, 196]);
    expect(cloud.avail, 0, reason: 'the retry pushed the FRESH local value, not the captured 1');
  });

  test('Hive changes between rounds 2 and 3: the LAST round pushes the value read fresh in that round', () async {
    cloud.bumpAfterFetch = 2; // rounds 1 and 2 lose, round 3 lands
    var gets = 0;
    final base = h.server.getResponders['user_progress']!;
    h.server.getResponders['user_progress'] = (r) {
      gets++;
      // a consume lands right after round 2's fetch, before round 3 starts
      if (gets == 3) {
        HiveService.instance.userBox.put('progress', {
          'streak_freezes_available': 0,
          'streak_freezes_last_refill': '2026-11-02',
          'streak_freeze_used_dates': _used,
          'streak_progress_version': 190,
        });
      }
      return base(r);
    };
    await SyncService.instance.syncFreezes();
    expect(cloud.requestVersions, [190, 196, 197, 198]);
    expect(cloud.avail, 0, reason: 'round 3 re-read Hive (0), not the captured/round-1 value (1)');
  });

  test('presence pin: ownership is re-checked before EVERY retry round after the first (round 1 stays the pre-fix path); presence only, a behavioral owner flip is a timing race', () {
    final src = File('lib/core/services/sync/sync_restore_completeness.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final loop = src.indexOf('for (var round = 1; round <= maxRounds; round++)');
    expect(loop, greaterThan(0));
    final guard = src.indexOf('round > 1 && HiveUserSession.currentOwnerFullId != userId) return;', loop);
    final firstFetch = src.indexOf(".from('user_progress')", loop);
    expect(guard, greaterThan(loop));
    expect(guard, lessThan(firstFetch), reason: 'guard precedes the first fetch of each round');
  });
}
