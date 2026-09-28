@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

/// Every log-client-error request carrying [opType]. `_reportSyncFailure`
/// fires `unawaited`, so its POST can land a tick or two after the push
/// call returns -- poll for it rather than checking synchronously. Same
/// shape as the *_payload_hash_index_writer_to_reader_test.dart siblings'
/// helper (fix round 2, F3): counts to [atLeast], bounded by a generous
/// deadline so a genuinely slow (not missing) report is still caught, THEN a
/// short settle so a SURPLUS (a flood -- e.g. a broken per-opType dedup that
/// reports every failure instead of one per opType) is also visible before
/// the caller counts, exactly the workout-template sibling's 150ms
/// flood-settle. Without the settle, a hasLength(2) assertion could pass on
/// a mutant that reports 4 times, if the poll happens to return right after
/// the 2nd of 4 arrives.
Future<List<dynamic>> _logClientErrorReports(SyncHarness h, String opType,
    {int atLeast = 1, int maxWaitMs = 10000}) async {
  List<dynamic> matches() => h.server.requests
      .where((r) =>
          r.path == '/functions/v1/log-client-error' &&
          r.body is Map &&
          (r.body as Map)['op_type'] == opType)
      .toList();
  final deadline = DateTime.now().add(Duration(milliseconds: maxWaitMs));
  while (matches().length < atLeast && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
  await Future.delayed(const Duration(milliseconds: 150));
  return matches();
}

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

  test('a same-valued id shared by an exercise and a food does not collide in '
      'the shared index (the exercise:/food: prefix disambiguates)', () async {
    h.server.clear(); // see the earlier test's comment -- shared server.
    // Both entities deliberately share the SAME raw id: without the
    // exercise:/food: type prefix on the row key, `_stored['shared-1']`
    // would be one index slot shared by both, so whichever push landed
    // SECOND would overwrite the other's fingerprint and the first would
    // never be able to skip on an unchanged pass.
    await HiveService.instance.customBox.put('custom_exercise_2',
        {'id': 'shared-1', 'name': 'Pull Up', 'logging_type': 'weight_reps'});
    await HiveService.instance.customBox
        .put('custom_food_2', {'id': 'shared-1', 'name': 'Rajma'});
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), hasLength(1));
    expect(h.server.writesTo('user_custom_foods'), hasLength(1));

    // Both unchanged -> both must still skip, even though their raw ids
    // collide -- proves the row key carries the type prefix, not just id.
    h.server.clear();
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), isEmpty,
        reason: 'the exercise must skip on its own recorded fingerprint, '
            'not be shadowed by the food sharing its raw id');
    expect(h.server.writesTo('user_custom_foods'), isEmpty);
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

  test('a forced exercise-upsert failure reports upsert_custom_exercise and a '
      'forced food-upsert failure reports upsert_custom_food -- neither '
      'collapses onto the shared domain catch-all sync_custom_items (F1)',
      () async {
    h.server.clear(); // see the earlier tests' comment -- shared server.
    await HiveService.instance.customBox.put('custom_exercise_1',
        {'id': 'ce-1', 'name': 'L Sit', 'logging_type': 'timed'});
    h.server.failWritesTo.add('user_custom_exercises');
    await SyncService.instance.pushCustomItemsForSyncDomain();
    h.server.failWritesTo.remove('user_custom_exercises');

    final exerciseReports =
        await _logClientErrorReports(h, 'upsert_custom_exercise');
    expect(exerciseReports, isNotEmpty,
        reason: 'the exercise-upsert failure must report under its own '
            'opType (${exerciseReports.length} arrived)');
    expect(
        await _logClientErrorReports(h, 'sync_custom_items', maxWaitMs: 300),
        isEmpty,
        reason: 'must not also collapse onto the whole-function catch-all '
            'opType');

    h.server.clear();
    await HiveService.instance.customBox
        .put('custom_food_1', {'id': 'cf-1', 'name': 'Poha'});
    h.server.failWritesTo.add('user_custom_foods');
    await SyncService.instance.pushCustomItemsForSyncDomain();
    h.server.failWritesTo.remove('user_custom_foods');

    final foodReports = await _logClientErrorReports(h, 'upsert_custom_food');
    expect(foodReports, isNotEmpty,
        reason: 'the food-upsert failure must report under its own opType '
            '(${foodReports.length} arrived)');
    expect(
        await _logClientErrorReports(h, 'sync_custom_items', maxWaitMs: 300),
        isEmpty,
        reason: 'must not also collapse onto the whole-function catch-all '
            'opType');
    expect(
        await _logClientErrorReports(h, 'upsert_custom_exercise',
            maxWaitMs: 300),
        isEmpty,
        reason: 'the food failure must not report under the exercise opType '
            'either -- the two tables must stay distinguishable');
  });

  test(
      'BOTH the exercise upsert and the food upsert fail in ONE pass -- both '
      'opTypes are reported exactly once each, and the shared catch-all '
      'sync_custom_items is never reported by the per-row path (mirror gap '
      'fix, F1 round 2)', () async {
    // _syncCustomItems() builds exactly ONE SyncSkipIndex for the whole
    // customBox loop (see lib/core/services/sync/sync_community.dart), so
    // seeding one exercise row + one food row and failing BOTH tables makes
    // both failures land inside the SAME pass / SAME index instance -- the
    // exact shape `if (failed == 1)` collapsed onto only the FIRST failure
    // overall, silencing the second table's report entirely.
    h.server.clear(); // see the earlier tests' comment -- shared server.
    await HiveService.instance.customBox.put('custom_exercise_1',
        {'id': 'ce-1', 'name': 'L Sit', 'logging_type': 'timed'});
    await HiveService.instance.customBox
        .put('custom_food_1', {'id': 'cf-1', 'name': 'Poha'});
    h.server.failWritesTo.addAll(['user_custom_exercises', 'user_custom_foods']);
    await SyncService.instance.pushCustomItemsForSyncDomain();
    h.server.failWritesTo
        .removeAll(['user_custom_exercises', 'user_custom_foods']);

    // One logical report is ONE request since main's B2a-2b dual-write fix
    // (merged 2026-09-28): `_reportSyncFailure`'s internal recordNonFatal
    // passes skipServerPost:true, so only its own direct invoke reaches
    // log-client-error. Before that fix it was 2 requests.
    final exerciseReports =
        await _logClientErrorReports(h, 'upsert_custom_exercise');
    expect(exerciseReports, hasLength(1),
        reason: 'the exercise failure must be reported exactly once '
            '(one request), even though the food failure in '
            'the SAME pass is the second failure overall '
            '(${exerciseReports.length} arrived)');

    final foodReports =
        await _logClientErrorReports(h, 'upsert_custom_food');
    expect(foodReports, hasLength(1),
        reason: 'the food failure must ALSO be reported exactly once '
            '(one request) -- the mirror gap: `if (failed == 1)` '
            'would silence this because it is the second failure of the '
            'pass, not the first (${foodReports.length} arrived)');

    expect(
        await _logClientErrorReports(h, 'sync_custom_items', maxWaitMs: 300),
        isEmpty,
        reason: 'neither per-row failure may collapse onto the shared '
            'domain catch-all opType');
  });

  test(
      'the mirror for single-opType throttling: TWO exercise rows fail in '
      'one pass -- upsert_custom_exercise is still reported exactly ONCE '
      '(the per-opType dedup must not turn into "report every failure")',
      () async {
    h.server.clear(); // see the earlier tests' comment -- shared server.
    await HiveService.instance.customBox.put('custom_exercise_1',
        {'id': 'ce-1', 'name': 'L Sit', 'logging_type': 'timed'});
    await HiveService.instance.customBox.put('custom_exercise_2',
        {'id': 'ce-2', 'name': 'Pull Up', 'logging_type': 'weight_reps'});
    h.server.failWritesTo.add('user_custom_exercises');
    await SyncService.instance.pushCustomItemsForSyncDomain();
    h.server.failWritesTo.remove('user_custom_exercises');

    final exerciseReports =
        await _logClientErrorReports(h, 'upsert_custom_exercise');
    expect(exerciseReports, hasLength(1),
        reason: 'two failures sharing the SAME opType in one pass must still '
            'collapse to exactly one report (one request) -- '
            'the throttle still holds per opType '
            '(${exerciseReports.length} arrived)');

    expect(
        await _logClientErrorReports(h, 'sync_custom_items', maxWaitMs: 300),
        isEmpty,
        reason: 'must not also collapse onto the whole-function catch-all '
            'opType');
  });
}
