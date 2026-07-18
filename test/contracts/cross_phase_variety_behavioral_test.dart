// W3.4 (Batch 11-B) — cross-phase VARIETY, PRODUCTION behavioral test (platform
// behavioral_test_path, §4.4 rule 21; SoT `cross_phase_variety`).
//
// Drives the REAL PlanGenerator.instance.generateV4 through the library-seed
// harness. `previousPhaseByDay` (per-day prior-phase A/B picks, LOWERCASED) makes
// the cascade PREFER a same-pattern sibling NOT used last phase (_preferNovel).
//
// Persona: full_gym / ADVANCED (suitableFor:null → the broadest, deepest pool) so
// avoiding last phase's picks genuinely pulls in novel siblings → the exercise
// SET changes (a shallow/beginner persona has pool-depth-1 slots where _preferNovel
// is a guaranteed no-op — 11-C's own test hit this class and chose deep-pool too).
//
// Proves:
//  (1) VARIETY — phase N+1 avoiding phase N's picks → the SET DIFFERS from phase N.
//  (2) SHIP-DARK / DETERMINISM — null previousPhaseByDay → the SAME plan (avoidNames
//      empty → _preferNovel = pool.first → byte-identical; and queryV4 is deterministic).
//  (3) BOUNDED — every day stays non-empty (no `(none)`) under variety.
//  (4) SAFETY — variety + a shoulder injury never surfaces a contraindicated exercise
//      (variety re-ranks WITHIN the already-injury-filtered pool).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, List<String>> contraByName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cross_phase_variety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    contraByName = {};
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
      contraByName[(r['name'] as String? ?? '').toLowerCase()] =
          ((r['injury_contraindications'] as List?) ?? const [])
              .map((e) => e.toString().toLowerCase())
              .toList();
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Phase gen({
    Map<int, ({List<String> a, List<String> b})>? prev,
    List<String> injuries = const [],
  }) =>
      PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: 2,
        experienceLevel: 'advanced',
        injuries: injuries,
        previousPhaseByDay: prev,
      );

  Set<String> allNames(Phase p) => {
        for (final wk in p.weekPlans)
          for (final d in wk.workoutDays)
            for (final e in d.exercises) e.exerciseName,
      };

  // Build a previousPhaseByDay map from a plan's variant-A (weekPlans[0]) and
  // variant-B (weekPlans[1]) days — LOWERCASED, exactly as previousPhaseNamesByDay.
  Map<int, ({List<String> a, List<String> b})> prevFrom(Phase p) {
    final wkA = p.weekPlans[0].workoutDays;
    final wkB = p.weekPlans.length > 1 ? p.weekPlans[1].workoutDays : wkA;
    return {
      for (var i = 0; i < wkA.length; i++)
        i: (
          a: [for (final e in wkA[i].exercises) e.exerciseName.toLowerCase()],
          b: i < wkB.length
              ? [for (final e in wkB[i].exercises) e.exerciseName.toLowerCase()]
              : const <String>[],
        ),
    };
  }

  test('(1) variety avoids the previous phase picks → the SET changes', () {
    final prevPhase = gen();
    final base = allNames(prevPhase);
    final on = allNames(gen(prev: prevFrom(prevPhase)));
    expect(on, isNot(equals(base)),
        reason: 'variety must pull in novel same-pattern siblings');
  });

  test('(2) ship-dark: null previousPhaseByDay → the SAME plan (deterministic)',
      () {
    expect(allNames(gen()), equals(allNames(gen())),
        reason: 'null prev → avoidNames empty → _preferNovel = pool.first → '
            'byte-identical (queryV4 deterministic)');
  });

  test('(3) bounded: every day non-empty under variety', () {
    final p = gen(prev: prevFrom(gen()));
    for (final d in p.weekPlans.first.workoutDays) {
      expect(d.exercises, isNotEmpty, reason: 'variety never empties a slot');
    }
  });

  test('(4) safety: variety + shoulder injury never surfaces a contra exercise',
      () {
    final prev = prevFrom(gen(injuries: const ['shoulder']));
    final p = gen(prev: prev, injuries: const ['shoulder']);
    for (final n in allNames(p)) {
      expect((contraByName[n.toLowerCase()] ?? const []).contains('shoulder'),
          isFalse,
          reason: '"$n" is shoulder-contraindicated but appears under variety');
    }
  });

  // B-pass P1: cover the SERVICE reader's core (previousPhaseNamesByDay), which the
  // generateV4-driven cases above don't exercise — the pure helper (A=week1/B=week2,
  // lowercase, day-index union, workout-row filter) + the ship-dark flag gate.
  group('previousPhaseNamesFrom — service reader core', () {
    Map<String, dynamic> wrow(int dayIdx, List<String> names) => {
          'type': 'workout',
          'workout_day_index': dayIdx,
          'exercises': [
            for (final n in names) {'exercise_name': n}
          ],
        };

    test('per-day A(week1)/B(week2), LOWERCASED, day-index union', () {
      final m = WorkoutScheduleReadService.previousPhaseNamesFrom(
        week1: [
          wrow(0, ['Barbell Bench Press', 'Push Up']),
          wrow(1, ['Barbell Back Squat']),
        ],
        week2: [wrow(0, ['Arnold Press'])],
      );
      expect(m[0]!.a, ['barbell bench press', 'push up']); // A from week1
      expect(m[0]!.b, ['arnold press']); // B from week2
      expect(m[1]!.a, ['barbell back squat']);
      expect(m[1]!.b, isEmpty); // union spans day 1 even with no week2 row
    });

    test('empty weeks → empty map', () {
      expect(
          WorkoutScheduleReadService.previousPhaseNamesFrom(
              week1: const [], week2: const []),
          isEmpty);
    });

    test('non-workout (rest) rows are ignored', () {
      final m = WorkoutScheduleReadService.previousPhaseNamesFrom(
        week1: [
          {'type': 'rest', 'workout_day_index': 0, 'exercises': const []},
          wrow(1, ['Deadlift']),
        ],
        week2: const [],
      );
      // The range spans 0..maxIdx (like repeatPinsFrom); a rest/gap day-index is an
      // EMPTY entry (buildPinnedDays fresh-fills it), NOT a populated one.
      expect(m[0]!.a, isEmpty); // rest row's names NOT collected
      expect(m[1]!.a, ['deadlift']);
    });

    test('ship-dark: flag OFF → previousPhaseNamesByDay() returns {}', () async {
      await HiveService.instance.configBox
          .delete('enable_cross_phase_variety');
      expect(WorkoutScheduleReadService.instance.previousPhaseNamesByDay(),
          isEmpty);
    });
  });
}
