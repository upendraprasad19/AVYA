// Behavioral — ⑥ Batch 7-A (W3.2 phase arc): `currentWaveCharacters()` reads the
// materialized `current_plan` blob's `week_plans[].week_character` (snake_case per
// WeekPlan.toMap), crash-safe on absent/malformed blobs. `phaseArcProvider` is
// flag-gated (`enable_phase_arc`, ship-dark DEFAULT OFF) → null when OFF / no plan.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_phase_arc');
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
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  Future<void> seedPlan(List<String> waves) async {
    await HiveService.instance.workoutBox.put('current_plan', {
      'week_plans': [
        for (final w in waves) {'week_character': w},
      ],
    });
  }

  group('currentWaveCharacters — reads week_character from the blob', () {
    test('4-week wave → [baseline, overreach, peak, deload]', () async {
      await seedPlan(['baseline', 'overreach', 'peak', 'deload']);
      expect(WorkoutScheduleService.instance.currentWaveCharacters(),
          ['baseline', 'overreach', 'peak', 'deload']);
    });
    test('no plan → const []', () async {
      expect(WorkoutScheduleService.instance.currentWaveCharacters(), isEmpty);
    });
    test('malformed blob (week_plans not a List) → const []', () async {
      await HiveService.instance.workoutBox
          .put('current_plan', {'week_plans': 'oops'});
      expect(WorkoutScheduleService.instance.currentWaveCharacters(), isEmpty);
    });
    test('non-Map blob → const []', () async {
      await HiveService.instance.workoutBox.put('current_plan', 'garbage');
      expect(WorkoutScheduleService.instance.currentWaveCharacters(), isEmpty);
    });
    test('week entry missing week_character → empty-string slot (no crash)',
        () async {
      await HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          {'week_character': 'baseline'},
          {'foo': 'bar'},
        ],
      });
      expect(WorkoutScheduleService.instance.currentWaveCharacters(),
          ['baseline', '']);
    });
  });

  group('phaseArcProvider — flag-gated (ship-dark OFF)', () {
    test('flag OFF (default) → null even with a plan', () async {
      await seedPlan(['baseline', 'overreach', 'peak', 'deload']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseArcProvider), isNull);
    });
    test('flag ON + plan → PhaseArcData (waves + current week 1-4)', () async {
      await HiveService.instance.configBox.put('enable_phase_arc', true);
      await seedPlan(['baseline', 'overreach', 'peak', 'deload']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final arc = c.read(phaseArcProvider);
      expect(arc, isNotNull);
      expect(arc!.waves, ['baseline', 'overreach', 'peak', 'deload']);
      expect(arc.currentWeek, inInclusiveRange(1, 4));
    });
    test('flag ON but no plan → null (degenerate guard)', () async {
      await HiveService.instance.configBox.put('enable_phase_arc', true);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseArcProvider), isNull);
    });
  });
}
