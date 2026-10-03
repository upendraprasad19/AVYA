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

  test('user_saved_meals: push/skip/edit/retry/kill-switch contract', () async {
    var calories = 400;
    await HiveService.instance.nutritionBox.put('saved_meal_1', {
      'is_saved_meal': true,
      'name': 'Chicken Bowl',
      'items': [
        {'name': 'chicken', 'quantity_g': 200}
      ],
      'total_calories': calories,
      'total_protein': 40,
      'times_used': 0,
      'created_at': '2026-09-01T10:00:00.000Z',
    });
    await expectSkipContract(
      h: h,
      domain: SyncSkipDomain.savedMeal,
      table: 'user_saved_meals',
      seed: () async {},
      runPass: () => SyncService.instance.pushSavedMealsForSyncDomain(),
      editOne: (gen) async {
        calories = 400 + gen;
        final m = Map<String, dynamic>.from(
            HiveService.instance.nutritionBox.get('saved_meal_1') as Map);
        m['total_calories'] = calories;
        await HiveService.instance.nutritionBox.put('saved_meal_1', m);
      },
    );
  });

  test('a saved meal missing created_at omits the field rather than sending "now" '
      '(day-swapper + sync-load plan D2, closes-diagnose f4c7a9)', () async {
    // The shared SyncStubServer (sync_domain_skip_harness.dart) is
    // constructed ONCE for this whole file, not per test -- tearDown never
    // clears `requests`, so the previous test's kill-switch-phase tail
    // requests are still present here (established pattern, see
    // sync_exercise_log_payload_hash_index_writer_to_reader_test.dart).
    h.server.clear();
    await HiveService.instance.nutritionBox.put('saved_meal_legacy', {
      'is_saved_meal': true,
      'name': 'Legacy Meal',
      'items': const [],
      'total_calories': 100,
      'total_protein': 10,
      'times_used': 0,
      // no 'created_at' — simulates a pre-migration row.
    });
    await SyncService.instance.pushSavedMealsForSyncDomain();
    final row = h.server.writesTo('user_saved_meals').single.rows.single;
    expect(row.containsKey('created_at'), isFalse);
  });

  test('a null-name saved meal is skipped with telemetry, never pushed', () async {
    h.server.clear(); // see the previous test's comment -- shared server.
    await HiveService.instance.nutritionBox.put('saved_meal_blank', {
      'is_saved_meal': true,
      'name': '   ',
      'total_calories': 1,
      'total_protein': 1,
      'times_used': 0,
    });
    await SyncService.instance.pushSavedMealsForSyncDomain();
    expect(h.server.writesTo('user_saved_meals'), isEmpty);
  });
}
