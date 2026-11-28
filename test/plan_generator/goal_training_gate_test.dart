// Unit 3A (docs/plans/2026-11-15-generator-step3a-goal-training.md §4, §4b; founder d3, d4, d58-d64): the whole-engine
// gate for training that follows the goal. The real PlanGenerator.instance.generateV4 runs the audit grid (4 goals x 3 /
// 4 / 5 / 6 days x 3 levels x 4 tiers x 30 / 45 / 60 / 90 minutes x phases 1-3: 2,304 plans, no injuries, no history).
// Week 1 of each plan is the week the tables name. OFF (the pre-3A reps, bands, rests and credit) is the frozen baseline
// `test/fixtures/goal_training_gate_baseline.json`, recorded on 421cd2d2 with the 3A kill switch
// set before generator-killswitch-3a3c deleted it (OI-514; plan docs/plans/2026-11-17-generator-killswitch-3a3c.md §1).
//
//  1. Build (build_muscle) and the legacy strength token: every plan equals OFF byte for byte (the baseline's sha256).
//  2. Cut and Maintain (same days / level / tier / minutes / phase) hold different exercises, sets or reps in every
//     profile but the two d63 accepts; OFF they were identical in 92 of 576 (baseline data).
//  3. Main lifts (archetype H / M, d58), Cut and Maintain, week 1: reps = the goal's table clamped into the row's own
//     range (d58: a range that cannot reach the table stops at its bound); deload is not in the grid (phases 1-3).
//  4. Accessories (any other rep-based row with a range), Cut and Maintain, week 1: reps in 10-15 or the row's own
//     range clamped there.
//  5. No group OFF trains in a plan-week (weeks 1-3) is at 0 ON. The grid is uninjured: with an injury a group can
//     reach 0 (founder d66, accepted; measured in diagnose 675d02), and the 4-day Maintain credit books a lunge to
//     Quads only (d67).
//  6. The displayed minutes run no further past the session than OFF's.
//  7. The Strength focus (profile `physique_focus = strength`): no group OFF trains in a plan-week is at 0; every main
//     lift's week-1 reps are its range's low end; its rest is +30 s at 60+ minutes only (d64), every other row's rest
//     is OFF's rule.
//  8. ON byte for byte: the digest of every ON plan's map (no focus) and of every focus plan's map; any change to a
//     real plan turns these red, and the counts above say what kind.
@Timeout(Duration(minutes: 40))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;

typedef _Shape = ({String map, List<Map<String, int>> vol, List<int?> mins});
typedef _Plan = (Phase, _Shape);

const _goals = ['build_muscle', 'lose_fat', 'general_fitness', 'strength'];
const _levels = ['beginner', 'intermediate', 'advanced'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _minutes = [30, 45, 60, 90];
const _groups = ['Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Quads', 'Hamstrings', 'Glutes', 'Calves', 'Core'];

/// d63: the two profiles where Cut and Maintain stay identical (3-day bodyweight, 30 minutes, phase 2: every lift's
/// floor is 8).
const _identicalAccepted = {'3|intermediate|bodyweight|30|2', '3|advanced|bodyweight|30|2'};

/// d81 (generator step 4, 2026-11-16): with the cardio finisher SHOWN (the live world: its switch unset), Cut and
/// Maintain stay identical in these 5 of 576 pairs: d63's two plus three where both get the same finisher. Accepted
/// (t304); measured with the comparison in the live-world test below (plan section 4 item 0).
const _identicalLive = {
  '3|beginner|home_dumbbells|30|1',
  '3|beginner|home_dumbbells|30|2',
  '3|intermediate|bodyweight|30|2',
  '3|advanced|bodyweight|30|2',
  '5|advanced|bodyweight|30|2',
};

/// Item 8, recorded on the built tree (2026-11-15), re-recorded after the step-2E merge (its arm swap changes Cut /
/// Maintain rows at 30 / 45 minutes; every count above is unchanged except the focus block's main lifts, 29,012 -> 29,010),
/// and on 421cd2d2 for generator-killswitch-3a3c (the finisher built unreserved through `CardioFinisher.debugReserve`
/// instead of the deleted 3C key: only the `finisher` maps moved, every count above unchanged; plan §6).
/// Library v30 (OI-443, 2026-11-28; library data only, no plan-engine code change): both digests re-recorded (were 07aa902a... and 56672a99...), week-1 mains
/// at a range bound 3601 -> 3591, and the 88 build / strength hashes in the baseline whose plans moved.
const _onDigest = '0c59a6830288b32e83b987f6fea67a14ab759fb4343b568608895abe3ca4bf79';
const _focusDigest = '9ced009106fd9acb4dddeb37f35656f94ccd121c01b41e6bfaa0743f8d92857b';
const _baselinePath = 'test/fixtures/goal_training_gate_baseline.json';

/// The goal's week-1 main-lift table, restated from the plan (§2) in the oracle's own words: Cut intermediate /
/// advanced 8 (hypertrophy), 6 (strength), 8 (metabolic); Cut beginner and Maintain 10 / 8 / 10.
int _table(String planGoal, String effLevel, int phase) {
  final strengthPhase = phase == 2;
  if (planGoal == 'lose_fat' && effLevel != 'beginner') return strengthPhase ? 6 : 8;
  return strengthPhase ? 8 : 10;
}

(int, int)? _range(Object? r) {
  final m = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$').firstMatch('${r ?? ''}');
  return m == null ? null : (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('goal_training_gate');
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
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    // Unit 3C (diagnose f3c9a6, plan §2.2): this gate measures the goal training (3A), so it runs with the finisher built
    // but its time not reserved, the world the baseline was recorded in. The finisher's own cost is measured by
    // cardio_finisher_reservation_behavioral_test and the diagnose doc.
    CardioFinisher.debugReserve = false;
  });

  tearDownAll(() async {
    CardioFinisher.debugReserve = true;
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Phase gen(String goal, int days, String level, String tier, int minutes, int phase) =>
      PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: const [],
        sessionDuration: minutes,
        previousWeights: const {},
      );

  /// One plan: its map (for the digest), its weekly credited sets per group (weeks 1-3) and its displayed day minutes.
  _Shape shape(Phase plan, String goal, int days, int minutes) {
    final planGoal = FitnessGoals.of(goal).planGoal;
    final quadGlutes =
        SplitResolver.quadPrimaryCreditsGlutes(planGoal, days, minutes, quadLegsB: PlanEngineFlags.quadLegsBEnabled);
    final vol = <Map<String, int>>[];
    final mins = <int?>[];
    for (final w in plan.weekPlans) {
      final v = <String, int>{};
      for (final d in w.workoutDays) {
        for (final e in d.exercises) {
          final row = byName[e.exerciseName.toLowerCase()];
          final tokens = [for (final m in (row?['primary_muscles'] as List? ?? e.primaryMuscles ?? const [])) '$m'];
          for (final g in BudgetMuscleGroups.creditedOf(tokens, quadPrimaryCreditsGlutes: quadGlutes)) {
            v[g] = (v[g] ?? 0) + e.sets;
          }
        }
        mins.add(() {
          try {
            return SessionBudget.estimateDayMinutesFromPlanDay(d.toMap(), const {},
                rowsByName: byName, finisher: const [] /* the lifts' minutes: the finisher's own time is not reserved here */);
          } catch (_) {
            return null;
          }
        }());
      }
      vol.add(v);
    }
    return (map: jsonEncode(plan.toMap()), vol: vol, mins: mins);
  }

  /// The grid in one world. Keys are `goal|days|level|tier|minutes|phase`.
  Future<Map<String, _Plan>> grid({required bool focus}) async {
    await HiveService.instance.userBox.put('profile', {if (focus) 'physique_focus': 'strength'});
    final out = <String, _Plan>{};
    for (final goal in _goals) {
      for (final days in const [3, 4, 5, 6]) {
        for (final level in _levels) {
          for (final tier in _tiers) {
            for (final minutes in _minutes) {
              for (final phase in const [1, 2, 3]) {
                final plan = gen(goal, days, level, tier, minutes, phase);
                out['$goal|$days|$level|$tier|$minutes|$phase'] = (plan, shape(plan, goal, days, minutes));
              }
            }
          }
        }
      }
    }
    await HiveService.instance.userBox.delete('profile');
    return out;
  }

  String sig(Phase p) => jsonEncode([
        for (final w in p.weekPlans)
          [
            for (final d in w.workoutDays) [for (final e in d.exercises) [e.exerciseName, e.sets, e.reps]]
          ]
      ]);

  /// The frozen OFF world (header).
  final baseline = jsonDecode(File(_baselinePath).readAsStringSync()) as Map<String, dynamic>;
  final offBuild = Map<String, String>.from(baseline['build'] as Map);
  final offGroups = {
    for (final e in (baseline['groups'] as Map).entries) e.key as String: List<int>.from(e.value as List),
  };
  final offMaxOver = baseline['maxOver'] as int;

  /// Plan-weeks (1-3) where a group OFF trains (the baseline's bitmask over [_groups]) is at 0 in [world].
  List<String> newlyAtZero(Map<String, _Plan> world) => [
        for (final k in world.keys)
          for (var w = 0; w < 3; w++)
            for (var i = 0; i < _groups.length; i++)
              if (offGroups[k]![w] & (1 << i) != 0 && (world[k]!.$2.vol[w][_groups[i]] ?? 0) == 0)
                '$k week ${w + 1} ${_groups[i]}',
      ];

  int maxOver(Map<String, _Plan> world) {
    var max = -1 << 30;
    for (final e in world.entries) {
      final minutes = int.parse(e.key.split('|')[4]);
      for (final m in e.value.$2.mins) {
        if (m != null && m - minutes > max) max = m - minutes;
      }
    }
    return max;
  }

  String digest(Map<String, _Plan> world) =>
      sha256Hex(utf8.encode([for (final k in world.keys) '$k:${sha256Hex(utf8.encode(world[k]!.$2.map))}']
          .join('\n')));

  test('the baseline covers the grid', () {
    expect(offGroups.length, 2304);
    expect(offBuild.length, 1152);
    expect(offBuild.keys.every((k) => k.startsWith('build_muscle|') || k.startsWith('strength|')), isTrue);
    expect(offMaxOver, 6);
    // Item 2's OFF count, kept as data (measured 2026-11-15 and again on 421cd2d2).
    expect(baseline['identicalOff'], 92);
  });

  test('the 2,304-plan grid against the OFF baseline', () async {
    final on = await grid(focus: false);
    expect(on.keys.toSet(), offGroups.keys.toSet());

    // 1. Build and the legacy strength token.
    final buildChanged = [
      for (final k in on.keys)
        if ((k.startsWith('build_muscle|') || k.startsWith('strength|')) &&
            sha256Hex(utf8.encode(on[k]!.$2.map)) != offBuild[k])
          k,
    ];

    // 2. Cut against Maintain.
    Set<String> identical(Map<String, _Plan> world) => {
          for (final k in world.keys)
            if (k.startsWith('lose_fat|'))
              if (sig(world[k]!.$1) == sig(world['general_fitness|${k.substring(9)}']!.$1))
                k.substring(9),
        };

    // 3-4. Week-1 reps.
    var mains = 0, mainsAtBound = 0, accessories = 0;
    final repMiss = <String>[];
    for (final k in on.keys) {
      final parts = k.split('|');
      final planGoal = FitnessGoals.of(parts[0]).planGoal;
      if (planGoal != 'lose_fat' && planGoal != 'general_fitness') continue;
      final phase = int.parse(parts[5]);
      final effLevel = PlanGenerator.effectiveLevel(parts[2], phase);
      for (final d in on[k]!.$1.weekPlans.first.workoutDays) {
        for (final e in d.exercises) {
          final row = byName[e.exerciseName.toLowerCase()];
          final r = int.tryParse(e.reps);
          final range = _range(row?['rep_range']);
          if (row == null || r == null || range == null || !SessionBudget.isRepBased(e.loggingType)) continue;
          final arch = SessionBudget.archetypeOfRow(row);
          if (arch == 'H' || arch == 'M') {
            mains++;
            final t = _table(planGoal, effLevel, phase);
            final want = t.clamp(range.$1, range.$2);
            if (want != t) mainsAtBound++;
            if (r != want) repMiss.add('$k ${e.exerciseName} main $r want $want');
          } else {
            accessories++;
            final lo = range.$1.clamp(10, 15), hi = range.$2.clamp(10, 15);
            if (r < lo || r > hi) repMiss.add('$k ${e.exerciseName} accessory $r range $range');
          }
        }
      }
    }

    final zeros = newlyAtZero(on);
    final onDigest = digest(on);
    // ignore: avoid_print
    print('goal training gate: build changed ${buildChanged.length}; identical ON ${identical(on)}; mains $mains (at '
        'bound $mainsAtBound), accessories $accessories, misses ${repMiss.length} ${repMiss.take(5).toList()}; newly at '
        '0 ${zeros.length} ${zeros.take(5).toList()}; max over OFF $offMaxOver ON ${maxOver(on)}; ON digest $onDigest');

    expect(buildChanged, isEmpty, reason: 'Build and the legacy strength token keep today\'s plan');
    expect(identical(on), _identicalAccepted, reason: 'd63');
    expect(repMiss, isEmpty);
    // Measured 2026-11-15: week-1 main lifts, those at a range bound (d58), accessories (Cut and Maintain).
    expect((mains, mainsAtBound, accessories), (14547, 3591, 12360));
    expect(zeros, isEmpty);
    expect(maxOver(on), lessThanOrEqualTo(offMaxOver));
    expect(onDigest, _onDigest);
  });

  test('the Strength focus (d4, d60, d64)', () async {
    final focus = await grid(focus: true);

    var mains = 0;
    final miss = <String>[];
    for (final k in focus.keys) {
      final parts = k.split('|');
      final minutes = int.parse(parts[4]);
      for (final d in focus[k]!.$1.weekPlans.first.workoutDays) {
        for (final e in d.exercises) {
          final row = byName[e.exerciseName.toLowerCase()];
          if (row == null || !SessionBudget.isRepBased(e.loggingType)) continue;
          final arch = SessionBudget.archetypeOfRow(row);
          final main = arch == 'H' || arch == 'M';
          final base = SessionBudget.restForArchetype(arch);
          final wantRest = main && minutes >= 60 ? base + 30 : base;
          if (e.restSeconds != wantRest) miss.add('$k ${e.exerciseName} rest ${e.restSeconds} want $wantRest');
          final range = _range(row['rep_range']);
          final r = int.tryParse(e.reps);
          if (main && range != null && r != null) {
            mains++;
            if (r != range.$1) miss.add('$k ${e.exerciseName} reps $r want ${range.$1}');
          }
        }
      }
    }
    final zeros = newlyAtZero(focus);
    final focusDigest = digest(focus);
    // ignore: avoid_print
    print('goal training gate, focus: mains $mains, misses ${miss.length} ${miss.take(5).toList()}; newly at 0 '
        '${zeros.length} ${zeros.take(5).toList()}; max over ${maxOver(focus)}; digest $focusDigest');
    expect(miss, isEmpty);
    expect(mains, 29010, reason: 'week-1 main lifts with a range, every goal (measured 2026-11-15, on the 2E tree)');
    expect(zeros, isEmpty, reason: 'd64: +30 s only at 60+ minutes, where it costs no group');
    expect(maxOver(focus), lessThanOrEqualTo(offMaxOver));
    expect(focusDigest, _focusDigest);
  });

  test('d81: the live world (finisher shown): Cut and Maintain identical in exactly the accepted 5 pairs', () async {
    CardioFinisher.debugReserve = true;
    try {
      // t304's comparison: every day of every week, each exercise's name, sets, reps, rest, duration, superset group
      // and type, plus the day's finisher names.
      String live(Phase p) => jsonEncode([
            for (final w in p.weekPlans)
              [
                for (final d in w.workoutDays)
                  [
                    [
                      for (final e in d.exercises)
                        [e.exerciseName, e.sets, e.reps, e.restSeconds, e.durationSeconds, e.supersetGroup, e.exerciseType]
                    ],
                    [for (final f in d.finisher) f.exerciseName],
                  ]
              ]
          ]);
      final same = <String>{};
      var pairs = 0;
      for (final days in const [3, 4, 5, 6]) {
        for (final level in _levels) {
          for (final tier in _tiers) {
            for (final minutes in _minutes) {
              for (final phase in const [1, 2, 3]) {
                pairs++;
                final cut = live(gen('lose_fat', days, level, tier, minutes, phase));
                final maintain = live(gen('general_fitness', days, level, tier, minutes, phase));
                if (cut == maintain) same.add('$days|$level|$tier|$minutes|$phase');
              }
            }
          }
        }
      }
      expect(pairs, 576);
      expect(same, _identicalLive, reason: 'd81');
    } finally {
      CardioFinisher.debugReserve = false;
    }
  });
}
