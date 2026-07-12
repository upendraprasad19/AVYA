// Behavioral regression — Ship 1 (U1 vocab + U2 universal-pool + U4 threading).
//
// End-to-end through the REAL generator (Hive + real exercise library seeded).
// Each test FAILS on the pre-fix code and PASSES post-fix:
//   • U1/U4-central: a LEGACY `back` injury (vocab drift) must exclude the
//     library's `lower_back`-contraindicated exercises — pre-fix `back` never
//     matched `lower_back`, so ZERO were excluded.
//   • U2: a `shoulder` injury must exclude Pike Push Up (a universal-pool pick
//     the attempt-5 fallback used to hand out unfiltered).
//   • Kill-switch: with `disable_injury_universal_filter=true`, Pike Push Up
//     REAPPEARS — proving both the revert path AND that the filter (not luck) is
//     what removes it (test non-vacuity).
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

  Set<String> exerciseNames(Phase phase) => {
        for (final wp in phase.weekPlans)
          for (final d in wp.workoutDays)
            for (final ex in d.exercises) ex.exerciseName,
      };

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

  test('shoulder injury excludes Pike Push Up from the universal pool (U2)', () {
    final phase = PlanGenerator.instance.generate(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'advanced',
      injuries: ['shoulder'],
    );
    expect(exerciseNames(phase), isNot(contains('Pike Push Up')),
        reason: 'Pike Push Up is shoulder-contraindicated — the U2 filter must '
            'skip it in the attempt-5 universal pool');
    expect(injuryHits(phase, {'shoulder'}), isEmpty,
        reason: 'no shoulder-contraindicated exercise anywhere in the plan');
  });

  test('kill-switch reverts U2 → Pike Push Up reappears (non-vacuity)', () async {
    await HiveService.instance.configBox
        .put('disable_injury_universal_filter', true);
    final phase = PlanGenerator.instance.generate(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'advanced',
      injuries: ['shoulder'],
    );
    // With the filter OFF, the attempt-5 pool bypasses the injury check exactly
    // as pre-U2 — so the shoulder-contraindicated Pike Push Up is handed out
    // again. This proves (a) the kill-switch reverts and (b) the ON test above
    // is non-vacuous (the filter, not luck, removes it).
    expect(exerciseNames(phase), contains('Pike Push Up'),
        reason: 'filter disabled → the universal pool must revert to unfiltered');
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
