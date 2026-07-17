// Behavioral regression — ⑥ Batch 6 (W2.3): readiness check-in → deterministic
// Green/Yellow/Red → a Red-day isolation SET-DROP (the 0-set floor is automatic).
// Behind `enable_readiness` (default OFF, ship dark). `readinessLevel` lives on
// `ActiveWorkoutData` (session-only) + MUST survive `copyWith` (the ⑦b F1 bug).
// Re-entry: `startWorkout` with no param re-applies today's STORED check-in
// (never re-prompt / re-derive). The LOAD cut is 6-B (`exercise_card.dart`, NOT
// here — `ExerciseData.weight` is dead `'0kg'`, ignored for history users).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('readinessLevelFor — deterministic flag count', () {
    test('0 flags → green', () {
      expect(readinessLevelFor(sleep: 0, soreness: 0, energy: 0),
          ReadinessLevel.green);
      expect(readinessLevelFor(sleep: 1, soreness: 1, energy: 1),
          ReadinessLevel.green);
    });
    test('1-2 flags → yellow', () {
      expect(readinessLevelFor(sleep: 2, soreness: 0, energy: 0),
          ReadinessLevel.yellow);
      expect(readinessLevelFor(sleep: 2, soreness: 2, energy: 1),
          ReadinessLevel.yellow);
    });
    test('3 flags → red', () {
      expect(readinessLevelFor(sleep: 2, soreness: 2, energy: 2),
          ReadinessLevel.red);
    });
    test('ReadinessCheckin.fromMap coerces (String→int) + clamps [0,2]', () {
      final c = ReadinessCheckin.fromMap(
          {'sleep': 2, 'soreness': '2', 'energy': 5, 'date': '2026-07-17'});
      expect(c.energy, 2); // 5 clamped to 2
      expect(c.level, ReadinessLevel.red);
    });
  });

  group('ActiveWorkoutData.copyWith — readinessLevel F1 survival', () {
    test('default readinessLevel is null', () {
      expect(const ActiveWorkoutData().readinessLevel, isNull);
    });
    test('readinessLevel SURVIVES the timer copyWith(elapsedSeconds:) — F1 bug',
        () {
      const data = ActiveWorkoutData(readinessLevel: ReadinessLevel.red);
      expect(data.copyWith(elapsedSeconds: 5).readinessLevel, ReadinessLevel.red);
    });
  });

  group('startWorkout — Red set-drop, flag-gated + re-entry (integration)', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final fixedNow = DateTime(2026, 7, 17, 12, 0);
    late Directory tempDir;
    late ProviderContainer container;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_readiness');
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
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        'userBox_aaaaaaaa',
        'workoutBox_aaaaaaaa',
        'nutritionBox_aaaaaaaa',
        'healthBox_aaaaaaaa',
        'coachBox_aaaaaaaa',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
      setTestClockTo(fixedNow);
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose(); // cancels the notifier timer
      resetTestClock();
      await HiveUserSession.closeAll();
    });

    // One isolation exercise (3 sets) + one compound (4 sets).
    const day = WorkoutDayData(dayNumber: 1, name: 'Push', exercises: [
      ExerciseData(name: 'Cable Fly', sets: '3', exerciseType: 'isolation'),
      ExerciseData(name: 'Bench Press', sets: '4', exerciseType: 'compound'),
    ]);

    Future<void> enableReadiness() async =>
        HiveService.instance.configBox.put('enable_readiness', true);

    Future<void> seedReadiness(String level) async {
      await HiveService.instance.healthBox.put(
        'readiness_${istDateStr(fixedNow)}',
        {
          'date': istDateStr(fixedNow),
          'sleep': 2,
          'soreness': 2,
          'energy': 2,
          'level': level,
        },
      );
    }

    List<ExerciseData> startAndGet({ReadinessLevel? readiness}) {
      container
          .read(activeWorkoutProvider.notifier)
          .startWorkout(day, readiness: readiness);
      return container.read(activeWorkoutProvider).exercises;
    }

    String setsOf(List<ExerciseData> ex, String name) =>
        ex.firstWhere((e) => e.name == name).sets;

    test('flag ON + Red (passed) → drops 1 isolation set; compound untouched',
        () async {
      await enableReadiness();
      final ex = startAndGet(readiness: ReadinessLevel.red);
      expect(setsOf(ex, 'Cable Fly'), '2'); // 3 → 2 (isolation)
      expect(setsOf(ex, 'Bench Press'), '4'); // compound unchanged
      expect(container.read(activeWorkoutProvider).readinessLevel,
          ReadinessLevel.red);
      // The 1×/sec timer copyWith(elapsedSeconds:) must not revert the level (F1).
      container.read(activeWorkoutProvider.notifier).setElapsedSeconds(10);
      expect(container.read(activeWorkoutProvider).readinessLevel,
          ReadinessLevel.red);
    });

    test('flag ON + Red STORED (re-entry, NO param) → same drop', () async {
      await enableReadiness();
      await seedReadiness('red');
      final ex = startAndGet(); // no param → re-applies the stored check-in
      expect(setsOf(ex, 'Cable Fly'), '2');
    });

    test('flag ON + Green → no drop', () async {
      await enableReadiness();
      final ex = startAndGet(readiness: ReadinessLevel.green);
      expect(setsOf(ex, 'Cable Fly'), '3');
    });

    test('flag OFF (default) + Red stored → NO drop (byte-identical), no level',
        () async {
      await seedReadiness('red'); // present, but flag off → never read
      final ex = startAndGet();
      expect(setsOf(ex, 'Cable Fly'), '3');
      expect(container.read(activeWorkoutProvider).readinessLevel, isNull);
    });
  });
}
