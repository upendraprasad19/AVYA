// OI-454 (SBF-QUADS-FLOOR option a): Quads reach their weekly floor in the 6-day build_muscle split.
//
// Two levers, both proven here on the REAL `PlanGenerator.generateV4` over the shipped library:
//  D1  Legs B swaps its Glutes / hip_isolation slot for a Quads / knee_dominant / compound slot.
//  D2  `SessionBudgetContext.quadPrimaryCreditsGlutes` is false for 6-day build_muscle only: an exercise
//      whose FIRST listed muscle is Quads credits Quads but not Glutes, so the Glutes top never refuses it.
//
// The counts below are taken from the generated plan with a restated, independent muscle reader (a
// substring match on the library row's primary_muscles), never from the allocator's own ledger, except
// where the test says it compares the two on purpose.
//
// The sweep also pins, on the PRODUCTION path (core-list pool OFF, which the gate's build_muscle subset
// does not run): every group's credited weekly total under its top and its session total under its
// cap in all four weeks, every day inside its minutes, Glutes at or above the level floor, Hamstrings
// never below the pre-change figure, and the allocator's label for each Quads shortfall at 90 minutes.
//
// The `_quadsAfter` table is the figure measured when the batch landed (week 1, phase 1, Quads weekly
// sets); `_quadsBefore` is the figure on the tree before it. Both are ratchets: a regression that loses
// the slot or the policy lowers Quads and reddens the sweep.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

const _levels = ['beginner', 'intermediate', 'advanced'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];

/// Quads weekly sets, week 1, 6-day build_muscle, key `level|tier|minutes`: BEFORE OI-454 (frozen).
const _quadsBefore = <String, int>{
  'beginner|bodyweight|60': 2, 'beginner|bodyweight|90': 2,
  'beginner|home_dumbbells|60': 2, 'beginner|home_dumbbells|90': 2,
  'beginner|basic_gym|60': 2, 'beginner|basic_gym|90': 2,
  'beginner|full_gym|60': 6, 'beginner|full_gym|90': 6,
  'intermediate|bodyweight|60': 5, 'intermediate|bodyweight|90': 5,
  'intermediate|home_dumbbells|60': 5, 'intermediate|home_dumbbells|90': 5,
  'intermediate|basic_gym|60': 3, 'intermediate|basic_gym|90': 3,
  'intermediate|full_gym|60': 7, 'intermediate|full_gym|90': 8,
  'advanced|bodyweight|60': 5, 'advanced|bodyweight|90': 5,
  'advanced|home_dumbbells|60': 5, 'advanced|home_dumbbells|90': 5,
  'advanced|basic_gym|60': 3, 'advanced|basic_gym|90': 3,
  'advanced|full_gym|60': 6, 'advanced|full_gym|90': 8,
};

/// The same, AFTER OI-454 (measured).
const _quadsAfter = <String, int>{
  'beginner|bodyweight|60': 10, 'beginner|bodyweight|90': 10,
  'beginner|home_dumbbells|60': 10, 'beginner|home_dumbbells|90': 10,
  'beginner|basic_gym|60': 9, 'beginner|basic_gym|90': 10,
  'beginner|full_gym|60': 10, 'beginner|full_gym|90': 10,
  'intermediate|bodyweight|60': 9, 'intermediate|bodyweight|90': 12,
  'intermediate|home_dumbbells|60': 10, 'intermediate|home_dumbbells|90': 12,
  'intermediate|basic_gym|60': 7, 'intermediate|basic_gym|90': 10,
  'intermediate|full_gym|60': 10, 'intermediate|full_gym|90': 12,
  'advanced|bodyweight|60': 8, 'advanced|bodyweight|90': 12,
  'advanced|home_dumbbells|60': 8, 'advanced|home_dumbbells|90': 13,
  'advanced|basic_gym|60': 5, 'advanced|basic_gym|90': 9,
  'advanced|full_gym|60': 8, 'advanced|full_gym|90': 12,
};

/// Hamstrings weekly sets (allocator credit), week 1, BEFORE OI-454: the change must not lower them.
const _hamstringsBefore = <String, int>{
  'beginner|bodyweight|60': 4, 'beginner|bodyweight|90': 4,
  'beginner|home_dumbbells|60': 4, 'beginner|home_dumbbells|90': 4,
  'beginner|basic_gym|60': 8, 'beginner|basic_gym|90': 8,
  'beginner|full_gym|60': 8, 'beginner|full_gym|90': 8,
  'intermediate|bodyweight|60': 5, 'intermediate|bodyweight|90': 5,
  'intermediate|home_dumbbells|60': 7, 'intermediate|home_dumbbells|90': 7,
  'intermediate|basic_gym|60': 11, 'intermediate|basic_gym|90': 11,
  'intermediate|full_gym|60': 11, 'intermediate|full_gym|90': 11,
  'advanced|bodyweight|60': 5, 'advanced|bodyweight|90': 5,
  'advanced|home_dumbbells|60': 7, 'advanced|home_dumbbells|90': 7,
  'advanced|basic_gym|60': 12, 'advanced|basic_gym|90': 13,
  'advanced|full_gym|60': 12, 'advanced|full_gym|90': 13,
};

/// build_muscle bands restated from the plan (floor, top, session cap) by level.
const _band = <String, (int, int, int)>{
  'beginner': (10, 12, 6),
  'intermediate': (12, 16, 8),
  'advanced': (14, 20, 10),
};

/// The allocator's label for a Quads shortfall at 90 minutes, week 1 (a persona absent here reaches its floor).
/// Read from `AllocationStats.belowFloor['Quads']`, so a doc that says why Quads stop short is checked.
const _quadsLabel90 = <String, String>{
  'intermediate|basic_gym|90': 'cap_limited',
  'advanced|bodyweight|90': 'co_group_limited',
  'advanced|home_dumbbells|90': 'time_limited',
  'advanced|basic_gym|90': 'time_limited',
  'advanced|full_gym|90': 'time_limited',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName;
  late Map<String, Map<String, dynamic>> rowsById;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('quads_floor_6day');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in rows) {
      await exBox.put((r['id'] ?? r['name']).toString(), r);
    }
    byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
    rowsById = {for (final r in rows) r['id'] as String: r};
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

  Phase gen(String goal, String tier, int days, String level, int minutes,
          {int phase = 1, List<String> focus = const []}) =>
      PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: const [],
        bodyFocus: focus,
        sessionDuration: minutes,
        previousWeights: const {},
      );

  List<String> musclesOf(PlannedExercise e) =>
      [for (final m in (byName[e.exerciseName.toLowerCase()]?['primary_muscles'] as List? ?? const [])) '$m'];

  /// The allocator budgets an exercise only when it has a library row and is neither a custom nor a
  /// timed / cardio / distance row (a Wall Sit keeps its sets and only spends time).
  bool budgeted(PlannedExercise e) =>
      e.customOrigin == null &&
      !const {'timed', 'cardio', 'distance'}.contains(e.loggingType) &&
      byName.containsKey(e.exerciseName.toLowerCase());

  bool lists(List<String> muscles, String needle) => muscles.any((m) => m.toLowerCase().contains(needle));

  /// Weekly sets of [week] (0-based) crediting [needle] in full: every exercise that LISTS it.
  int fullCredit(Phase plan, int week, String needle) {
    var n = 0;
    for (final d in plan.weekPlans[week].workoutDays) {
      for (final e in d.exercises.where(budgeted)) {
        if (lists(musclesOf(e), needle)) n += e.sets;
      }
    }
    return n;
  }

  /// Glutes under the OI-454 rule: an exercise whose first listed muscle is Quads does not credit them.
  int glutesWithoutQuadFirst(Phase plan, int week) {
    var n = 0;
    for (final d in plan.weekPlans[week].workoutDays) {
      for (final e in d.exercises.where(budgeted)) {
        final m = musclesOf(e);
        if (m.isEmpty || !lists(m, 'glute')) continue;
        // A hip hinge that also lists Hamstrings (Trap Bar Deadlift lists Quads first) keeps its Glutes.
        if (!lists(m, 'hamstring') && m.first.toLowerCase().contains('quad') && !lists([m.first], 'glute')) continue;
        n += e.sets;
      }
    }
    return n;
  }

  /// Tops, session caps and minutes of every week and day of [plan], in the credited sense of this split (the
  /// rule is applied through `creditedOf`, the function the generator's ledgers use, so this cannot catch a rule that is
  /// wrong, only a week-2-to-4 pass or a phase that overshoots under it). The band is the EFFECTIVE level's, and in a
  /// lighter phase (4, 8, 12) every group's top is the band floor. A focus group (cap 12, top 25) is passed in [focusGroups].
  /// A failure is appended to [bad]; the gate (`session_set_budget_gate_test.dart`) owns the explained-overage exemptions
  /// for forced days, so a failure here on a library change should be read against its `countForced` / `forcedDays`.
  void auditPlan(Phase plan, String level, int phase, int minutes, String key, List<String> bad,
      {Set<String> focusGroups = const {}}) {
    final eff = PlanGenerator.effectiveLevel(level, phase);
    final (floor, bandTop, bandCap) = _band[eff]!;
    final lighter = phase % 4 == 0;
    int top(String grp) => lighter ? floor : (focusGroups.contains(grp) ? 25 : bandTop);
    int cap(String grp) => (!lighter && focusGroups.contains(grp)) ? 12 : bandCap;
    for (var w = 0; w < plan.weekPlans.length; w++) {
      final weekly = <String, int>{};
      for (final d in plan.weekPlans[w].workoutDays) {
        final session = <String, int>{};
        for (final e in d.exercises.where(budgeted)) {
          for (final grp in BudgetMuscleGroups.creditedOf(musclesOf(e), quadPrimaryCreditsGlutes: false)) {
            session[grp] = (session[grp] ?? 0) + e.sets;
            weekly[grp] = (weekly[grp] ?? 0) + e.sets;
          }
        }
        session.forEach((grp, n) {
          if (n > cap(grp)) bad.add('$key p$phase w${w + 1} ${d.name}: $grp $n > session cap ${cap(grp)}');
        });
        final secs = SessionBudget.estimateDaySecondsFromPlanDay(d.toMap(), rowsById);
        if (secs > (minutes + 2) * 60) {
          bad.add('$key p$phase w${w + 1} ${d.name}: ${(secs / 60).toStringAsFixed(1)} min > ${minutes + 2}');
        }
      }
      weekly.forEach((grp, n) {
        if (n > top(grp)) bad.add('$key p$phase w${w + 1}: $grp $n > weekly top ${top(grp)}');
      });
    }
  }

  /// Whether [e] is a quad-first exercise of the knee_dominant pattern (what the Legs B slot asks for).
  bool kneeQuadFirst(PlannedExercise e) {
    final row = byName[e.exerciseName.toLowerCase()];
    final m = musclesOf(e);
    return row != null &&
        m.isNotEmpty &&
        m.first.toLowerCase().contains('quad') &&
        ((row['movement_pattern'] as List? ?? const []).contains('knee_dominant'));
  }

  group('D1: the Legs B slot', () {
    test('the slot and the credit flag share one predicate: selectV4 has a Legs B day exactly when it is true', () {
      for (final goal in ['build_muscle', 'lose_fat', 'strength', 'general_fitness']) {
        for (final days in [3, 4, 5, 6]) {
          for (final level in _levels) {
            final hasLegsB = SplitResolver.selectV4(goal, days, experienceLevel: level).any((d) => d.name == 'Legs B');
            expect(hasLegsB, SplitResolver.hasQuadLegsBSplit(goal, days), reason: '$goal ${days}d $level');
          }
        }
      }
    });

    test('Legs B carries a Quads knee_dominant compound slot at priority 2 and no glute isolation slot', () {
      final legsB = SplitResolver.selectV4('build_muscle', 6).firstWhere((d) => d.name == 'Legs B');
      expect(legsB.slotsA.length, 8, reason: 'a swap, not an add');
      final quad = legsB.slotsA.where((s) =>
          s.targetMuscle == 'Quads' &&
          s.movementPattern == 'knee_dominant' &&
          s.exerciseType == 'compound' &&
          s.priority == 2);
      expect(quad, hasLength(1));
      expect(
        legsB.slotsA.where((s) => s.targetMuscle == 'Glutes' && s.movementPattern == 'hip_isolation'),
        isEmpty,
      );
      // The priority-1 glute and hamstring compounds are still there (the deload keeps priority 1).
      expect(legsB.slotsA.where((s) => s.priority == 1).map((s) => s.targetMuscle),
          containsAll(['Hamstrings', 'Glutes']));
    });

    test('controls: Legs A and the default 6-day PPL keep their glute isolation slot', () {
      final legsA = SplitResolver.selectV4('build_muscle', 6).firstWhere((d) => d.name == 'Legs A');
      expect(legsA.slotsA.where((s) => s.targetMuscle == 'Glutes' && s.movementPattern == 'hip_isolation'),
          hasLength(1));
      for (final g in ['lose_fat', 'strength', 'general_fitness']) {
        final legs = SplitResolver.selectV4(g, 6).where((d) => d.dayType == 'legs');
        for (final d in legs) {
          expect(d.slotsA.where((s) => s.targetMuscle == 'Glutes' && s.movementPattern == 'hip_isolation'),
              isNotEmpty,
              reason: '$g 6-day ${d.name} is the default PPL and keeps its glute isolation slot');
        }
      }
    });
  });

  group('D2: the credit rule', () {
    test('creditedOf drops Glutes only for an exercise whose first muscle is Quads, and only when asked', () {
      const squat = ['Quads', 'Glutes'];
      expect(BudgetMuscleGroups.creditedOf(squat), {'Quads', 'Glutes'}, reason: 'the default is today');
      expect(BudgetMuscleGroups.creditedOf(squat, quadPrimaryCreditsGlutes: true), {'Quads', 'Glutes'});
      expect(BudgetMuscleGroups.creditedOf(squat, quadPrimaryCreditsGlutes: false), {'Quads'});
      expect(BudgetMuscleGroups.creditedOf(['Quads', 'Glutes', 'Calves'], quadPrimaryCreditsGlutes: false),
          {'Quads', 'Calves'});
      // First muscle is not Quads: nothing is dropped.
      expect(BudgetMuscleGroups.creditedOf(['Glutes', 'Quads'], quadPrimaryCreditsGlutes: false),
          {'Glutes', 'Quads'});
      expect(BudgetMuscleGroups.creditedOf(['Hamstrings', 'Glutes'], quadPrimaryCreditsGlutes: false),
          {'Hamstrings', 'Glutes'});
      expect(BudgetMuscleGroups.creditedOf(['Lower Back', 'Glutes', 'Hamstrings'], quadPrimaryCreditsGlutes: false),
          {'Glutes', 'Hamstrings'}, reason: 'the erectors map to no group, the first muscle is not Quads');
      // A leading token that maps to no group (Adductors) or to Glutes (Glute Medius) is NOT skipped: first listed wins.
      expect(BudgetMuscleGroups.creditedOf(['Adductors', 'Quads', 'Glutes'], quadPrimaryCreditsGlutes: false),
          {'Quads', 'Glutes'}, reason: 'Lateral Lunge, Cossack Squat');
      expect(BudgetMuscleGroups.creditedOf(['Glute Medius', 'Quads', 'Glutes'], quadPrimaryCreditsGlutes: false),
          {'Quads', 'Glutes'}, reason: 'Curtsey Squat');
      // A hip hinge that lists Quads first AND Hamstrings (Trap Bar Deadlift) keeps its Glutes: the heaviest glute lift.
      expect(
          BudgetMuscleGroups.creditedOf(['Quads', 'Glutes', 'Lower Back', 'Hamstrings'],
              quadPrimaryCreditsGlutes: false),
          {'Quads', 'Glutes', 'Hamstrings'});
      // A quad-only or empty list is untouched, and nothing throws.
      expect(BudgetMuscleGroups.creditedOf(['Quads'], quadPrimaryCreditsGlutes: false), {'Quads'});
      expect(BudgetMuscleGroups.creditedOf(const [], quadPrimaryCreditsGlutes: false), isEmpty);
      // The focus mapper is NOT affected: a user who picks Quads and Glutes as focus keeps both.
      expect(BudgetMuscleGroups.of(['Quads', 'Glutes']), {'Quads', 'Glutes'});
    });

    test('named library rows: the squat and lunge family drops Glutes; the 7 not-quad-first rows, the hinges and the glute lifts keep them',
        () {
      List<String> primary(String name) => [for (final m in (byName[name.toLowerCase()]!['primary_muscles'] as List)) '$m'];
      Set<String> credited(String name) => BudgetMuscleGroups.creditedOf(primary(name), quadPrimaryCreditsGlutes: false);
      for (final n in ['Barbell Back Squat', 'Goblet Squat', 'Leg Press', 'Walking Lunge', 'Bulgarian Split Squat']) {
        expect(credited(n), isNot(contains('Glutes')), reason: n);
        expect(credited(n), contains('Quads'), reason: n);
      }
      for (final n in [
        'Box Squat', 'Lateral Lunge', 'Sumo Squat', 'Cossack Squat', 'Weighted Cossack Squats', 'Curtsey Squat',
        'Skater Hops', // the 7 rows that list Quads and Glutes with another muscle first
        'Trap Bar Deadlift', 'Deadlift', 'Romanian Deadlift', 'Glute Bridge', // hinges and glute lifts
      ]) {
        expect(credited(n), contains('Glutes'), reason: n);
      }
    });

    test('the order of primary_muscles is a contract: every row listing Quads AND Glutes with another muscle first, '
        'and every quad-first row listing Hamstrings, is a KNOWN exception', () {
      const knownNotQuadFirst = {
        'Box Squat', 'Lateral Lunge', 'Sumo Squat', 'Cossack Squat', 'Weighted Cossack Squats', 'Curtsey Squat',
        'Skater Hops',
      };
      const knownHingeQuadFirst = {'Trap Bar Deadlift'};
      final notQuadFirst = <String>{};
      final hingeQuadFirst = <String>{};
      for (final row in byName.values) {
        final m = [for (final x in (row['primary_muscles'] as List? ?? const [])) '$x'];
        if (m.isEmpty) continue;
        final quadFirst = BudgetMuscleGroups.of([m.first]).contains('Quads');
        final glutes = BudgetMuscleGroups.of(m).contains('Glutes');
        final quads = BudgetMuscleGroups.of(m).contains('Quads');
        if (quads && glutes && !quadFirst) notQuadFirst.add(row['name'] as String);
        if (quadFirst && glutes && BudgetMuscleGroups.of(m).contains('Hamstrings')) hingeQuadFirst.add(row['name'] as String);
      }
      expect(notQuadFirst, knownNotQuadFirst,
          reason: 'a new library row lists Quads and Glutes with another muscle first (it keeps its Glutes credit): '
              'decide it on purpose and add it here, or reorder its primary_muscles');
      expect(hingeQuadFirst, knownHingeQuadFirst,
          reason: 'a new quad-first row also lists Hamstrings (a hip hinge that keeps its Glutes credit)');
    });

    test('the context default keeps every other plan\'s credit', () {
      final c = SessionBudgetContext(
        minutes: 60,
        planGoal: 'build_muscle',
        level: 'intermediate',
        lighterPhase: false,
        focusGroups: const {},
        archetypeByName: const {},
      );
      expect(c.quadPrimaryCreditsGlutes, isTrue);
    });
  });

  group('the generated plan', () {
    test('founder case: Quads reach the floor, Glutes and Hamstrings stay in band, in weeks 1 to 3', () {
      final plan = gen('build_muscle', 'full_gym', 6, 'intermediate', 90);
      for (var w = 0; w < 3; w++) {
        final q = fullCredit(plan, w, 'quad');
        expect(q, inInclusiveRange(12, 16), reason: 'week ${w + 1} Quads (band 12 to 16)');
        final g = glutesWithoutQuadFirst(plan, w);
        expect(g, inInclusiveRange(12, 16), reason: 'week ${w + 1} Glutes under the rule (band 12 to 16)');
        expect(fullCredit(plan, w, 'hamstring'), inInclusiveRange(12, 16), reason: 'week ${w + 1} Hamstrings');
      }
      // Legs B holds a quad-first knee exercise it did not hold before.
      final legsB = plan.weekPlans[0].workoutDays.firstWhere((d) => d.name == 'Legs B');
      expect(legsB.exercises.where(kneeQuadFirst), isNotEmpty,
          reason: 'Legs B: ${legsB.exercises.map((e) => e.exerciseName).toList()}');
    });

    test('sweep: 3 levels x 4 tiers x {60, 90} min on the production path (core-list pool OFF)', () {
      final bad = <String>[];
      for (final level in _levels) {
        for (final tier in _tiers) {
          for (final minutes in const [60, 90]) {
            final key = '$level|$tier|$minutes';
            SessionSetAllocator.debugLastStats = null;
            final plan = gen('build_muscle', tier, 6, level, minutes);
            final stats = SessionSetAllocator.debugLastStats!['A']!;
            final (floor, top, cap) = _band[level]!;
            // Quads: at or above the measured figure, and above the old one.
            final q = fullCredit(plan, 0, 'quad');
            if (q < _quadsAfter[key]!) bad.add('$key: Quads $q < measured ${_quadsAfter[key]}');
            if (q <= _quadsBefore[key]!) bad.add('$key: Quads $q is not above the old ${_quadsBefore[key]}');
            // Glutes (credited) keep their floor; Hamstrings never fall below the pre-change figure.
            final g = glutesWithoutQuadFirst(plan, 0);
            if (g < floor) bad.add('$key: credited Glutes $g < floor $floor');
            final h = fullCredit(plan, 0, 'hamstring');
            if (h < _hamstringsBefore[key]!) bad.add('$key: Hamstrings $h < before ${_hamstringsBefore[key]}');
            // The allocator's own label for a Quads shortfall at 90 minutes is the documented one.
            if (minutes == 90) {
              expect(stats.belowFloor['Quads'], _quadsLabel90[key], reason: '$key Quads label');
            }
            // The documented CAUSE of `cap_limited` there: both leg days hold a budgeted quad compound at the
            // per-exercise maximum (the label alone also covers a session cap or a weekly top).
            if (key == 'intermediate|basic_gym|90') {
              final quadCompoundSets = [
                for (final d in plan.weekPlans[0].workoutDays.where((d) => d.name.startsWith('Legs')))
                  for (final e in d.exercises.where(budgeted).where(kneeQuadFirst)) e.sets,
              ];
              expect(quadCompoundSets, isNotEmpty);
              expect(quadCompoundSets.every((n) => n == SessionBudget.maxSetsPerExercise), isTrue,
                  reason: 'quad compound sets $quadCompoundSets, maximum ${SessionBudget.maxSetsPerExercise}');
            }
            // Tops, caps and minutes in all four weeks (credited sense, the rule of this split).
            auditPlan(plan, level, 1, minutes, key, bad);
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('phases 2 to 5 (lighter phase 4, a beginner budgeted as advanced at 5): tops, caps and minutes hold', () {
      final bad = <String>[];
      for (final level in _levels) {
        for (final tier in const ['bodyweight', 'full_gym']) {
          for (var phase = 2; phase <= 5; phase++) {
            final plan = gen('build_muscle', tier, 6, level, 90, phase: phase);
            auditPlan(plan, level, phase, 90, '$level|$tier|90', bad);
            // The slot is still in the plan in every phase that is not the week-4 deload.
            final legsB = plan.weekPlans[0].workoutDays.firstWhere((d) => d.name == 'Legs B');
            if (!legsB.exercises.any(kneeQuadFirst)) {
              bad.add('$level|$tier p$phase: Legs B has no knee_dominant quad-first exercise');
            }
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('a glutes body focus at 6 days: the focus group keeps its cap 12 / top 25 in the credited sense', () {
      final bad = <String>[];
      final plan = gen('build_muscle', 'full_gym', 6, 'intermediate', 90, focus: const ['Glutes']);
      auditPlan(plan, 'intermediate', 1, 90, 'intermediate|full_gym|90|focus Glutes', bad,
          focusGroups: const {'Glutes'});
      expect(bad, isEmpty);
      expect(fullCredit(plan, 0, 'quad'), greaterThanOrEqualTo(12), reason: 'the focus does not take the Quads work back');
    });

    test('recompose plans as build_muscle: the 6-day plan carries the slot and the rule', () {
      final plan = gen('recompose', 'full_gym', 6, 'intermediate', 90);
      expect(SplitResolver.hasQuadLegsBSplit('build_muscle', 6), isTrue);
      expect(fullCredit(plan, 0, 'quad'), greaterThanOrEqualTo(12));
      final legsB = plan.weekPlans[0].workoutDays.firstWhere((d) => d.name == 'Legs B');
      expect(legsB.exercises.any(kneeQuadFirst), isTrue);
    });

    test('a knee-injured 6-day plan: no exercise carries the knee tag and Legs B keeps at least 3 exercises',
        () {
      final plan = PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 6,
        phase: 1,
        experienceLevel: 'intermediate',
        injuries: const ['knee'],
        bodyFocus: const [],
        sessionDuration: 90,
        previousWeights: const {},
      );
      for (var w = 0; w < plan.weekPlans.length; w++) {
        for (final d in plan.weekPlans[w].workoutDays) {
          expect(d.exercises, isNotEmpty, reason: 'week ${w + 1} ${d.name}');
          for (final e in d.exercises) {
            final tags = [for (final t in (byName[e.exerciseName.toLowerCase()]?['injury_contraindications'] as List? ?? const [])) '$t'];
            expect(tags, isNot(contains('knee')), reason: 'week ${w + 1} ${d.name}: ${e.exerciseName}');
          }
        }
      }
      final legsB = plan.weekPlans[0].workoutDays.firstWhere((d) => d.name == 'Legs B');
      expect(legsB.exercises.length, greaterThanOrEqualTo(3), reason: legsB.exercises.map((e) => e.exerciseName).join(', '));
    });

    test('the allocator credits what the rule says: 6-day build_muscle drops the quad-first Glutes credit, '
        'every other plan keeps it', () {
      // [goal, days]: the policy plan first, then controls that must keep full credit.
      for (final (goal, days, policy) in const [
        ('build_muscle', 6, true),
        ('recompose', 6, true),
        ('build_muscle', 5, false),
        ('build_muscle', 4, false),
        ('build_muscle', 3, false),
        ('strength', 6, false),
        ('lose_fat', 6, false),
        ('general_fitness', 6, false),
      ]) {
        SessionSetAllocator.debugLastStats = null;
        final plan = gen(goal, 'full_gym', days, 'intermediate', 90);
        final ledger = SessionSetAllocator.debugLastStats!['A']!.weekly['Glutes'] ?? 0;
        final full = fullCredit(plan, 0, 'glute');
        final ruled = glutesWithoutQuadFirst(plan, 0);
        // Precondition for BOTH arms: the plan holds a quad-first exercise that lists Glutes, so the arms differ.
        final hasQuadFirstWithGlutes = plan.weekPlans[0].workoutDays.any((d) => d.exercises.where(budgeted).any((e) {
              final m = musclesOf(e);
              return m.isNotEmpty && m.first.toLowerCase().contains('quad') && lists(m, 'glute') && !lists(m, 'hamstring');
            }));
        expect(hasQuadFirstWithGlutes, isTrue, reason: '$goal ${days}d: the control needs a squat or lunge in the plan');
        if (policy) {
          expect(ledger, ruled, reason: '$goal ${days}d: the ledger credits Glutes under the rule');
          expect(full, greaterThan(ruled), reason: '$goal ${days}d: squats carry glute work the rule does not count');
        } else {
          expect(ledger, full, reason: '$goal ${days}d: the ledger credits every listed muscle');
          expect(full, greaterThan(ruled), reason: '$goal ${days}d: the rule WOULD have changed this plan');
        }
      }
    });
  });

  group('kill switch disable_quad_legs_b (platform tier feature_flag, default ON)', () {
    Future<void> withSwitch(Future<void> Function() body) async {
      final box = HiveService.instance.configBox;
      await box.put('disable_quad_legs_b', true);
      try {
        await body();
      } finally {
        await box.delete('disable_quad_legs_b');
      }
    }

    test('unset: the new Legs B; the switch is read by PlanEngineFlags and defaults ON', () {
      expect(PlanEngineFlags.quadLegsBEnabled, isTrue);
    });

    test('selectV4(quadLegsB: false) restores the pre-OI-454 Legs B slot list exactly', () {
      final off = SplitResolver.selectV4('build_muscle', 6, quadLegsB: false).firstWhere((d) => d.name == 'Legs B');
      expect(off.slotsA.length, 8);
      expect(off.slotsA.where((s) => s.targetMuscle == 'Quads'), isEmpty);
      expect(off.slotsA.where((s) => s.targetMuscle == 'Glutes' && s.movementPattern == 'hip_isolation' && s.priority == 2),
          hasLength(1));
      // Every other split is untouched by the argument.
      for (final goal in ['lose_fat', 'strength', 'general_fitness', 'build_muscle']) {
        for (final days in [3, 4, 5]) {
          expect(SplitResolver.selectV4(goal, days, quadLegsB: false).map((d) => d.slotsA.length),
              SplitResolver.selectV4(goal, days).map((d) => d.slotsA.length),
              reason: '$goal ${days}d');
        }
      }
    });

    test('switched off, generation returns to the old behaviour: Quads equal the pre-change table in all 24 cells '
        'and the allocator credits Glutes in full', () async {
      await withSwitch(() async {
        expect(PlanEngineFlags.quadLegsBEnabled, isFalse);
        final bad = <String>[];
        for (final level in _levels) {
          for (final tier in _tiers) {
            for (final minutes in const [60, 90]) {
              final key = '$level|$tier|$minutes';
              final plan = gen('build_muscle', tier, 6, level, minutes);
              final q = fullCredit(plan, 0, 'quad');
              if (q != _quadsBefore[key]) bad.add('$key: Quads $q != old ${_quadsBefore[key]}');
            }
          }
        }
        expect(bad, isEmpty);
        SessionSetAllocator.debugLastStats = null;
        final plan = gen('build_muscle', 'full_gym', 6, 'intermediate', 90);
        expect(SessionSetAllocator.debugLastStats!['A']!.weekly['Glutes'], fullCredit(plan, 0, 'glute'),
            reason: 'with the switch off a squat credits Glutes again');
        final legsB = plan.weekPlans[0].workoutDays.firstWhere((d) => d.name == 'Legs B');
        expect(legsB.exercises.where(kneeQuadFirst), isEmpty, reason: 'the old Legs B holds no quad exercise');
      });
    });
  });
}
