// ⑧ 8-A / UNIT 2-cap — repeat-phase PINNED-SELECTION capability, PRODUCTION
// behavioral test (platform behavioral_test_path, §4.4 rule 21; SoT concept
// `repeat_phase_pinned_selection`).
//
// Drives the REAL PlanGenerator.instance.generateV4 through the Hive-boot harness
// the equipment-exclusion test established (seed the FULL library into
// exerciseBox, call the real engine) — so ExerciseSelector.buildPinnedDays'
// getByExactName resolve + custom fallback + the injury/exclusion refilter + the
// per-variant (A/B) build + the MF-1 fresh-fill are all exercised end-to-end.
//
// Proves:
//  (1) FACADE PARITY / ship-dark — `generate()` (which forwards the new
//      pinnedExercisesByDay + equipmentExclusions) == direct `generateV4()` with a
//      null pin, and a null pin is a valid full plan (the inert guarantee).
//  (2) FAITHFUL REPRODUCE — pinning a fresh plan's OWN per-day A (week 1) AND B
//      (week 2) names regenerates the SAME per-day set for BOTH weeks. This is the
//      test that catches an A/B collapse (a single-list `B=A` would make week-2
//      duplicate week-1).
//  (3) A/B DISTINCT — pinning day 0 with `(a:[X], b:[Y])`, X≠Y, puts X in the
//      A-weeks (1 & 3) and Y in the B-weeks (2 & 4) — never the same list twice.
//  (4) INJURY UNGATED — a newly-contraindicated pin is DROPPED even though
//      `disable_injury_universal_filter` governs only the att-5 pool; the emptied
//      variant FRESH-FILLS.
//  (5) TIER KEPT — a pin whose equipment_tier omits the user's tier is KEPT (tier
//      is a soft att4-relaxed heuristic; the caller guarantees same-tier).
//  (6) ABSENT NAME — a renamed/deleted pin is dropped; the variant fresh-fills.
//  (7) CUSTOM RESOLVE — a pinned name absent from the library resolves via the
//      user's custom_exercise_* rows.
//  (8) CARDINALITY — a partial pin (only some day indices) fresh-fills the
//      unpinned frames; the plan keeps its full day count, every day non-empty.
//
// Harness runs at phase 1 (no stage-0 decay / L2-L6 history-box needs) — the
// generateV4 TAIL (Stage-0 resolve + periodization + sequencing) is UNCHANGED by
// this unit (the branch only swaps how `populated` is built); the phase≥2 decay is
// covered by the existing progression tests; UNIT 2-int tests the real repeat
// through generateAndSchedule at phase≥2. The A/B weeks exist at phase 1 too
// (periodization `useB` fires on weekIdx 1 & 3 regardless of phase), so the
// collapse regression is observable here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

/// Per-day pin payload type (matches generateV4's `pinnedExercisesByDay` value).
typedef DayPins = ({List<String> a, List<String> b});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pinned_sel_behavioral');
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
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    // buildPinnedDays' custom fallback reads the user-scoped customBox
    // (customBox_<hash>) — open a session so getCustomExercises can wrap it.
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Phase gen({
    String equipment = 'full_gym',
    int phase = 1,
    Map<int, DayPins>? pins,
  }) =>
      PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: equipment,
        daysPerWeek: 4,
        phase: phase,
        experienceLevel: 'intermediate',
        injuries: const [],
        pinnedExercisesByDay: pins,
      );

  // Exercise-name SET for (week index, day index). week 0 = variant A (weeks 1/3),
  // week 1 = variant B (weeks 2/4) — the A/B alternation periodization materializes.
  Set<String> names(Phase p, int week, int day) =>
      p.weekPlans[week].workoutDays[day].exercises
          .map((e) => e.exerciseName)
          .toSet();

  int dayCount(Phase p) => p.weekPlans.first.workoutDays.length;

  test('(1) facade parity + null pin is a valid plan (ship-dark)', () {
    final direct = gen(); // generateV4, pins default null
    final facade = PlanGenerator.instance.generate(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'intermediate',
      injuries: const [],
    );
    expect(jsonEncode(facade.toMap()), jsonEncode(direct.toMap()),
        reason: 'generate() forwards the new pinnedExercisesByDay + '
            'equipmentExclusions params; with both defaulted it must be identical '
            'to a direct generateV4 — the facade additions are inert.');
    expect(direct.weekPlans, isNotEmpty);
    expect(names(direct, 0, 0), isNotEmpty,
        reason: 'the null-pin path is a valid, populated plan.');
  });

  test('(2) faithful reproduce: pinning a plan\'s own A+B names reproduces BOTH '
      'week 1 (A) and week 2 (B) per day', () {
    final fresh = gen();
    final pins = <int, DayPins>{
      for (var d = 0; d < dayCount(fresh); d++)
        d: (
          a: names(fresh, 0, d).toList(), // week-1 (variant A) names
          b: names(fresh, 1, d).toList(), // week-2 (variant B) names
        ),
    };
    final pinned = gen(pins: pins);
    expect(dayCount(pinned), dayCount(fresh));
    for (var d = 0; d < dayCount(fresh); d++) {
      expect(names(pinned, 0, d), names(fresh, 0, d),
          reason: 'day $d week-1 (A) reproduced.');
      expect(names(pinned, 1, d), names(fresh, 1, d),
          reason: 'day $d week-2 (B) reproduced — a single-list B=A collapse would '
              'make this equal week-1 instead, duplicating the phase.');
    }
    // Sanity: the split genuinely alternates A/B, so this test isn't vacuous.
    expect(names(fresh, 0, 0), isNot(equals(names(fresh, 1, 0))),
        reason: 'the 4-day build_muscle split has a distinct variant-B on day 0.');
  });

  test('(3) A/B distinct: pinning (a:[X], b:[Y]) puts X in weeks 1/3 and Y in '
      'weeks 2/4 — never the same list twice', () {
    final exBox = Hive.box(HiveService.exerciseBoxName);
    Map<String, dynamic> move(String id, String name) => {
          'id': id,
          'name': name,
          'movement_pattern': 'horizontal_push',
          'exercise_type': 'compound',
          'target_focus': 'chest',
          'primary_muscles': ['Chest'],
          'equipment_tier': ['bodyweight', 'basic_gym', 'full_gym'],
          'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
          'is_foundational': true,
          'default_sets': 3,
          'default_reps': '10',
          'rep_range': '8-12',
          'equipment_needed': ['bodyweight'],
        };
    exBox.put('pin_a_move', move('pin_a_move', 'Pin Test A Move'));
    exBox.put('pin_b_move', move('pin_b_move', 'Pin Test B Move'));
    addTearDown(() {
      exBox.delete('pin_a_move');
      exBox.delete('pin_b_move');
    });

    final plan = gen(pins: {
      0: (a: ['Pin Test A Move'], b: ['Pin Test B Move']),
    });
    // Weeks 1 & 3 (weekPlans 0 & 2) use variant A; weeks 2 & 4 (1 & 3) use B.
    expect(names(plan, 0, 0), {'Pin Test A Move'},
        reason: 'week 1 (A) day 0 is exactly the pinned A move.');
    expect(names(plan, 2, 0), {'Pin Test A Move'},
        reason: 'week 3 (A) day 0 is the pinned A move.');
    expect(names(plan, 1, 0), {'Pin Test B Move'},
        reason: 'week 2 (B) day 0 is the pinned B move — NOT the A move.');
    expect(names(plan, 3, 0), {'Pin Test B Move'},
        reason: 'week 4 (B) day 0 is the pinned B move.');
  });

  test('(4) injury UNGATED: a contraindicated pin is dropped; the variant '
      'fresh-fills', () {
    final exBox = Hive.box(HiveService.exerciseBoxName);
    exBox.put('pin_contra', {
      'id': 'pin_contra',
      'name': 'Pinned Contra Move',
      'movement_pattern': 'horizontal_push',
      'exercise_type': 'compound',
      'target_focus': 'chest',
      'primary_muscles': ['Chest'],
      'equipment_tier': ['bodyweight', 'basic_gym', 'full_gym'],
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': true,
      'default_sets': 3,
      'default_reps': '10',
      'rep_range': '8-12',
      'injury_contraindications': ['shoulder'],
      'equipment_needed': ['bodyweight'],
    });
    addTearDown(() => exBox.delete('pin_contra'));

    final plan = PlanGenerator.instance.generateV4(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'intermediate',
      injuries: const ['shoulder'],
      pinnedExercisesByDay: {
        0: (a: ['Pinned Contra Move'], b: const <String>[]),
      },
    );
    expect(names(plan, 0, 0).contains('Pinned Contra Move'), isFalse,
        reason: 'the UNGATED injury refilter drops a contraindicated pin.');
    expect(plan.weekPlans[0].workoutDays[0].exercises, isNotEmpty,
        reason: 'MF-1: the all-dropped A variant fresh-fills — never `(none)`.');
  });

  test('(5) tier KEPT: a pin whose tier omits the user\'s tier is preserved '
      '(no tier re-filter)', () {
    final exBox = Hive.box(HiveService.exerciseBoxName);
    exBox.put('pin_gymonly', {
      'id': 'pin_gymonly',
      'name': 'Pinned Gym Only',
      'movement_pattern': 'horizontal_push',
      'exercise_type': 'compound',
      'target_focus': 'chest',
      'primary_muscles': ['Chest'],
      'equipment_tier': ['full_gym'], // omits bodyweight
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': true,
      'default_sets': 3,
      'default_reps': '10',
      'rep_range': '8-12',
      'equipment_needed': ['machines'],
    });
    addTearDown(() => exBox.delete('pin_gymonly'));

    final plan = gen(equipment: 'bodyweight', pins: {
      0: (a: ['Pinned Gym Only'], b: const <String>[]),
    });
    expect(names(plan, 0, 0).contains('Pinned Gym Only'), isTrue,
        reason: 'tier is a SOFT att4-relaxed heuristic, not a hard constraint — a '
            'faithful repeat keeps the prior pick; the caller (2-int) guarantees '
            'same-tier, so a genuine tier change never reaches here.');
  });

  test('(6) absent name: a renamed/deleted pin is dropped; the variant fresh-fills',
      () {
    final plan = gen(pins: {
      0: (a: ['This Exercise Does Not Exist 12345'], b: const <String>[]),
    });
    expect(names(plan, 0, 0).contains('This Exercise Does Not Exist 12345'),
        isFalse);
    expect(plan.weekPlans[0].workoutDays[0].exercises, isNotEmpty,
        reason: 'MF-1 fresh-fill: an all-dropped variant is refilled, never `(none)`.');
  });

  test('(7) custom resolve: a pinned name absent from the library resolves via '
      'the user\'s custom_exercise_* rows', () async {
    final customBox = HiveService.instance.customBox; // scoped customBox_<hash>
    await customBox.put('custom_exercise_pin_t1', {
      'type': 'exercise',
      'name': 'My Landmine Press',
      'default_logging_type': 'weight_reps',
      'default_sets': 3,
      'default_reps': '10',
      'default_rest_secs': 60,
      'equipment_needed': ['barbell'],
      'primary_muscles': ['Shoulders'],
    });
    addTearDown(() => customBox.delete('custom_exercise_pin_t1'));

    final plan = gen(pins: {
      0: (a: ['My Landmine Press'], b: const <String>[]),
    });
    expect(names(plan, 0, 0).contains('My Landmine Press'), isTrue,
        reason: 'getByExactName misses (not in library) → the custom fallback '
            'resolves it via getCustomExercises + _buildCustomExercise.');
  });

  test('(8) cardinality: a partial pin fresh-fills unpinned frames; full day '
      'count, every day non-empty', () {
    final fresh = gen();
    // Pin ONLY day 0 (A+B); days 1..n carry no pin entry.
    final plan = gen(pins: {
      0: (
        a: names(fresh, 0, 0).toList(),
        b: names(fresh, 1, 0).toList(),
      ),
    });
    expect(dayCount(plan), dayCount(fresh),
        reason: 'unpinned frames still produce their day (fresh-filled by index).');
    for (var d = 0; d < dayCount(plan); d++) {
      expect(plan.weekPlans[0].workoutDays[d].exercises, isNotEmpty,
          reason: 'day $d week-1 non-empty.');
      expect(plan.weekPlans[1].workoutDays[d].exercises, isNotEmpty,
          reason: 'day $d week-2 non-empty (B never collapses to empty).');
    }
    // The pinned day reproduces both variants.
    expect(names(plan, 0, 0), names(fresh, 0, 0));
    expect(names(plan, 1, 0), names(fresh, 1, 0));
  });
}
