// APK Test #12.1 — pins the writer-side normalization for legacy
// edit-sheet field names.
//
// Bug class: founder reported 2026-05-06 that the receipt rendered
// "0 sets · 26 reps · 85 kg" for an edited workout log. Root cause:
// `EditWorkoutLogSheet._save` writes `sets_completed` (legacy field)
// but the canonical readers (Train expanded view + Receipt) prefer
// `set_number` (new field, post-Test #6 WorkoutWriteService). When a
// user completed a workout without checking sets (set_number=0) and
// then edited via the sheet to add weight+reps, the merge produced
// `set_number=0, sets_completed=N` — readers reported 0 sets.
//
// Fix: `WorkoutWriteService.editLog` now normalizes legacy field names
// to canonical names BEFORE merging:
//   sets_completed → set_number
//   sets_detail    → sets (with `duration_seconds` → `duration_sec`)
//
// This pins the contract so EditWorkoutLogSheet can keep writing
// legacy names AND the readers see canonical data — single source
// of truth at the WriteService layer.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_edit_log_norm');
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

  group('editLog normalizes legacy field names (APK Test #12.1)', () {
    test('sets_completed → set_number when set_number missing or zero',
        () async {
      final wb = HiveService.instance.workoutBox;
      // Seed an exlog row as if the active workout completed with NO
      // checked sets — set_number=0, no per-set sets[] array.
      const key = 'exlog_2026-05-06_-1234';
      const dateStr = '2026-05-06';
      await wb.put(key, {
        'exercise_name': 'Bench Press',
        'date': dateStr,
        'set_number': 0,
        'reps_completed': 0,
        'weight_kg': 0.0,
        'logging_type': 'weight_reps',
      });

      // EditSheet writes legacy field names only.
      final result = await WorkoutWriteService.instance.editLog(
        logKey: key,
        updates: {
          'sets_completed': 3,
          'reps_completed': 26,
          'weight_kg': 85.0,
        },
        source: WriteSource.editSheet,
      );

      expect(result.success, isTrue);

      final updated = wb.get(key) as Map;
      expect(updated['set_number'], 3,
          reason: 'sets_completed must be promoted to set_number');
      expect(updated['sets_completed'], 3);
      expect(updated['reps_completed'], 26);
      expect(updated['weight_kg'], 85.0);
    });

    test('explicit set_number wins over sets_completed when caller sends both',
        () async {
      final wb = HiveService.instance.workoutBox;
      const key = 'exlog_2026-05-06_-9999';
      const dateStr = '2026-05-06';
      await wb.put(key, {
        'exercise_name': 'Squat',
        'date': dateStr,
        'set_number': 5,
        'logging_type': 'weight_reps',
      });

      // Caller sends BOTH — explicit set_number must take precedence.
      final result = await WorkoutWriteService.instance.editLog(
        logKey: key,
        updates: {
          'set_number': 4,
          'sets_completed': 99, // garbage; should be ignored as source
        },
        source: WriteSource.editSheet,
      );
      expect(result.success, isTrue);
      final updated = wb.get(key) as Map;
      expect(updated['set_number'], 4);
    });

    test('sets_detail → sets (with duration_seconds → duration_sec)',
        () async {
      final wb = HiveService.instance.workoutBox;
      const key = 'exlog_2026-05-06_-5555';
      const dateStr = '2026-05-06';
      await wb.put(key, {
        'exercise_name': 'Plank',
        'date': dateStr,
        'set_number': 0,
        'logging_type': 'timed',
      });

      final result = await WorkoutWriteService.instance.editLog(
        logKey: key,
        updates: {
          'sets_detail': [
            {'set_number': 1, 'duration_seconds': 60},
            {'set_number': 2, 'duration_seconds': 75},
            {'set_number': 3, 'duration_seconds': 90},
          ],
        },
        source: WriteSource.editSheet,
      );
      expect(result.success, isTrue);

      final updated = wb.get(key) as Map;
      // sets[] populated from sets_detail with field-name translation.
      final sets = updated['sets'];
      expect(sets, isA<List>());
      expect((sets as List).length, 3);
      // editLog auto-recomputes set_number from sets[].length.
      expect(updated['set_number'], 3);
      // Each set carries duration_sec (canonical), not duration_seconds.
      expect((sets[0] as Map)['duration_sec'], 60);
      expect((sets[2] as Map)['duration_sec'], 90);
    });
  });
}
