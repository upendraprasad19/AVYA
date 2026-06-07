// test/contracts/restore_local_wins_additive_test.dart
//
// Slow-boot guard (4e8b1d): returning users now reach /home WHILE the cloud
// restore runs in the background, making the restore concurrent with the user
// logging. Two properties keep that safe:
//
//   (a) LOCAL-WINS / ADDITIVE restore — the restore never overwrites a local
//       row that already exists (it may hold sets/meals the user just logged
//       and not yet synced; a network blip would make that a TRUE loss). The
//       restore only fills gaps. Mirrors the weight-restore pattern
//       (sync_health.dart:300) and the existing _restoreScheduledWorkouts merge.
//
//   (b) The exlog index append (addToExlogIndex) is an add-only UNION, and the
//       post-restore heal (reconcileExlogIndexes) rebuilds the index from the
//       rows actually present — so a returning user's index never loses a key.
//
// NOTE: an earlier draft tried to prove an index read-modify-write "race". A
// control (25 concurrent UNLOCKED appends → all 25 survived) REFUTED it: Hive
// commits the value in-memory before it yields for the disk flush, so the
// read→put has no gap on the single isolate. The real loss vector the bg-flip
// introduces is the unconditional row OVERWRITE — fixed by (a).
//
// closes-diagnose: e4a8b1
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import '_sync_service_source.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('exlog index — add-only union + reconcile (behavioral)', () {
    late Directory tempDir;
    late Box box;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exlog_index');
      Hive.init(tempDir.path);
      box = await Hive.openBox('idx_workout');
    });

    tearDown(() async {
      await box.close();
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('addToExlogIndex is an add-only union — concurrent + repeated appends '
        'lose nothing and never duplicate', () async {
      const dateStr = '2026-06-02';
      final keys = List.generate(25, (i) => 'exlog_${dateStr}_k$i');
      await Future.wait([
        for (final k in keys)
          WorkoutWriteService.instance.addToExlogIndex(box, dateStr, k)
      ]);
      // Re-append every key — must be idempotent.
      for (final k in keys) {
        await WorkoutWriteService.instance.addToExlogIndex(box, dateStr, k);
      }
      final stored =
          (box.get('exercise_log_index_$dateStr') as List).cast<String>();
      expect(stored.toSet(), keys.toSet(), reason: 'every key present');
      expect(stored.length, keys.length, reason: 'no duplicates');
    });

    test('reconcileExlogIndexes rebuilds a drifted index from the present rows',
        () async {
      const dateStr = '2026-06-03';
      final keys = List.generate(12, (i) => 'exlog_${dateStr}_k$i');
      for (final k in keys) {
        await box.put(k, {'id': k, 'type': 'exercise_log', 'date': dateStr});
      }
      // Index drifted — only the first key present (orphan scenario).
      await box.put('exercise_log_index_$dateStr', <String>[keys.first]);

      await WorkoutWriteService.instance.reconcileExlogIndexes(box);

      final stored =
          (box.get('exercise_log_index_$dateStr') as List).cast<String>();
      expect(stored.toSet(), keys.toSet(),
          reason: 'reconcile unions every present exlog_<date>_* key back into '
              'the index (never drops a present key)');
    });
  });

  group('restore writers are local-wins / additive (source contract)', () {
    late String src;
    setUpAll(() {
      src = _strip(loadSyncServiceSource().readAsStringSync());
    });

    test('_restoreExerciseLogs only writes the row when local is absent', () {
      expect(src.contains('Future<void> _restoreExerciseLogs('), isTrue);
      expect(src.contains('if (_hive.workoutBox.get(logId) == null)'), isTrue,
          reason: 'exlog restore must NOT overwrite a local (possibly unsynced) '
              'row — local-wins additive guard (4e8b1d)');
    });

    test('_restoreWorkoutLogs skips when a local wlog summary exists', () {
      expect(src.contains('Future<void> _restoreWorkoutLogs('), isTrue);
      expect(
          src.contains('if (_hive.workoutBox.get(logId) != null) continue;'),
          isTrue,
          reason: 'wlog restore must be additive (local-wins)');
    });

    test('_restoreNutritionLogs only writes when the local meal is absent', () {
      expect(src.contains('Future<void> _restoreNutritionLogs('), isTrue);
      expect(src.contains('if (_hive.nutritionBox.get(localKey) == null)'),
          isTrue,
          reason: 'nutrition-log restore must be additive (local-wins)');
    });

    test('_restoreSavedMeals skips when a local saved meal exists', () {
      expect(src.contains('Future<void> _restoreSavedMeals('), isTrue);
      expect(
          src.contains('if (_hive.nutritionBox.get(hiveKey) != null) continue;'),
          isTrue,
          reason: 'saved-meal restore must be additive (local-wins)');
    });
  });
}
