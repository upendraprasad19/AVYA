// U2 safe-omission on the PRODUCTION runtime path (rule 21).
//
// The synthetic tracer test (injury_safe_omission_test.dart) proves the harness
// mirror; this proves the real `ExerciseSelector.pickV4` -> `_cascadeFill`
// return-null path. A Hive library is seeded so the ONLY exercises for a
// movement pattern are its three universal-pool members, all contraindicated
// for the user. attempts 1-4 (queryV4 injuryExclusions) exclude them; attempt-5
// filters the pool; with nothing safe left, the slot is SAFELY OMITTED (the
// PopulatedDay has zero exercises) — never a contraindicated pick, never a crash.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_safe_omission');
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
      HiveService.exerciseBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);

    // Seed a library where the ONLY shoulder_isolation exercises are the three
    // universal-pool members — all shoulder-contraindicated.
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    for (final n in const ['Pike Push Up', 'Arm Circles', 'Band Pull Apart']) {
      await exBox.put(n, {
        'id': n.toLowerCase().replaceAll(' ', '_'),
        'name': n,
        'movement_pattern': 'shoulder_isolation',
        'exercise_type': 'isolation',
        'target_focus': 'rear delt',
        'primary_muscles': ['rear deltoid'],
        'equipment_tier': ['full_gym'],
        'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
        'is_foundational': true,
        'default_sets': 3,
        'default_reps': '12',
        'rep_range': '10-15',
        'injury_contraindications': ['shoulder'],
      });
    }
    HiveService.instance.markInitializedForTests();
  });

  MuscleSlotDay dayWithShoulderIsoSlot() => const MuscleSlotDay(
        name: 'Shoulders',
        focus: 'Rear Delts',
        dayType: 'shoulders_arms',
        intensity: 'hypertrophy',
        slotsA: [
          MuscleSlot(
            targetMuscle: 'Rear Delts',
            movementPattern: 'shoulder_isolation',
            exerciseType: 'isolation',
            priority: 3,
          ),
        ],
      );

  test('shoulder-injured user: all-contra pool -> slot safely omitted (no pick)',
      () {
    final days = ExerciseSelector.pickV4(
      slotDays: [dayWithShoulderIsoSlot()],
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'full_gym',
      effectiveExp: 'advanced',
      phase: 1,
      goal: 'build_muscle',
      injuries: const ['shoulder'],
    );
    expect(days, hasLength(1));
    expect(days.first.exercisesA, isEmpty,
        reason: 'every shoulder_isolation option is shoulder-contraindicated -> '
            'the slot is dropped (safe omission), never a contraindicated pick');
  });

  test('uninjured user: same pool fills the slot (non-vacuity)', () {
    final days = ExerciseSelector.pickV4(
      slotDays: [dayWithShoulderIsoSlot()],
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'full_gym',
      effectiveExp: 'advanced',
      phase: 1,
      goal: 'build_muscle',
      injuries: const [],
    );
    expect(days.first.exercisesA, isNotEmpty,
        reason: 'an uninjured user must still get an exercise for the slot');
  });

  test('filter off (kill-switch path): contraindicated pool pick returns', () {
    final days = ExerciseSelector.pickV4(
      slotDays: [dayWithShoulderIsoSlot()],
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'full_gym',
      effectiveExp: 'advanced',
      phase: 1,
      goal: 'build_muscle',
      injuries: const ['shoulder'],
      applyInjuryUniversalFilter: false,
    );
    // Attempts 1-4 still exclude via queryV4, so the slot only fills from the
    // (now-unfiltered) universal pool — proving the flag gates exactly the U2
    // attempt-5 behavior.
    expect(days.first.exercisesA, isNotEmpty,
        reason: 'filter disabled -> the universal pool reverts to unfiltered');
  });
}
