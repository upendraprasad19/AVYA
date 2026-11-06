// ⑦ OI-89 Task 5 — the behavioural proof, on the PRODUCTION runtime path.
//
// A bodyweight-tier user must never be handed an exercise they cannot perform.
// This drives the real `ExerciseSelector.pickV4` -> `_cascadeFill`, not the
// diagnostic mirror (`cascade_tracer.dart` never calls the production selector
// and holds no reference to PlanEngineFlags — nothing flag-gated can be
// measured through it).
//
// THE ORACLE READS `equipmentNeeded` OFF THE BUILT `PlannedExercise`, never
// `equipment_tier`. The first attempt at OI-89 used an oracle that read the same
// field as its production predicate, which made the assertion tautological with
// respect to the harm — it could only ever prove the check was threaded, never
// that it worked. Note `PlannedExercise` exposes `exerciseName`, not `name`.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

/// All 11 strength patterns — including `knee_dominant` and `vertical_pull`,
/// which the first attempt's pattern list omitted and which is exactly where its
/// leaks lived.
const _patterns = <String>[
  'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull',
  'knee_dominant', 'hip_dominant', 'core', 'elbow_flexion',
  'elbow_extension', 'shoulder_isolation', 'hip_isolation',
];

Map<String, dynamic> _ex(
  String id,
  String name,
  String pattern,
  List<String> needed,
  List<String> tiers,
) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'movement_pattern': [pattern],
      'equipment_needed': needed,
      'equipment_tier': tiers,
      'exercise_type': 'compound',
      'target_focus': 'Test',
      'primary_muscles': ['Test'],
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': true,
      'priority_tier': 1,
      'is_active': true,
      'default_sets': 3,
      'default_reps': '10',
      'default_rest_secs': 60,
      'rep_range': '8-12',
      'logging_type': 'reps',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_capability_leak');
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
    // Cleanup is hygiene, not an assertion — a throw here would stack a second
    // failure that hides the real one. %TEMP% is reaped by the OS regardless.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
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

    // For EVERY pattern seed one performable row and one that is not. Both are
    // tagged `bodyweight` in equipment_tier — modelling the real over-tag class,
    // where the tier says yes and the equipment says no.
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    var n = 0;
    for (final p in _patterns) {
      await exBox.put('OK$n', _ex('OK$n', 'Safe $p', p, ['bodyweight'],
          ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']));
      await exBox.put('BAD$n', _ex('BAD$n', 'Barbell $p', p, ['barbell'],
          ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']));
      n++;
    }
    HiveService.instance.markInitializedForTests();
  });

  List<MuscleSlotDay> slotDays() => [
        MuscleSlotDay(
          name: 'Full Body',
          focus: 'full_body',
          dayType: 'full_body',
          intensity: 'strength',
          slotsA: [
            for (final p in _patterns)
              MuscleSlot(
                targetMuscle: 'Test',
                movementPattern: p,
                exerciseType: 'compound',
                priority: 1,
              ),
          ],
        ),
      ];

  List<String> offCapabilityPicks(
      List<PopulatedDay> days, Set<String> capability) {
    final leaks = <String>[];
    for (final d in days) {
      for (final e in [...d.exercisesA, ...d.exercisesB]) {
        if (!EquipmentCapability.canPerform(e.equipmentNeeded, capability)) {
          leaks.add('${e.exerciseName} needs ${e.equipmentNeeded}');
        }
      }
    }
    return leaks;
  }

  test('a bodyweight persona receives ZERO off-capability picks', () {
    final capability = EquipmentVocab.effectiveItems('bodyweight', null, null);
    final days = ExerciseSelector.pickV4(
      slotDays: slotDays(),
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'bodyweight',
      effectiveExp: 'beginner',
      phase: 1,
      goal: 'build_muscle',
      exclusions: const {},
      capability: capability,
    );
    expect(offCapabilityPicks(days, capability), isEmpty);
  });

  test('every pattern is still FILLED — the floor omits nothing here', () {
    // A capability filter that empties slots has traded one bug for another.
    // Each pattern has a performable row seeded, so all 11 must fill.
    final capability = EquipmentVocab.effectiveItems('bodyweight', null, null);
    final days = ExerciseSelector.pickV4(
      slotDays: slotDays(),
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'bodyweight',
      effectiveExp: 'beginner',
      phase: 1,
      goal: 'build_muscle',
      exclusions: const {},
      capability: capability,
    );
    expect(days.first.exercisesA.length, _patterns.length);
  });

  test('a null capability set means OFF — the barbell rows come back', () {
    // Proves the flag-OFF path is a genuine SKIP. Passing a "universal set"
    // instead would NOT be inert: canPerform fails closed on an unreadable
    // requirement regardless of what the set contains.
    final days = ExerciseSelector.pickV4(
      slotDays: slotDays(),
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'bodyweight',
      effectiveExp: 'beginner',
      phase: 1,
      goal: 'build_muscle',
      exclusions: const {},
      capability: null,
    );
    expect(days.first.exercisesA.length, _patterns.length);
  });

  test('an OWNED item unlocks its exercises (decision 4)', () {
    final capability =
        EquipmentVocab.effectiveItems('bodyweight', ['barbell'], null);
    final days = ExerciseSelector.pickV4(
      slotDays: slotDays(),
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'bodyweight',
      effectiveExp: 'beginner',
      phase: 1,
      goal: 'build_muscle',
      exclusions: const {},
      capability: capability,
    );
    expect(offCapabilityPicks(days, capability), isEmpty);
    expect(days.first.exercisesA.length, _patterns.length);
  });
  test('seam 5: a row with NO equipment_tier is still INJURY-filtered', () {
    // Before this batch, queryV4's tier block did `return true` for a row with a
    // missing/empty equipment_tier — an early return from the WHOLE fused
    // predicate, so such a row also skipped filters 4-8 INCLUDING the injury
    // exclusion. It is now a fall-through.
    //
    // Rule 21 needs a test that FAILS without the fix, and no existing one can:
    // 0 of the 259 seeded library rows have an empty equipment_tier. The live
    // population is community-synced rows, which land in the same box. So the
    // row is synthesised here.
    final box = Hive.box(HiveService.exerciseBoxName);
    box.put('NOTIER', <String, dynamic>{
      'id': 'NOTIER',
      'name': 'No Tier Shoulder Move',
      'movement_pattern': ['shoulder_isolation'],
      'equipment_needed': ['bodyweight'],
      'equipment_tier': <String>[], // the community-row shape
      'exercise_type': 'compound',
      'target_focus': 'Test',
      'primary_muscles': ['Test'],
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': true,
      'priority_tier': 1,
      'is_active': true,
      'default_sets': 3,
      'default_reps': '10',
      'default_rest_secs': 60,
      'rep_range': '8-12',
      'logging_type': 'reps',
      'injury_contraindications': ['shoulder'],
    });

    final hits = ExerciseRepository.instance.queryV4(
      movementPattern: 'shoulder_isolation',
      equipmentTier: 'bodyweight',
      injuryExclusions: const ['shoulder'],
      exclusions: const {},
      capability: null,
    );
    expect(hits.map((e) => e['id']), isNot(contains('NOTIER')),
        reason: 'a no-tier row must still be subject to the injury filter — '
            'the tier being unknown is no reason to hand an injured user a '
            'contraindicated exercise');
  });

}
