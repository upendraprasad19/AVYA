// Library Batch S1b-2 (plan docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md, Decision 2): the same-movement
// rule on the PRODUCTION path (ExerciseRepository.queryV4 and ExerciseSelector.pickV4), one seam per test. Each test seeds
// a small library of REAL rows (E147 Sumo Squat / N14 Dumbbell Sumo Squat, E048 Glute Bridge / N19 Dumbbell Glute Bridge)
// so a single seam decides the outcome; the oracle reads the built PlannedExercise names, never the helper.
//
// Mutations (diagnose doc): the queryV4 expansion removed (tests 1, 2, 4, 6 red); the universal-pool skip reverted (test
// 5 red); the ON picked partners removed (test 3 red); demoted names expanded (test 7 red).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('same_movement_behavioral');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    final library = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    byId = {for (final r in library) r['id'] as String: r};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveService.instance.configBox.put('enable_core_list_pool', false);
    for (final k in HiveService.instance.workoutBox.keys.toList()) {
      await HiveService.instance.workoutBox.delete(k);
    }
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Replaces the exercise box with [rows] (real rows, optionally edited).
  Future<void> seed(List<Map<String, dynamic>> rows) async {
    final box = Hive.box(HiveService.exerciseBoxName);
    await box.clear();
    for (final r in rows) {
      await box.put(r['id'] as String, r);
    }
  }

  /// A third knee_dominant compound row that sorts after E147 / N14 (priority 3), so it is the fallback.
  Map<String, dynamic> testSquat() =>
      {...byId['E042']!, 'id': 'X001', 'name': 'Test Squat', 'priority_tier': 3, 'core_levels': ['beginner', 'intermediate', 'advanced']};

  Map<String, dynamic> warmup(String id) => {...byId[id]!, 'movement_pattern': ['warmup']};

  MuscleSlot slot(String pattern, String muscle, String type) =>
      MuscleSlot(targetMuscle: muscle, movementPattern: pattern, exerciseType: type, priority: 1);

  MuscleSlotDay day(List<MuscleSlot> a, [List<MuscleSlot>? b]) => MuscleSlotDay(
        name: 'Test Day', focus: 'legs', dayType: 'legs', intensity: 'hypertrophy', slotsA: a, slotsB: b);

  PopulatedDay pick(MuscleSlotDay d, {String goal = 'build_muscle', String level = 'intermediate', int phase = 2}) =>
      ExerciseSelector.pickV4(
        slotDays: [d],
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'home_dumbbells',
        effectiveExp: level,
        phase: phase,
        goal: goal,
        exclusions: const {},
        capability: null,
      ).first;

  List<String> names(List<PlannedExercise> xs) => [for (final x in xs) x.exerciseName];
  final knee = slot('knee_dominant', 'Quads', 'compound');

  test('1. queryV4: an excluded original also excludes its loaded version, and the reverse; nothing excluded keeps both', () async {
    await seed([byId['E147']!, byId['N14']!]);
    List<String> q(Set<String> ex) => [
          for (final r in ExerciseRepository.instance.queryV4(
              movementPattern: 'knee_dominant', equipmentTier: 'home_dumbbells', excludeNames: ex,
              exclusions: const {}, capability: null))
            r['name'] as String
        ];
    expect(q({}), containsAll(['Sumo Squat', 'Dumbbell Sumo Squat']), reason: 'non-vacuity');
    expect(q({'Sumo Squat'}), isNot(contains('Dumbbell Sumo Squat')));
    expect(q({'Dumbbell Sumo Squat'}), isNot(contains('Sumo Squat')));
  });

  test('2. OFF same day: two Quads slots never hold Sumo Squat and Dumbbell Sumo Squat together', () async {
    await seed([byId['E147']!, byId['N14']!]);
    final a = names(pick(day([knee, knee])).exercisesA);
    expect(a, isNotEmpty, reason: 'non-vacuity');
    expect(a.contains('Sumo Squat') && a.contains('Dumbbell Sumo Squat'), isFalse, reason: '$a');
  });

  test('3. ON (core-list pool) same day: a beginner day never holds the pair either', () async {
    await HiveService.instance.configBox.put('enable_core_list_pool', true);
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    final a = names(pick(day([knee, knee]), level: 'beginner').exercisesA);
    expect(a.where((n) => n == 'Sumo Squat' || n == 'Dumbbell Sumo Squat').length, 1, reason: '$a');
  });

  test('4. OFF variant B (non-strength) never holds the partner of an A pick', () async {
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    final d = pick(day([knee], [knee]));
    expect(names(d.exercisesA), ['Sumo Squat'], reason: 'E147 sorts first (same keys, lower id)');
    expect(names(d.exercisesB), ['Test Squat'], reason: 'B excludes A and its partner');
  });

  test('5. universal pool: a day holding Dumbbell Glute Bridge does not get Glute Bridge from the bodyweight pool', () async {
    await seed([byId['N19']!, warmup('E048'), warmup('E257')]);
    final iso = slot('hip_isolation', 'Glutes', 'isolation');
    final a = names(pick(day([iso, iso])).exercisesA);
    expect(a.first, 'Dumbbell Glute Bridge');
    expect(a, isNot(contains('Glute Bridge')), reason: '$a');
    expect(a, contains('Glute Kickback'), reason: 'the pool moves on to its next name');
  });

  test('6. L6: a demoted Sumo Squat is not replaced by its own loaded version', () async {
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    await HiveService.instance.workoutBox.put('schedule_$yesterday', {
      'date': yesterday,
      'exercises': [
        {'name': 'Test Squat', 'swapped_from': 'Sumo Squat'},
      ],
    });
    final a = names(pick(day([knee])).exercisesA);
    expect(a, ['Test Squat'], reason: 'L6 swaps Sumo Squat out and skips its partner');
  });

  test('7. MIRROR: a demoted loaded version does not demote its original (demoted names are per exercise)', () async {
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    await HiveService.instance.workoutBox.put('schedule_$yesterday', {
      'date': yesterday,
      'exercises': [
        {'name': 'Test Squat', 'swapped_from': 'Dumbbell Sumo Squat'},
      ],
    });
    expect(names(pick(day([knee])).exercisesA), ['Sumo Squat']);
  });
}
