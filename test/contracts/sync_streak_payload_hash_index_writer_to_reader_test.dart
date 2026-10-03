// day-swapper+sync-load Task 16 — behavioral contract for the streaks skip
// decision, routed through SyncSkipIndex (domain `streak`, index stored in
// healthBox per plan D12 — streak rows already live there).

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
    await HiveService.instance.healthBox.put('streaks', [
      {
        'week_start': '2026-09-14',
        'workouts_planned': 5,
        'workouts_completed': 3,
        'is_streak_maintained': true,
        'created_at': '2026-09-14T00:00:00.000Z',
      }
    ]);
  }

  Future<void> editOne(int generation) async {
    final box = HiveService.instance.healthBox;
    final list = (box.get('streaks') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    list[0]['workouts_completed'] = 3 + generation;
    await box.put('streaks', list);
  }

  test('the full contract: first push, unchanged skip, edit re-sends, retry after failure, kill switch',
      () async {
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.streak,
      table: 'streaks',
      seed: seed,
      editOne: editOne,
      runPass: () => SyncService.instance.pushStreaksForSyncDomain(),
    );
  });

  test('a row with an empty week_start is skipped and never recorded', () async {
    h.server.clear();
    await HiveService.instance.healthBox.put('streaks', [
      {'week_start': '', 'workouts_planned': 1}
    ]);
    await SyncService.instance.pushStreaksForSyncDomain();
    expect(h.server.writesTo('streaks'), isEmpty);
  });
}
