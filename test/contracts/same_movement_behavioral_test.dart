// Library Batch S1b-2 (plan docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md, Decision 2): the same-movement
// rule on the PRODUCTION path (ExerciseRepository.queryV4 and ExerciseSelector.pickV4), one seam per test. Each test seeds
// a small library of REAL rows (E147 Sumo Squat / N14 Dumbbell Sumo Squat, E048 Glute Bridge / N19 Dumbbell Glute Bridge)
// so a single seam decides the outcome; the oracle reads the built PlannedExercise names, never the helper.
//
// Unit 1B-F (plan docs/plans/2026-11-10-generator-1bf-flip.md, Ruling 7): the core-list pool is the only picker, so tests 2
// (OFF same day) and 5 (the universal pool) went with the cascade; tests 4, 6 and 7 run on the core path at `level:
// 'beginner'` (E147's `core_levels` is beginner only), and 6b / 6c are new. The core path only sorts a demoted row last, so
// `_pickCoreList` and `topUpDays` widen the demoted set by the loaded versions of each demoted ORIGINAL (one direction),
// which amends S1b-2's Decision 2 row "Demoted names ... no" for this path.
//
// Mutations (diagnose doc): the queryV4 expansion removed (test 1 red); the picked partners removed (test 3 red);
// `softFor` stops expanding (test 4 red: B = Dumbbell Sumo Squat); the widening applied both ways (test 7 red, only);
// the widening dropped (tests 6 and 6b red); the widening in `rankedPool`'s demoted set but not the avoid names (test 6b
// red, only); the top-up reading the unwidened set (test 6c red).
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

import '../plan_engine_v4/_helpers.dart' show exercise;

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

  test('3. same day: a beginner day never holds the pair', () async {
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    final a = names(pick(day([knee, knee]), level: 'beginner').exercisesA);
    expect(a.where((n) => n == 'Sumo Squat' || n == 'Dumbbell Sumo Squat').length, 1, reason: '$a');
  });

  test('4. variant B (non-strength) soft-avoids the partner of an A pick', () async {
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    final d = pick(day([knee], [knee]), level: 'beginner');
    expect(names(d.exercisesA), ['Dumbbell Sumo Squat'],
        reason: 'the loaded version ranks first for a home_dumbbells user (implement fit)');
    expect(names(d.exercisesB), ['Test Squat'], reason: 'B soft-avoids A and its partner (softFor)');
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
    final a = names(pick(day([knee]), level: 'beginner').exercisesA);
    expect(a, ['Test Squat'], reason: 'L6 swaps Sumo Squat out and skips its partner');
  });

  Future<void> demoteSumo() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    await HiveService.instance.workoutBox.put('schedule_$yesterday', {
      'date': yesterday,
      'exercises': [
        {'name': 'Test Squat', 'swapped_from': 'Sumo Squat'},
      ],
    });
  }

  test('6b. L6 avoid names: with every candidate avoided, the pick falls back to the pool head, never the partner', () async {
    // Test Squat is the previous phase's pick (avoided); Sumo Squat is demoted, and so is its loaded version. With the
    // loaded version in the avoid names every candidate is avoided and `_preferNovel` takes the pool head (Test Squat,
    // the only row not demoted); with it only in `rankedPool`'s demoted partition the pick walks to Dumbbell Sumo Squat.
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    await demoteSumo();
    final d = ExerciseSelector.pickV4(
      slotDays: [day([knee])],
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'home_dumbbells',
      effectiveExp: 'beginner',
      phase: 2,
      goal: 'build_muscle',
      exclusions: const {},
      capability: null,
      // Lowercase, as production writes it (WorkoutScheduleReadService.previousPhaseNamesByDay).
      previousPhaseByDay: {0: (a: ['test squat'], b: ['test squat'])},
    ).first;
    expect(names(d.exercisesA), ['Test Squat']);
  });

  test('6c. the thin-day top-up: a demoted Sumo Squat is not topped in as its loaded version', () async {
    // Injury `shoulder` (E147 and N14 carry hip and knee, which would drop them and pass vacuously), phase 2 (the demoted
    // set is read only from phase 2), a day holding two non-squat rows so one more is added.
    await seed([byId['E147']!, byId['N14']!, testSquat()]);
    await demoteSumo();
    final held = [exercise(name: 'Row One'), exercise(name: 'Row Two')];
    final out = ExerciseSelector.topUpDays(
      [PopulatedDay(name: 'Test Day', focus: 'legs', dayType: 'legs', intensity: 'hypertrophy', exercisesA: held, exercisesB: held)],
      slotDays: [day([knee])],
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'home_dumbbells',
      effectiveExp: 'beginner',
      phase: 2,
      goal: 'build_muscle',
      injuries: const ['shoulder'],
      applyInjurySubstitutePreference: false,
      exclusions: const {},
      capability: null,
    ).single;
    expect(names(out.exercisesA), ['Row One', 'Row Two', 'Test Squat']);
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
    expect(names(pick(day([knee]), level: 'beginner').exercisesA), ['Sumo Squat']);
  });
}
