// APK Test #16.1 / Agent A — behavioural test for `ExlogKeyMigrator`.
//
// Synthesise a workoutBox with mixed-shape legacy keys:
//   1. Canonical `exlog_<istDate>_<v5Prefix>` (already correct)
//   2. Rogue A   `exlog_<date>_<name.hashCode>` (sync rogue)
//   3. Rogue B   `exlog_<ms>_<name.hashCode>` (logSetWithPrRescan rogue)
//
// After `ExlogKeyMigrator.runIfNeeded()`:
//   - Every surviving key matches the canonical
//     `WorkoutWriteService.exlogKey(date, name)` output.
//   - Rows for the same (date, name) are MERGED — sets[] concatenated,
//     aggregates recomputed.
//   - The `exercise_log_index_<date>` list contains exactly the new key.
//   - Migration flag `exlog_key_migration_v8` set to true.
//
// Also pins idempotency: calling `runIfNeeded()` twice is a no-op the
// second time.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_exlog_migrator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.workoutBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();

    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  test('migrator consolidates mixed-shape exlog keys to canonical', () async {
    final wb = HiveService.instance.workoutBox;
    final date = DateTime.utc(2026, 5, 14, 7, 0); // IST 12:30 May 14
    const dateStr = '2026-05-14';
    const name = 'Bench Press';

    final canonicalKey = WorkoutWriteService.exlogKey(date, name);

    // Shape 1 — canonical key (1 set: 80kg × 10)
    await wb.put(canonicalKey, {
      'exercise_name': name,
      'date': dateStr,
      'sets': [
        {'weight_kg': 80.0, 'reps': 10},
      ],
      'updated_at_ms': 100,
    });

    // Shape 2 — rogue sync key (hashCode based)
    final rogueA = 'exlog_${dateStr}_${name.toLowerCase().trim().hashCode}';
    await wb.put(rogueA, {
      'exercise_name': name,
      'date': dateStr,
      'sets': [
        {'weight_kg': 85.0, 'reps': 8},
      ],
      'updated_at_ms': 200,
    });

    // Shape 3 — rogue PR-rescan key (ms+hashCode)
    final rogueB = 'exlog_1747100000000_${name.hashCode}';
    await wb.put(rogueB, {
      'exercise_name': name,
      'date': dateStr,
      'sets': [
        {'weight_kg': 90.0, 'reps': 6},
      ],
      'updated_at_ms': 300,
    });

    // Stale index pointing at all 3 keys
    await wb.put(
      'exercise_log_index_$dateStr',
      [canonicalKey, rogueA, rogueB],
    );

    await ExlogKeyMigrator.runIfNeeded();

    // After migration — only one exlog key for (May 14, Bench Press).
    final exlogKeys =
        wb.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1,
        reason: 'rogue keys must be merged into canonical key');
    expect(exlogKeys.single, canonicalKey);

    // Merged sets — 3 entries, ordered by updated_at_ms.
    final merged = wb.get(canonicalKey) as Map;
    final sets = (merged['sets'] as List).cast<Map>();
    expect(sets.length, 3, reason: 'all 3 sets merged');
    expect(sets.map((s) => s['weight_kg']).toList(), [80.0, 85.0, 90.0]);

    // Aggregates recomputed.
    expect(merged['set_number'], 3);
    expect(merged['reps_completed'], 24); // 10 + 8 + 6
    expect(merged['weight_kg'], 90.0); // max
    expect(merged['volume_kg'], 80 * 10 + 85 * 8 + 90 * 6);

    // Index rebuilt — single canonical key, no stale rogue refs.
    final idx = wb.get('exercise_log_index_$dateStr');
    expect(idx, isA<List>());
    expect((idx as List).cast<String>(), [canonicalKey]);

    // Migration flag set.
    final config = HiveService.instance.configBox;
    expect(config.get('exlog_key_migration_v8'), true);
  });

  test('migrator is idempotent — second call is a no-op', () async {
    final wb = HiveService.instance.workoutBox;
    final date = DateTime.utc(2026, 5, 14);
    const dateStr = '2026-05-14';
    final canonicalKey =
        WorkoutWriteService.exlogKey(date, 'Squat');

    await wb.put(canonicalKey, {
      'exercise_name': 'Squat',
      'date': dateStr,
      'sets': [
        {'weight_kg': 100.0, 'reps': 5},
      ],
      'updated_at_ms': 1,
    });

    await ExlogKeyMigrator.runIfNeeded();
    final afterFirst = wb.get(canonicalKey);

    await ExlogKeyMigrator.runIfNeeded();
    final afterSecond = wb.get(canonicalKey);

    expect(afterSecond, equals(afterFirst),
        reason: 'second migration must be a no-op (gated by config flag)');
  });

  test('legacy entry without sets[] synthesises a single set on merge',
      () async {
    // Older `exlog_*` rows pre-Test-#6 had only top-level weight_kg +
    // reps_completed, no `sets[]` array. Migrator must synthesise a
    // single ExerciseSet so the canonical row carries the data forward.
    final wb = HiveService.instance.workoutBox;
    final date = DateTime.utc(2026, 5, 14);
    const dateStr = '2026-05-14';

    final rogue = 'exlog_${dateStr}_${'Deadlift'.hashCode}';
    await wb.put(rogue, {
      'exercise_name': 'Deadlift',
      'date': dateStr,
      'weight_kg': 150.0,
      'reps_completed': 5,
      'updated_at_ms': 1000,
    });

    await ExlogKeyMigrator.runIfNeeded();

    final canonicalKey =
        WorkoutWriteService.exlogKey(date, 'Deadlift');
    final merged = wb.get(canonicalKey) as Map;
    final sets = (merged['sets'] as List).cast<Map>();
    expect(sets.length, 1);
    expect(sets.single['weight_kg'], 150.0);
    expect(sets.single['reps'], 5);
  });
}
