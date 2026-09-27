@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('user_custom_exercises: push/skip/edit/retry/kill-switch contract', () async {
    var sets = 3;
    await HiveService.instance.customBox.put('custom_exercise_1', {
      'id': 'ce-1',
      'name': 'L Sit',
      'logging_type': 'timed',
      'default_sets': sets,
    });
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.customItem,
      table: 'user_custom_exercises',
      seed: () async {},
      runPass: () => SyncService.instance.pushCustomItemsForSyncDomain(),
      editOne: (gen) async {
        sets = 3 + gen;
        await HiveService.instance.customBox.put('custom_exercise_1', {
          'id': 'ce-1',
          'name': 'L Sit',
          'logging_type': 'timed',
          'default_sets': sets,
        });
      },
    );
  });

  test('an exercise and a food push independently in the same pass (shared index, disjoint row keys)',
      () async {
    // The shared SyncStubServer (sync_domain_skip_harness.dart) is
    // constructed ONCE for this whole file, not per test -- tearDown never
    // clears `requests`, so the previous test's kill-switch-phase tail
    // requests are still present here (established pattern, see
    // sync_exercise_log_payload_hash_index_writer_to_reader_test.dart).
    h.server.clear();
    await HiveService.instance.customBox.put('custom_exercise_1',
        {'id': 'ce-1', 'name': 'L Sit', 'logging_type': 'timed'});
    await HiveService.instance.customBox.put('custom_food_1', {'id': 'cf-1', 'name': 'Poha'});
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), hasLength(1));
    expect(h.server.writesTo('user_custom_foods'), hasLength(1));

    // Second pass: both unchanged -> both skip.
    h.server.clear();
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), isEmpty);
    expect(h.server.writesTo('user_custom_foods'), isEmpty);

    // Edit only the food -> only the food re-pushes.
    await HiveService.instance.customBox
        .put('custom_food_1', {'id': 'cf-1', 'name': 'Poha', 'calories_per_100g': 130});
    h.server.clear();
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), isEmpty);
    expect(h.server.writesTo('user_custom_foods'), hasLength(1));
  });

  test('a leftover legacy custom_exercises/custom_foods list key is ignored — '
      'no writer ever populates it, and the retired read path (D18) must not '
      'crash or push it', () async {
    h.server.clear(); // see the previous test's comment -- shared server.
    await HiveService.instance.customBox.put('custom_exercises', [
      {'id': 'legacy-1', 'name': 'Old Shape Exercise', 'logging_type': 'weight_reps'}
    ]);
    await HiveService.instance.customBox.put('custom_foods', [
      {'id': 'legacy-2', 'name': 'Old Shape Food'}
    ]);
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), isEmpty);
    expect(h.server.writesTo('user_custom_foods'), isEmpty);
  });
}
