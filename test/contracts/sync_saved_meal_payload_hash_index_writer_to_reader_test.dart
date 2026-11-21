@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('a confirmed saved-meal push is recorded under '
      'sync_saved_meal_payload_hash_index in nutritionBox, keyed by name, and '
      'the SAME function reads it back to skip', () async {
    await HiveService.instance.nutritionBox.put('saved_meal_x', {
      'is_saved_meal': true,
      'name': 'Dal Rice',
      'items': const [],
      'total_calories': 300,
      'total_protein': 15,
      'times_used': 0,
      'created_at': '2026-09-01T00:00:00.000Z',
    });
    await SyncService.instance.pushSavedMealsForSyncDomain();
    expect(
      SyncSkipIndex.readIndex(
          HiveService.instance.nutritionBox, SyncSkipDomain.savedMeal.indexKey),
      contains('Dal Rice'),
    );
    h.server.clear();
    await SyncService.instance.pushSavedMealsForSyncDomain();
    expect(h.server.writesTo('user_saved_meals'), isEmpty);
  });
}
