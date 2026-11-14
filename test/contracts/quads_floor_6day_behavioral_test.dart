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
// The sweep also pins, on the PRODUCTION path (the core-list pool, the only picker since Unit 1B-F; the tables were
// first measured on the deleted cascade and carry per-cell overrides measured at the flip): every group's credited weekly total under its top and its session total under its
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
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../helpers/budget_invariant_oracle.dart';

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

// Batch C2c (OI-474): E230 Standing Single Leg Curl became a bodyweight row, so in bodyweight and home plans it now
// fills the Hamstrings / knee_dominant / isolation slot that a lunge variant (crediting Quads and Glutes) filled
// before. Measured on the merged tree, 6-day build_muscle, week 1: Hamstrings rise 2 to 5 sets in 11 cells (for example 8 to 12 in
// intermediate|bodyweight|90, floor 12; 7 to 12 in advanced|bodyweight|90, floor 14) and Quads fall by 1 to 3 sets in the cells below. These tables
// OVERRIDE the OI-454 ones cell by cell (the OI-454 figures above stay as recorded); every other cell is unchanged.
// A cell here that equals the OI-454 figure is a dead override, pinned by the last test of this file.

/// `_quadsAfter` overrides (the Quads figure with the OI-454 lever ON).
const _quadsAfterC2c = <String, int>{
  'beginner|bodyweight|60': 9, 'beginner|home_dumbbells|60': 9,
  'intermediate|bodyweight|60': 7, 'intermediate|bodyweight|90': 10,
  'intermediate|home_dumbbells|60': 7, 'intermediate|home_dumbbells|90': 10,
  'advanced|bodyweight|60': 6, 'advanced|bodyweight|90': 10,
  'advanced|home_dumbbells|60': 6, 'advanced|home_dumbbells|90': 10,
};

/// `_quadsBefore` overrides (the Quads figure with the lever switched OFF: the old Legs B, the library as it is now).
const _quadsOffC2c = <String, int>{
  'intermediate|bodyweight|60': 3, 'intermediate|bodyweight|90': 3,
  'intermediate|home_dumbbells|60': 3, 'intermediate|home_dumbbells|90': 3,
  'advanced|bodyweight|60': 3, 'advanced|bodyweight|90': 3,
  'advanced|home_dumbbells|60': 3, 'advanced|home_dumbbells|90': 3,
};

/// `_quadsLabel90` overrides. Two cells that reached their floor now stop short on the per-exercise cap; two that
/// stopped short for another reason now stop on the cap.
const _quadsLabel90C2c = <String, String>{
  'intermediate|bodyweight|90': 'cap_limited',
  'intermediate|home_dumbbells|90': 'cap_limited',
  'advanced|bodyweight|90': 'cap_limited',
  'advanced|home_dumbbells|90': 'cap_limited',
};

// Unit 1B-F (docs/plans/2026-11-10-generator-1bf-flip.md, 2026-11-11): the core-list pool became the only picker, so the
// production path these tables pin moved from the deleted cascade to the core path. Measured on the flipped tree (week 1,
// 6-day build_muscle, a probe over the same 24 cells); each table below OVERRIDES the ones above cell by cell, and a cell
// equal to what it replaces is a dead override (the last test). With the lever ON, Quads rise in all 13 changed cells
// (for example advanced|basic_gym|60 5 to 8); the switched-off figures are the old Legs B on the core path. Hamstrings
// fall below the pre-OI-454 cascade figure in six gym cells (intermediate basic_gym / full_gym 60: 11 to 9; advanced
// basic_gym 60: 12 to 8, 90: 13 to 12; advanced full_gym 60: 12 to 8, 90: 13 to 11): the flip's own trade against the
// cascade's picks (the flipped tree equals the pre-flip pool-ON world on the golden personas), named in the 1B-F diagnose
// doc; no cell reaches 0. At 90 minutes no Quads shortfall is `cap_limited` any more (the core path's quad compounds
// stop short of the per-exercise maximum), so the cap-cause check below has no cell to read and is kept for a later one.

/// `_quadsAfter` overrides at the flip (core path, lever ON).
const _quadsAfter1BF = <String, int>{
  'intermediate|bodyweight|60': 10, 'intermediate|bodyweight|90': 12,
  'intermediate|home_dumbbells|60': 9, 'intermediate|home_dumbbells|90': 12,
  'intermediate|basic_gym|60': 9, 'intermediate|basic_gym|90': 12,
  'advanced|bodyweight|60': 7, 'advanced|bodyweight|90': 13,
  'advanced|home_dumbbells|60': 7, 'advanced|home_dumbbells|90': 12,
  'advanced|basic_gym|60': 8, 'advanced|basic_gym|90': 11,
  'advanced|full_gym|60': 9,
};

/// `_quadsBefore` overrides at the flip (core path, lever switched OFF).
const _quadsOff1BF = <String, int>{
  'intermediate|bodyweight|60': 4, 'intermediate|bodyweight|90': 4,
  'intermediate|home_dumbbells|60': 4, 'intermediate|home_dumbbells|90': 4,
  'intermediate|basic_gym|60': 4, 'intermediate|basic_gym|90': 4,
  'advanced|bodyweight|60': 5, 'advanced|bodyweight|90': 5,
  'advanced|home_dumbbells|60': 4, 'advanced|home_dumbbells|90': 4,
  'advanced|basic_gym|60': 5, 'advanced|basic_gym|90': 8,
};

/// `_hamstringsBefore` overrides at the flip: the six gym cells the core path holds below the cascade figure.
const _hamstrings1BF = <String, int>{
  'intermediate|basic_gym|60': 9, 'intermediate|full_gym|60': 9,
  'advanced|basic_gym|60': 8, 'advanced|basic_gym|90': 12,
  'advanced|full_gym|60': 8, 'advanced|full_gym|90': 11,
};

/// The one cell whose credited Glutes sit below the level floor at the flip (advanced floor 14), an EXACT ratchet:
/// advanced|basic_gym|60 holds 12. It is the pre-flip pool-ON plan (golden key grid|basic_gym|build_muscle|6d|advanced|p1,
/// equal before and after the flip); a below-band week is the class step 2's weekly floor owns (founder d14 / d20).
const _glutesBelowFloor1BF = <String, int>{'advanced|basic_gym|60': 12};

/// `_quadsLabel90` overrides at the flip; `null` = the cell reaches its floor.
const _quadsLabel90_1BF = <String, String?>{
  'intermediate|bodyweight|90': null,
  'intermediate|home_dumbbells|90': null,
  'intermediate|basic_gym|90': null,
  'advanced|bodyweight|90': 'time_limited',
  'advanced|home_dumbbells|90': 'time_limited',
};

int _quadsAfterBeforeFlip(String key) => _quadsAfterC2c[key] ?? _quadsAfter[key]!;
int _quadsOffBeforeFlip(String key) => _quadsOffC2c[key] ?? _quadsBefore[key]!;
String? _label90BeforeFlip(String key) => _quadsLabel90C2c[key] ?? _quadsLabel90[key];

// Unit 2A (OI-486, docs/plans/2026-11-12-generator-step2-allocator.md, 2026-11-13): the lead-first allocator. Measured
// on the 2A tree over the same 24 cells; each table below OVERRIDES the 1B-F ones cell by cell (a cell equal to what it
// replaces is a dead override, the last test). With the lever ON, Quads fall in four beginner cells and rise in none:
// the leg days open with a bilateral hinge (Bodyweight Good Morning on bodyweight), the sequencer's opener, at 3 sets,
// so R2 holds each unilateral quad compound at the lead + 1 = 4 instead of 5 (bodyweight 60: 9 to 8, 90: 10 to 8;
// home_dumbbells and basic_gym 90: 10 to 9). The three 90-minute cells read `cap_limited` (R2 has no `_Why` of its
// own, plan section 5), and the cap-cause check below accepts the R2 hold as that cause. Weekly minimums are unit 2C's
// (OI-501). Switched off, the old Legs B moves in 16 cells (the lead at 3 changes what time is left).

/// `_quadsAfter` overrides at 2A (lever ON).
const _quadsAfter2A = <String, int>{
  'beginner|bodyweight|60': 8, 'beginner|bodyweight|90': 8,
  'beginner|home_dumbbells|90': 9, 'beginner|basic_gym|90': 9,
};

/// `_quadsBefore` overrides at 2A (lever switched OFF).
const _quadsOff2A = <String, int>{
  'beginner|bodyweight|60': 3, 'beginner|bodyweight|90': 3,
  'beginner|home_dumbbells|60': 3, 'beginner|home_dumbbells|90': 3,
  'beginner|basic_gym|60': 3, 'beginner|basic_gym|90': 3,
  'intermediate|bodyweight|60': 5, 'intermediate|bodyweight|90': 5,
  'intermediate|home_dumbbells|60': 5, 'intermediate|home_dumbbells|90': 5,
  'intermediate|basic_gym|60': 5, 'intermediate|basic_gym|90': 5,
  'intermediate|full_gym|90': 7,
  'advanced|home_dumbbells|60': 5, 'advanced|home_dumbbells|90': 5,
  'advanced|full_gym|90': 7,
};

/// `_quadsLabel90` overrides at 2A.
const _quadsLabel90_2A = <String, String?>{
  'beginner|bodyweight|90': 'cap_limited',
  'beginner|home_dumbbells|90': 'cap_limited',
  'beginner|basic_gym|90': 'cap_limited',
};

int _quadsAfterBefore2A(String key) => _quadsAfter1BF[key] ?? _quadsAfterBeforeFlip(key);
int _quadsOffBefore2A(String key) => _quadsOff1BF[key] ?? _quadsOffBeforeFlip(key);
String? _label90Before2A(String key) =>
    _quadsLabel90_1BF.containsKey(key) ? _quadsLabel90_1BF[key] : _label90BeforeFlip(key);

int _quadsAfterFor(String key) => _quadsAfter2A[key] ?? _quadsAfterBefore2A(key);
int _quadsOffFor(String key) => _quadsOff2A[key] ?? _quadsOffBefore2A(key);
int _hamstringsFor(String key) => _hamstrings1BF[key] ?? _hamstringsBefore[key]!;
String? _label90For(String key) =>
    _quadsLabel90_2A.containsKey(key) ? _quadsLabel90_2A[key] : _label90Before2A(key);

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

  /// Unit 2B: the allocator stats of each generated plan, so `auditPlan` reads the shared oracle's floor allowances.
  final statsOf = Expando<Map<String, AllocationStats>>('allocator stats');
  Phase gen(String goal, String tier, int days, String level, int minutes,
      {int phase = 1, List<String> focus = const []}) {
    SessionSetAllocator.debugLastStats = null;
    final plan = PlanGenerator.instance.generateV4(
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
    final stats = SessionSetAllocator.debugLastStats;
    if (stats != null) statsOf[plan] = stats;
    return plan;
  }

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
      // Unit 2B (the shared oracle, `budget_invariant_oracle.dart`): this week's variant (6-day: A only).
      final vStats = statsOf[plan]?[w == 1 || w == 3 ? 'B' : 'A'] ?? statsOf[plan]?['A'];
      final days = plan.weekPlans[w].workoutDays;
      for (var di = 0; di < days.length; di++) {
        final d = days[di];
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
        final floorClock = BudgetInvariantOracle.floorOverClockSeconds(vStats, di);
        if (secs > (minutes + 2) * 60 + floorClock) {
          bad.add('$key p$phase w${w + 1} ${d.name}: ${(secs / 60).toStringAsFixed(1)} min > ${minutes + 2}');
        }
      }
      weekly.forEach((grp, n) {
        final ceiling = BudgetInvariantOracle.weekCeiling(top(grp), vStats, grp);
        if (n > ceiling) bad.add('$key p$phase w${w + 1}: $grp $n > weekly top ${top(grp)} (+ floor: $ceiling)');
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
        // Library Batch S1b-2: the loaded versions copy their original's primary_muscles (N14 of Sumo Squat, N17 of
        // Lateral Lunge), so they keep the same Glutes credit on purpose.
        'Dumbbell Sumo Squat', 'Dumbbell Lateral Lunge',
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

    test('sweep: 3 levels x 4 tiers x {60, 90} min on the production path (the core-list pool)', () {
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
            if (q < _quadsAfterFor(key)) bad.add('$key: Quads $q < measured ${_quadsAfterFor(key)}');
            if (q <= _quadsBefore[key]!) bad.add('$key: Quads $q is not above the old ${_quadsBefore[key]}');
            // Glutes (credited) keep their floor; Hamstrings never fall below the pre-change figure.
            final g = glutesWithoutQuadFirst(plan, 0);
            final gExc = _glutesBelowFloor1BF[key];
            if (gExc != null) {
              if (g != gExc) bad.add('$key: credited Glutes $g != recorded $gExc (Unit 1B-F exception)');
            } else if (g < floor) {
              bad.add('$key: credited Glutes $g < floor $floor');
            }
            final h = fullCredit(plan, 0, 'hamstring');
            if (h < _hamstringsFor(key)) bad.add('$key: Hamstrings $h < recorded ${_hamstringsFor(key)}');
            // The allocator's own label for a Quads shortfall at 90 minutes is the documented one.
            if (minutes == 90) {
              expect(stats.belowFloor['Quads'], _label90For(key), reason: '$key Quads label');
            }
            // The documented CAUSE of `cap_limited` there: every budgeted quad compound on the leg days is held, at
            // the per-exercise maximum or (Unit 2A, R2) at its day's lead + 1, the lead being the sequencer's opener of
            // the day's budgeted rows (the label alone also covers a session cap or a weekly top).
            if (minutes == 90 && _label90For(key) == 'cap_limited') {
              final held = <(int, int)>[
                for (final d in plan.weekPlans[0].workoutDays.where((d) => d.name.startsWith('Legs')))
                  for (final e in d.exercises.where(budgeted).where(kneeQuadFirst))
                    (e.sets, SequencingEngine.openerOf(d.exercises.where(budgeted).toList())!.sets),
              ];
              expect(held, isNotEmpty);
              expect(held.every((h) => h.$1 == SessionBudget.maxSetsPerExercise || h.$1 == h.$2 + 1), isTrue,
                  reason: '$key: (quad compound sets, lead sets) $held, maximum ${SessionBudget.maxSetsPerExercise}');
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

    test('the allocator credits what the rule says: 6-day build_muscle, and 3 / 4 / 5-day build_muscle at 60+ minutes '
        '(Unit 2C-a), drop the quad-first Glutes credit; every other plan keeps it', () {
      // [goal, days, minutes]: the policy plans first, then controls that must keep full credit.
      for (final (goal, days, minutes, policy) in const [
        ('build_muscle', 6, 90, true),
        ('recompose', 6, 90, true),
        // Unit 2C-a (S2, founder d35): the balanced week's credit.
        ('build_muscle', 5, 90, true),
        ('build_muscle', 4, 90, true),
        ('build_muscle', 3, 90, true),
        ('build_muscle', 4, 60, true),
        // Below 60 minutes the 3 / 4 / 5-day plans keep today's lists and credit.
        ('build_muscle', 5, 45, false),
        ('build_muscle', 4, 45, false),
        ('build_muscle', 3, 45, false),
        ('strength', 6, 90, false),
        ('lose_fat', 6, 90, false),
        ('general_fitness', 6, 90, false),
      ]) {
        SessionSetAllocator.debugLastStats = null;
        final plan = gen(goal, 'full_gym', days, 'intermediate', minutes);
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
          expect(ledger, ruled, reason: '$goal ${days}d ${minutes}m: the ledger credits Glutes under the rule');
          expect(full, greaterThan(ruled), reason: '$goal ${days}d: squats carry glute work the rule does not count');
        } else {
          expect(ledger, full, reason: '$goal ${days}d ${minutes}m: the ledger credits every listed muscle');
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
              if (q != _quadsOffFor(key)) bad.add('$key: Quads $q != old ${_quadsOffFor(key)}');
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

  test('the C2c overrides are live: each names a real cell and differs from the OI-454 figure it replaces', () {
    for (final e in _quadsAfterC2c.entries) {
      expect(_quadsAfter.containsKey(e.key), isTrue, reason: 'after: ${e.key} is not a cell');
      expect(e.value, isNot(_quadsAfter[e.key]), reason: 'after: ${e.key} equals the OI-454 figure (a dead override)');
    }
    for (final e in _quadsOffC2c.entries) {
      expect(_quadsBefore.containsKey(e.key), isTrue, reason: 'off: ${e.key} is not a cell');
      expect(e.value, isNot(_quadsBefore[e.key]), reason: 'off: ${e.key} equals the OI-454 figure (a dead override)');
    }
    for (final e in _quadsLabel90C2c.entries) {
      expect(e.key.endsWith('|90') && _quadsAfter.containsKey(e.key), isTrue,
          reason: 'label: ${e.key} is not a real 90-minute cell');
      expect(e.value, isNot(_quadsLabel90[e.key]), reason: 'label: ${e.key} equals the OI-454 label (a dead override)');
    }
    for (final e in _quadsAfter2A.entries) {
      expect(e.value, isNot(_quadsAfterBefore2A(e.key)), reason: 'after (2A): ${e.key} is a dead override');
    }
    for (final e in _quadsOff2A.entries) {
      expect(e.value, isNot(_quadsOffBefore2A(e.key)), reason: 'off (2A): ${e.key} is a dead override');
    }
    for (final e in _quadsLabel90_2A.entries) {
      expect(e.key.endsWith('|90') && _quadsAfter.containsKey(e.key), isTrue,
          reason: 'label (2A): ${e.key} is not a real 90-minute cell');
      expect(e.value, isNot(_label90Before2A(e.key)), reason: 'label (2A): ${e.key} is a dead override');
    }
    for (final e in _quadsAfter1BF.entries) {
      expect(e.value, isNot(_quadsAfterBeforeFlip(e.key)), reason: 'after (1B-F): ${e.key} is a dead override');
    }
    for (final e in _quadsOff1BF.entries) {
      expect(e.value, isNot(_quadsOffBeforeFlip(e.key)), reason: 'off (1B-F): ${e.key} is a dead override');
    }
    for (final e in _hamstrings1BF.entries) {
      expect(_hamstringsBefore.containsKey(e.key), isTrue, reason: 'hamstrings (1B-F): ${e.key} is not a cell');
      expect(e.value, isNot(_hamstringsBefore[e.key]), reason: 'hamstrings (1B-F): ${e.key} is a dead override');
    }
    for (final e in _glutesBelowFloor1BF.entries) {
      expect(_quadsAfter.containsKey(e.key), isTrue, reason: 'glutes (1B-F): ${e.key} is not a cell');
      expect(e.value, lessThan(_band[e.key.split('|').first]!.$1), reason: 'glutes (1B-F): ${e.key} is not below its floor');
    }
    for (final e in _quadsLabel90_1BF.entries) {
      expect(e.key.endsWith('|90') && _quadsAfter.containsKey(e.key), isTrue, reason: 'label (1B-F): ${e.key}');
      expect(e.value, isNot(_label90BeforeFlip(e.key)), reason: 'label (1B-F): ${e.key} is a dead override');
    }
  });
}
