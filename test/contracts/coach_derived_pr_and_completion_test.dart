// Derive-only behavioral proof (2026-05-31).
//
// Two primitives the removed AI tools used to duplicate are proven to be
// DERIVED from raw logging via the canonical WorkoutWriteService:
//
//   1. PR derives from logSet — `logExercise` runs `_rescanPrFor`, and the
//      home PR snapshot (`loadAllExercisePRs`) computes the best-per-set from
//      `exlog_*`. No separate `logPR` tool is needed.
//   2. Completion derives from logging — the canonical `markCompleted` flips a
//      planned scheduled day to `completed`. The AI dispatcher now calls this
//      after a coach `logSet` (wiring pinned by
//      `derive_only_tool_surface_test.dart`); the full dispatcher-level proof
//      is the live-web E2E (the dispatcher needs a live Ref + Supabase sync).
//
// Pure Hive — no Supabase — so it runs in the pre-commit gate.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_derive_only');
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
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  group('Derive-only behavioral primitives', () {
    test('PR derives from a logged set (no logPR tool required)', () async {
      final today = DateTime.now();
      final result = await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Bench Press',
        sets: [
          ExerciseSet(
            weightKg: 100,
            reps: 5,
            loggedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
        source: WriteSource.aiCoach,
      );
      expect(result.success, isTrue);

      final prs = WorkoutRepository.instance.loadAllExercisePRs();
      final bench =
          prs.where((p) => p.exerciseName.toLowerCase() == 'bench press');
      expect(bench, isNotEmpty,
          reason: 'A logged set must surface as a PR via loadAllExercisePRs '
              '(derived) — no logPR tool needed.');
      expect(bench.first.bestValue, 100);
    });

    test('completion derives via canonical markCompleted (planned → completed)',
        () async {
      final today = DateTime.now();
      final wb = HiveService.instance.workoutBox;
      final sKey = WorkoutWriteService.scheduleKey(today);
      await wb.put(sKey, {
        'date': istDateStr(today),
        'workout_name': 'Push Day',
        'status': 'planned',
        'type': 'custom_template',
      });

      final result = await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Push Day',
        durationSec: 0,
      );
      expect(result.success, isTrue);

      final after = wb.get(sKey) as Map;
      expect(after['status'], 'completed',
          reason: 'Logging a scheduled day must derive completion through the '
              'canonical markCompleted writer (replaces markWorkoutComplete).');
    });
  });
}
