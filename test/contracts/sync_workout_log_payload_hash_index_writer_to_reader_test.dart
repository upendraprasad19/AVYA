// day-swapper+sync-load Task 16 — behavioral contract for the wlog (workout
// session summary) skip decision, routed through SyncSkipIndex (domain
// `wlog`). No pre-existing index: every pass previously re-upserted every
// wlog_* row unconditionally (the OI-237 write-amplification class).
//
// See docs/diagnoses/2026-09-26-sync-write-amplification-a9d3f6.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<void> seed() async {
    await HiveService.instance.workoutBox.put('wlog_2026-09-20', {
      'id': 'wlog_2026-09-20',
      'type': 'workout_log',
      'workout_name': 'Push A',
      'date': '2026-09-20',
      'completed_at': '2026-09-20T07:00:00.000Z',
      'duration_seconds': 3600,
    });
  }

  Future<void> editOne(int generation) async {
    final box = HiveService.instance.workoutBox;
    final raw = Map<String, dynamic>.from(box.get('wlog_2026-09-20') as Map);
    raw['duration_seconds'] = 3600 + generation;
    await box.put('wlog_2026-09-20', raw);
  }

  test('the full contract: first push, unchanged skip, edit re-sends, retry after failure, kill switch',
      () async {
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.wlog,
      table: 'workout_logs',
      seed: seed,
      editOne: editOne,
      runPass: () => SyncService.instance.pushWorkoutLogsForSyncDomain(),
    );
  });

  test('a row missing date or workout_name is skipped and never recorded (existing null-key guard)',
      () async {
    h.server.clear();
    await HiveService.instance.workoutBox.put('wlog_2026-09-21', {
      'id': 'wlog_2026-09-21',
      'type': 'workout_log',
      'workout_name': '',
      'date': '2026-09-21',
    });
    await SyncService.instance.pushWorkoutLogsForSyncDomain();
    expect(h.server.writesTo('workout_logs'), isEmpty);
    expect(
        SyncSkipIndex.readIndex(HiveService.instance.workoutBox, SyncSkipDomain.wlog.indexKey)
            .containsKey('wlog_2026-09-21'),
        isFalse);
  });

  test('an unresolvable timestamp is omitted, never now(): the second pass skips (round-1 D1 F1)',
      () async {
    h.server.clear();
    // `date` is non-empty (passes the null-key guard) but malformed, and the
    // row carries no timestamp field — before the fix this reached now().
    await HiveService.instance.workoutBox.put('wlog_1775500200000', {
      'id': 'wlog_1775500200000',
      'type': 'workout_log',
      'workout_name': 'Legacy',
      'date': '2026-9-5',
    });
    await SyncService.instance.pushWorkoutLogsForSyncDomain();
    final first = h.server.writesTo('workout_logs');
    expect(first, hasLength(1));
    expect(first.single.rows.single.containsKey('logged_at'), isFalse);
    expect(first.single.rows.single.containsKey('created_at'), isFalse);
    await SyncService.instance.pushWorkoutLogsForSyncDomain();
    expect(h.server.writesTo('workout_logs'), hasLength(1),
        reason: 'a now()-stamped fingerprint differs every pass and re-pushes');
  });

  test('a deleted wlog row leaves the index on the next pass (liveKeys prune)', () async {
    h.server.clear();
    await seed();
    await SyncService.instance.pushWorkoutLogsForSyncDomain();
    final box = HiveService.instance.workoutBox;
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.wlog.indexKey)
        .containsKey('wlog_2026-09-20'), isTrue);
    await box.delete('wlog_2026-09-20');
    await SyncService.instance.pushWorkoutLogsForSyncDomain();
    expect(SyncSkipIndex.readIndex(box, SyncSkipDomain.wlog.indexKey)
        .containsKey('wlog_2026-09-20'), isFalse);
  });
}
