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

  test('a confirmed custom-exercise push is recorded under '
      'sync_custom_item_payload_hash_index in customBox as "exercise:<id>", and '
      'the SAME function reads it back to skip', () async {
    await HiveService.instance.customBox
        .put('custom_exercise_9', {'id': 'ce-9', 'name': 'Pistol Squat', 'logging_type': 'bodyweight_reps'});
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(
      SyncSkipIndex.readIndex(
          HiveService.instance.customBox, SyncSkipDomain.customItem.indexKey),
      contains('exercise:ce-9'),
    );
    h.server.clear();
    await SyncService.instance.pushCustomItemsForSyncDomain();
    expect(h.server.writesTo('user_custom_exercises'), isEmpty);
  });
}
