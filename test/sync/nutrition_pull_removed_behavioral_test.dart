// OI-348 walk B1 hotfix (Landing 1a-i, diagnose b1d2a8).
//
// Before: `pullRecentCrossChannelLogs` ran a nutrition leg
// (`SyncService._pullNutritionLogs`) that wrote every cloud `nutrition_logs`
// row of the last 24 h under its CLOUD UUID, with totals and no items, next to
// this device's own `nlog_` row for the same meal; every whole-box reader
// counted both. After: the leg is off (switch `restore_nutrition_launch_pull`
// runs it again) and the copies already written are removed once per user.
//
// Driven through `pullRecentCrossChannelLogsForUser` because the stub harness
// has no auth session (the public method returns before doing anything).
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import 'sync_domain_skip_harness.dart';

const _cloudId = '0b6f0a52-1c2d-4e3f-8a9b-0c1d2e3f4a5b';
const _date = '2026-11-22';

Map<String, dynamic> _nlogLunch() => {
      'id': 'nlog_${_date}_lunch_0a1b2c3d',
      'log_key': 'nlog_${_date}_lunch_0a1b2c3d',
      'date': _date,
      'meal_type': 'lunch',
      'total_calories': 95,
      'total_protein': 0,
      'total_carbs': 25,
      'total_fat': 0,
      'total_fiber': 4,
      'items': [
        {'name': 'Apple', 'quantity_g': 180.0, 'calories': 95.0},
      ],
      'source': 'manual',
      'created_at': '2026-11-22T07:00:00.000Z',
      'logged_at': '2026-11-22T07:00:00.000Z',
    };

/// The exact shape the removed leg wrote: the cloud row's columns plus the
/// `source` it stamped (the cloud table has no `source` column).
Map<String, dynamic> _pullCopy({String id = _cloudId}) => {
      'id': id,
      'user_id': kTestUserId,
      'date': _date,
      'meal_type': 'lunch',
      'total_calories': 95,
      'total_protein': 0,
      'total_carbs': 25,
      'total_fat': 0,
      'total_fiber': 4,
      'created_at': '2026-11-22T07:00:01.000+00:00',
      'source': 'telegram_label_stand_in',
    };

Map<String, dynamic> _cloudRow() => {
      'id': _cloudId,
      'user_id': kTestUserId,
      'date': _date,
      'meal_type': 'lunch',
      'total_calories': 95,
      'total_protein': 0,
      'total_carbs': 25,
      'total_fat': 0,
      'total_fiber': 4,
      'created_at': '2026-11-22T07:00:01.000+00:00',
    };

int _dayCalories() {
  var sum = 0;
  for (final v in HiveService.instance.nutritionBox.values) {
    if (v is Map && v['date'] == _date && v['meal_type'] != null) {
      sum += (v['total_calories'] as num? ?? 0).round();
    }
  }
  return sum;
}

void main() {
  final h = SyncHarness();
  final events = <String>[];
  var invalidations = 0;

  setUp(() async {
    await h.setUp();
    h.server.clear();
    h.server.writeResponders.clear();
    h.server.pagedTables.clear();
    events.clear();
    invalidations = 0;
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) =>
        events.add('$op ${message ?? ''}');
    NutritionWriteService.onStateChanged = () => invalidations++;
    SyncServiceNutrition.debugFailPullCopyCleanup = false;
    SyncServiceNutrition.debugFailPullCopyDelete = false;
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    NutritionWriteService.onStateChanged = null;
    SyncServiceNutrition.debugFailPullCopyCleanup = false;
    SyncServiceNutrition.debugFailPullCopyDelete = false;
    await HiveService.instance.syncBox
        .delete(nutritionPullCopyCleanFlagKey(kTestUserId));
    await h.tearDown();
  });

  Future<void> pull() => SyncService.instance
      .pullRecentCrossChannelLogsForUser(kTestUserId)
      .timeout(const Duration(minutes: 2));
  bool flagged() =>
      HiveService.instance.syncBox
          .get(nutritionPullCopyCleanFlagKey(kTestUserId)) ==
      true;

  group('the nutrition leg is off', () {
    test('a cloud row for a meal this device holds adds no second row', () async {
      final box = HiveService.instance.nutritionBox;
      await box.put(_nlogLunch()['id'] as String, _nlogLunch());
      h.server.pagedTables['nutrition_logs'] = [_cloudRow()];
      await pull();
      expect(box.containsKey(_cloudId), isFalse,
          reason: 'the leg must not write the cloud copy any more');
      expect(_dayCalories(), 95, reason: 'the meal is counted once');
      expect(
          h.server.requests
              .where((r) => r.table == 'nutrition_logs')
              .isEmpty,
          isTrue,
          reason: 'the leg does not even read the table');
    });

    test('the switch runs the old leg again (old path reachable)', () async {
      final box = HiveService.instance.nutritionBox;
      await HiveService.instance.configBox
          .put(kRestoreNutritionLaunchPullKey, true);
      try {
        // Cleanup already ran for this user, so the copy written by the old
        // leg is not removed in the same pass.
        await HiveService.instance.syncBox
            .put(nutritionPullCopyCleanFlagKey(kTestUserId), true);
        await box.put(_nlogLunch()['id'] as String, _nlogLunch());
        h.server.pagedTables['nutrition_logs'] = [_cloudRow()];
        await pull();
        expect(box.containsKey(_cloudId), isTrue);
        expect(_dayCalories(), 190, reason: 'the old doubling, by design');
      } finally {
        await HiveService.instance.configBox
            .delete(kRestoreNutritionLaunchPullKey);
      }
    });
  });

  group('isNutritionPullCopy (the pure rule)', () {
    test('matches only the shape the removed leg wrote', () {
      expect(isNutritionPullCopy(_cloudId, _pullCopy()), isTrue);
      expect(isNutritionPullCopy(_nlogLunch()['id'], _nlogLunch()), isFalse);
      expect(isNutritionPullCopy(_cloudId, {..._pullCopy(), 'items': []}),
          isFalse,
          reason: 'a row with items is a real meal');
      expect(
          isNutritionPullCopy(
              _cloudId, {..._pullCopy(), 'is_saved_meal': true}),
          isFalse);
      expect(
          isNutritionPullCopy(
              _cloudId, {..._pullCopy(), 'source': 'cloud_restore'}),
          isFalse,
          reason: 'a pre-Test-#12.8 restore row is not a pull copy');
      expect(
          isNutritionPullCopy(_cloudId, Map.of(_pullCopy())..remove('user_id')),
          isFalse);
      expect(
          isNutritionPullCopy(_cloudId, Map.of(_pullCopy())..remove('date')),
          isFalse);
      expect(isNutritionPullCopy('saved_meal_abc', _pullCopy()), isFalse);
      expect(isNutritionPullCopy(_cloudId, ['not', 'a', 'map']), isFalse);
    });
  });

  group('the one-time removal of the copies', () {
    test('removes the copy beside the real row; keeps every other row',
        () async {
      final box = HiveService.instance.nutritionBox;
      const savedId = '1b6f0a52-1c2d-4e3f-8a9b-0c1d2e3f4a5b';
      const withItemsId = '2b6f0a52-1c2d-4e3f-8a9b-0c1d2e3f4a5b';
      const restoredId = '3b6f0a52-1c2d-4e3f-8a9b-0c1d2e3f4a5b';
      await box.put(_nlogLunch()['id'] as String, _nlogLunch());
      await box.put(_cloudId, _pullCopy());
      await box.put('saved_meal_0a1b2c3d', {
        'id': 'saved_meal_0a1b2c3d',
        'name': 'Apple',
        'is_saved_meal': true,
      });
      await box.put(savedId, {..._pullCopy(id: savedId), 'is_saved_meal': true});
      await box.put(
          withItemsId, {..._pullCopy(id: withItemsId), 'items': const []});
      await box.put(
          restoredId, {..._pullCopy(id: restoredId), 'source': 'cloud_restore'});
      await box.put('sync_nlog_payload_hash_index', {'x': 'y'});
      // Five meal-shaped rows: the real row, the copy, and three look-alikes.
      expect(_dayCalories(), 95 * 5, reason: 'precondition');

      await pull();

      expect(box.containsKey(_cloudId), isFalse);
      expect(box.containsKey(_nlogLunch()['id']), isTrue);
      expect(box.containsKey('saved_meal_0a1b2c3d'), isTrue);
      expect(box.containsKey(savedId), isTrue);
      expect(box.containsKey(withItemsId), isTrue);
      expect(box.containsKey(restoredId), isTrue);
      expect(box.containsKey('sync_nlog_payload_hash_index'), isTrue);
      expect(flagged(), isTrue);
      expect(invalidations, 1, reason: 'the screens are told to re-read');
      expect(events.where((e) => e.startsWith('nutrition_pull_copies_removed')),
          ['nutrition_pull_copies_removed count=1']);
    });

    test('the day total equals the real row alone afterwards', () async {
      final box = HiveService.instance.nutritionBox;
      await box.put(_nlogLunch()['id'] as String, _nlogLunch());
      await box.put(_cloudId, _pullCopy());
      expect(_dayCalories(), 190);
      await pull();
      expect(_dayCalories(), 95);
    });

    test('runs once: a copy planted after the flag survives', () async {
      final box = HiveService.instance.nutritionBox;
      await pull(); // nothing to remove: the flag is still written
      expect(flagged(), isTrue);
      expect(invalidations, 0, reason: 'nothing removed, nothing to re-read');
      expect(events.where((e) => e.startsWith('nutrition_pull_copies_removed')),
          isEmpty);
      await box.put(_cloudId, _pullCopy());
      await pull();
      expect(box.containsKey(_cloudId), isTrue);
    });

    test('another account live: nothing removed, no flag', () async {
      final box = HiveService.instance.nutritionBox;
      await box.put(_cloudId, _pullCopy());
      HiveUserSession.debugCurrentUidResolverForTests =
          () => 'aaaaaaaa-0000-0000-0000-000000000000';
      try {
        await SyncService.instance
            .pullRecentCrossChannelLogsForUser(kTestUserId)
            .timeout(const Duration(minutes: 2));
      } finally {
        HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      }
      expect(box.containsKey(_cloudId), isTrue);
      expect(flagged(), isFalse);
    });

    // B-pass F1: the ONLY guard for "the live account is B but the open Hive
    // boxes still belong to A" is the Hive-owner check; ownerChangedSince
    // compares with the live account and passes here.
    test('Hive boxes owned by another account: nothing removed, no flag for the live account', () async {
      const other = 'bbbbbbbb-0000-0000-0000-000000000000';
      final box = HiveService.instance.nutritionBox;
      await box.put(_cloudId, _pullCopy());
      HiveUserSession.debugCurrentUidResolverForTests = () => other;
      try {
        await SyncService.instance
            .pullRecentCrossChannelLogsForUser(other)
            .timeout(const Duration(minutes: 2));
      } finally {
        HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      }
      expect(HiveService.instance.syncBox.get(nutritionPullCopyCleanFlagKey(other)),
          isNull,
          reason: 'the flag of an account whose box was never scanned');
      expect(box.containsKey(_cloudId), isTrue);
      expect(invalidations, 0);
    });

    // B-pass F3: a delete that throws after it started still makes the screens
    // re-read, and leaves the run-once flag unset so the next launch retries.
    test('a delete that fails part-way: screens re-read, no flag, retried next launch', () async {
      final box = HiveService.instance.nutritionBox;
      await box.put(_cloudId, _pullCopy());
      SyncServiceNutrition.debugFailPullCopyDelete = true;
      await pull();
      expect(invalidations, 1, reason: 'the screens re-read after a started delete');
      expect(flagged(), isFalse, reason: 'a failed run must not mark itself done');
      SyncServiceNutrition.debugFailPullCopyDelete = false;
      await pull();
      expect(box.containsKey(_cloudId), isFalse, reason: 'the next launch removes it');
      expect(flagged(), isTrue);
    });

    test('the kill switch keeps the copies and writes no flag', () async {
      final box = HiveService.instance.nutritionBox;
      await HiveService.instance.configBox
          .put(kDisableNutritionPullCopyCleanKey, true);
      try {
        await box.put(_cloudId, _pullCopy());
        await pull();
        expect(box.containsKey(_cloudId), isTrue);
        expect(flagged(), isFalse);
      } finally {
        await HiveService.instance.configBox
            .delete(kDisableNutritionPullCopyCleanKey);
      }
    });
  });

  group('the other legs', () {
    Map<String, dynamic> weightRow() => {
          'id': 'w-1',
          'user_id': kTestUserId,
          'date': _date,
          'weight_kg': 72.5,
          'created_at': '2026-11-22T06:00:00.000Z',
        };

    test('the weight leg still writes weight_<date>', () async {
      h.server.pagedTables['weight_logs'] = [weightRow()];
      await pull();
      final w = HiveService.instance.healthBox.get('weight_$_date');
      expect(w, isA<Map>());
      expect((w as Map)['weight_kg'], 72.5);
    });

    test('a failing cleanup never skips the weight leg', () async {
      SyncServiceNutrition.debugFailPullCopyCleanup = true;
      h.server.pagedTables['weight_logs'] = [weightRow()];
      await pull();
      expect(HiveService.instance.healthBox.get('weight_$_date'), isA<Map>());
      expect(flagged(), isFalse);
    });
  });
}
