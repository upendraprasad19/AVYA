// Batch B1 Task 1 — repeat-phase pins must check equipment CAPABILITY on the
// PRODUCTION path (diagnose docs/diagnoses/2026-10-22-att5-capability-mirror-only-b1c4e7.md).
//
// OI-89 added the capability skip to the diagnostic MIRROR only, so the scorecard
// could never see a production leak. This file drives the real
// ExerciseSelector.buildPinnedDays. The oracle reads `equipmentNeeded` off the
// BUILT PlannedExercise, never the predicate's own input. Unit 1B-F deleted the
// attempt-5 universal pool (and the mirror) with the cascade, and with them this
// file's two pool tests: the core-list path has no name-picked fallback that
// bypasses the capability filter.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late List<Map<String, dynamic>> library;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('universal_pool_capability');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    library = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Set<String>? bodyweight() => TrainingHistoryAnalyzer.resolveCapability(
      tier: 'bodyweight', exclusions: const {}, flagEnabled: true);

  Future<void> seedFullLibrary() async {
    final box = Hive.box(HiveService.exerciseBoxName);
    await box.clear();
    for (final r in library) {
      await box.put(r['id'] as String, r);
    }
  }

  MuscleSlot slot(String pattern, String muscle) => MuscleSlot(
        targetMuscle: muscle,
        movementPattern: pattern,
        exerciseType: 'compound',
        priority: 1,
      );

  MuscleSlotDay day(List<MuscleSlot> slots) => MuscleSlotDay(
        name: 'Test Day',
        focus: 'full_body',
        dayType: 'full_body',
        intensity: 'hypertrophy',
        slotsA: slots,
      );

  List<PopulatedDay> pinned(Object pins, Set<String>? capability) =>
      ExerciseSelector.buildPinnedDays(
        frames: [day([slot('elbow_flexion', 'Biceps')])],
        pinnedByDay: {
          0: (a: pins is List<String> ? pins : [pins as String], b: const <String>[])
        },
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: 'intermediate',
        phase: 2,
        goal: 'build_muscle',
        capability: capability,
      );

  Future<void> putCustom(String name, List<String> needed) async {
    final box = HiveService.instance.customBox;
    final key = 'custom_exercise_${name.toLowerCase().replaceAll(' ', '-')}';
    await box.put(key, {
      'type': 'exercise',
      'name': name,
      'equipment_needed': needed,
      'primary_muscles': ['Biceps'],
      'movement_pattern': ['elbow_flexion'],
      'logging_type': 'weight_reps',
    });
    addTearDown(() => box.delete(key));
  }

  List<String> names(List<PlannedExercise> xs) =>
      [for (final x in xs) x.exerciseName];

  test('a lone library pin the user cannot perform is dropped; the emptied '
      'variant is refilled',
      () async {
    await seedFullLibrary();
    final capability = bodyweight()!;
    final days = pinned('Barbell Curl', capability);
    final built = [...days.first.exercisesA, ...days.first.exercisesB];
    expect(names(built), isNot(contains('Barbell Curl')));
    expect(days.first.exercisesA, isNotEmpty,
        reason: 'the emptied A variant fresh-fills through pickV4');
    for (final e in built) {
      expect(EquipmentCapability.canPerform(e.equipmentNeeded, capability),
          isTrue,
          reason: '${e.exerciseName} needs ${e.equipmentNeeded}');
    }
  });

  // B-pass F6: the refill fires only when the WHOLE variant empties. With a
  // performable pin beside it, an unperformable pin just shortens the day by
  // one, the same shape as today's exclusion / injury pin drops.
  test('next to a performable pin, an unperformable one shortens the day by one',
      () async {
    await seedFullLibrary();
    final days =
        pinned(['Barbell Curl', 'Self-Resisted Bicep Curl'], bodyweight());
    expect(names(days.first.exercisesA), ['Self-Resisted Bicep Curl']);
  });

  test('a custom pin with no recorded equipment is kept', () async {
    await seedFullLibrary();
    await putCustom('My Band Row', const []);
    final days = pinned('My Band Row', bodyweight());
    expect(names(days.first.exercisesA), contains('My Band Row'));
  });

  test('a custom pin needing kit the user lacks is dropped', () async {
    await seedFullLibrary();
    await putCustom('My Barbell Curl Variant', const ['barbell']);
    final days = pinned('My Barbell Curl Variant', bodyweight());
    expect(names(days.first.exercisesA), isNot(contains('My Barbell Curl Variant')));
  });

  test('pins with capability null are kept', () async {
    await seedFullLibrary();
    final days = pinned('Barbell Curl', null);
    expect(names(days.first.exercisesA), contains('Barbell Curl'));
  });
}
