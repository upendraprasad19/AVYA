// Behavioral regression — Ship 1 (U1 vocab + U2 universal-pool + U4 threading).
//
// End-to-end through the REAL generator (Hive + real exercise library seeded).
// Each test FAILS on the pre-fix code and PASSES post-fix:
//   • U1/U4-central: a LEGACY `back` injury (vocab drift) must exclude the
//     library's `lower_back`-contraindicated exercises — pre-fix `back` never
//     matched `lower_back`, so ZERO were excluded.
//   • U2 (end-to-end): a `shoulder` injury must remove EVERY shoulder-contra
//     exercise from the plan; non-vacuity is shown by the same UNINJURED persona
//     still getting shoulder-loaded exercises. (Batch 13-A moved the
//     shoulder_isolation universal-pool fallback to the SAFE E261, so the
//     attempt-5 filter + its `disable_injury_universal_filter` kill-switch are now
//     proven deterministically in injury_safe_omission_production_test.dart.)
//   • U4 HIGH-3: the AI-coach "regenerate my plan" path (which DROPPED injuries)
//     must exclude a knee-injured user's knee-contraindicated exercises.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, Set<String>> contraByName; // name (lower) → contra tokens

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_injury_filter');
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
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      HiveService.exerciseBoxName,
      'workoutBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
      'userBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);

    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    contraByName = {};
    for (final e in lib) {
      final m = Map<String, dynamic>.from(e as Map);
      await exBox.put(m['id'], m);
      final ic = m['injury_contraindications'];
      final tokens = ic is List
          ? ic.map((t) => t.toString().toLowerCase()).toSet()
          : <String>{};
      contraByName[(m['name'] as String).toLowerCase()] = tokens;
    }

    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  // All injury tokens a plan's MAIN exercises breach for [injuries].
  Set<String> injuryHits(Phase phase, Set<String> injuries) {
    final hits = <String>{};
    for (final wp in phase.weekPlans) {
      for (final day in wp.workoutDays) {
        for (final ex in day.exercises) {
          final contra = contraByName[ex.exerciseName.toLowerCase()] ?? const {};
          hits.addAll(contra.intersection(injuries));
        }
      }
    }
    return hits;
  }

  test('legacy `back` vocab excludes lower_back-contra exercises (U1/U4-central)',
      () {
    final phase = PlanGenerator.instance.generate(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'advanced',
      injuries: ['back'], // LEGACY chip vocab — normalized to lower_back inside
    );
    expect(phase.weekPlans, isNotEmpty);
    expect(
      injuryHits(phase, {'lower_back'}),
      isEmpty,
      reason: 'a `back` injury must exclude lower_back-contraindicated exercises '
          '(vocab normalized centrally in generateV4)',
    );
  });

  test('shoulder injury → NO shoulder-contraindicated exercise in the plan (U1/U2/U4)',
      () {
    // End-to-end: the always-on injury filter (queryV4 attempts 1-4 + the attempt-5
    // universal-pool U2 skip) removes every shoulder-contraindicated exercise from an
    // injured user's generated plan. (Batch 13-A: the attempt-5 universal-pool filter
    // + its kill-switch are proven deterministically by
    // injury_safe_omission_production_test.dart, which seeds an all-contra pool and
    // asserts safe-omission / kill-switch-revert on the real pickV4 path. This test
    // pins the property end-to-end through the real library + full generate().)
    final phase = PlanGenerator.instance.generate(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'advanced',
      injuries: ['shoulder'],
    );
    expect(phase.weekPlans, isNotEmpty);
    expect(injuryHits(phase, {'shoulder'}), isEmpty,
        reason: 'no shoulder-contraindicated exercise may appear anywhere in an '
            'injured user\'s plan');
  });

  test('non-vacuity: the SAME uninjured persona DOES get shoulder-loaded exercises',
      () {
    // Proves the injured-user test above is not vacuous: the identical persona,
    // uninjured, gets shoulder-contraindicated exercises (overhead presses etc.), so
    // their ABSENCE for the injured user is the filter's doing — not the library
    // simply lacking such exercises.
    final phase = PlanGenerator.instance.generate(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'advanced',
      injuries: const [],
    );
    expect(injuryHits(phase, {'shoulder'}), isNotEmpty,
        reason: 'an uninjured full_gym plan must contain ≥1 shoulder-loaded exercise — '
            'else the injured-user test would pass vacuously');
  });

  test('coach regenerate excludes a knee user\'s knee-contra exercises (U4 HIGH-3)',
      () async {
    await HiveService.instance.userBox.put('profile', {
      'primary_goal': 'build_muscle',
      'equipment_access': 'full_gym',
      'days_per_week': 4,
      'fitness_experience': 'advanced',
      'injuries': ['knee'],
    });
    await HiveService.instance.userBox.put('progress', {'current_phase': 4});

    final out = await RegeneratePlanPlanner.instance.plan(weeks: 4);
    expect(out.rawSchedules, isNotEmpty);

    final hits = <String>{};
    for (final row in out.rawSchedules) {
      final exs = row['exercises'];
      if (exs is List) {
        for (final e in exs) {
          final name =
              (e as Map)['exercise_name']?.toString().toLowerCase() ?? '';
          hits.addAll((contraByName[name] ?? const {}).intersection({'knee'}));
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'the coach regen dropped injuries pre-fix; post-U4 it threads '
            'profile[injuries] into generate() so knee-contra exercises are excluded');
  });
}
