// Unit 2C-b (docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md §5, founder d35-d49): the whole-engine gate
// for the weekly minimum and the under-60 allowance. The real PlanGenerator.instance.generateV4 runs the audit grid at
// 30 and 45 minutes (4 goals x 3 / 4 / 5 / 6 days x 3 levels x 4 tiers x phases 1-3: 1,152 plans, no injuries, no
// history) with 2C's kill switch `disable_balanced_week` unset (ON) and set (OFF: below 60 minutes 2C-a never acts, so
// OFF is the pre-2C-b tree). Every expected value was computed from the measurement dumps before this gate was run
// (the chosen prototype run b25 against merged main de30a0a7, both 30 / 45 restricted; plan §4.1, §7 option (a)), and
// the built allocator reproduces b25's 2,304-plan dump byte for byte.
//
//  1. Verdicts (the audit lib, its over-time bound at +6 under 60, d47): ON 657 suitable / 495 needs_work / 0 not_suitable;
//     OFF 578 / 546 / 28 (the 28 Shoulders-zero lose_fat / general_fitness plans, fixed by the swap design).
//  2. No plan gains a major issue code against OFF.
//  3. A group OFF trains in a plan-week (1-3) is never at 0 ON, except Calves at 30 minutes (d45): exactly 143.
//  4. Every day holds exactly OFF's rows, all four weeks (d44: the allowance adds sets, never an exercise).
//  5. (plan, group) pairs with a zero week among weeks 1-3: ON 49 (Calves; Unit 2E closed Biceps 13 and Triceps 9 on
//     2026-11-15), OFF 132.
//  6. The displayed minutes run at most 6 past the session's (the allowance, d47).
//  7. The allowance stamp: false on exactly the two fallback plans (`build_muscle|3|advanced|bodyweight|30|{2,3}`,
//     the B-7 persona), whose whole plan equals OFF (the fallback is R verbatim, week 2 included); true on the rest.
//  8. 2A off and 2B off (`disable_lead_first` / `disable_day_floor` set): the switch changes nothing (a 48-plan
//     30-minute subset, digests compared).
//  9. ON byte for byte: the digest of every ON plan's phase map equals the built tree's, recorded 2026-11-14 when that
//     tree's 2,304-plan dump equalled the chosen prototype run b25 byte for byte. Any change to a real 30 / 45-minute
//     plan turns this red; the counts above say what kind.
@Timeout(Duration(minutes: 30))
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
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import 'plan_audit/plan_audit_lib.dart';

const _goals = ['build_muscle', 'lose_fat', 'general_fitness', 'strength'];
const _levels = ['beginner', 'intermediate', 'advanced'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _groups = ['Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Quads', 'Hamstrings', 'Glutes', 'Calves', 'Core'];
/// Item 9: the ON grid's digest on the built tree (2026-11-14), re-recorded 2026-11-15 for Unit 2E (its block below
/// says what changed: exactly the 21 arm-residue plans), and for Unit 3A (the goal's Cut / Maintain reps and bands;
/// with the goal training off everywhere 2E's 794121ba... measured back exactly).
const _onDigest = '1c37a806d719674bd23e44de450d51a80ca81b9fc9686430f95e3e2ae8ee42bc';

const _fallback = {'build_muscle|3|advanced|bodyweight|30|2', 'build_muscle|3|advanced|bodyweight|30|3'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName, byId, byExactName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('weekly_minimum_gate');
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
    byExactName = {for (final r in rows) r['name'] as String: r};
    byId = {for (final r in rows) (r['id'] ?? r['name']).toString(): r};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    // Unit 3C (diagnose f3c9a6, plan §2.2): this gate measures the weekly minimum (2C-b), so every world runs with the
    // cardio finisher switch set (today's finisher, nothing reserved, none shown).
    await HiveService.instance.configBox.put('disable_cardio_finisher_shown', true);
  });

  tearDownAll(() async {
    final config = HiveService.instance.configBox;
    for (final k in const ['disable_balanced_week', 'disable_lead_first', 'disable_day_floor', 'disable_cardio_finisher_shown']) {
      await config.delete(k);
    }
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

  /// The plan in the audit's dump shape (plan_audit_dump_test.dart's `dumpOne`, without the exercise header map).
  Map<String, dynamic> dumpOf(Phase plan, String goal, int days, String level, String tier, int minutes, int phase) {
    final planGoal = FitnessGoals.of(goal).planGoal;
    final effLevel = PlanGenerator.effectiveLevel(level, phase);
    final quadGlutes = SplitResolver.quadPrimaryCreditsGlutes(planGoal, days, minutes,
        quadLegsB: PlanEngineFlags.quadLegsBEnabled);
    final band = SessionBudget.weeklyBand(planGoal, effLevel);
    return {
      'k': '$goal|$days|$level|$tier|$minutes|$phase',
      'pn': plan.name,
      'pg': planGoal,
      'el': effLevel,
      'b': [band.bottom, band.top],
      'w': [
        for (final w in plan.weekPlans)
          () {
            final vol = <String, int>{};
            final dayList = [
              for (final d in w.workoutDays)
                {
                  'n': d.name,
                  'f': d.focus,
                  'x': [
                    for (final e in d.exercises)
                      () {
                        final row = byName[e.exerciseName.toLowerCase()];
                        final tokens = [
                          for (final m in (row?['primary_muscles'] as List? ?? e.primaryMuscles ?? const [])) '$m'
                        ];
                        final groups = BudgetMuscleGroups.creditedOf(tokens, quadPrimaryCreditsGlutes: quadGlutes);
                        for (final g in groups) {
                          vol[g] = (vol[g] ?? 0) + e.sets;
                        }
                        return [e.exerciseName, e.sets, e.reps, e.restSeconds, e.durationSeconds, e.supersetGroup,
                            groups.toList(), e.exerciseType];
                      }(),
                  ],
                  'min': () {
                    try {
                      return SessionBudget.estimateDayMinutesFromPlanDay(d.toMap(), byId,
                          rowsByName: byName, finisher: const [] /* the finisher switch is set: no screen shows one */);
                    } catch (_) {
                      return null;
                    }
                  }(),
                },
            ];
            return {'c': w.weekCharacter, 'd': dayList, 'v': vol};
          }(),
      ],
    };
  }

  test('the 30 / 45-minute grid, ON against OFF (1,152 plans each)', () async {
    final config = HiveService.instance.configBox;
    final auditor = PlanAuditor(byExactName);
    final on = <String, Map<String, dynamic>>{}, off = <String, Map<String, dynamic>>{};
    final onMap = <String, String>{}, offMap = <String, String>{};
    final stampFalse = <String>{};
    for (final world in const ['on', 'off']) {
      if (world == 'off') {
        await config.put('disable_balanced_week', true);
      } else {
        await config.delete('disable_balanced_week');
      }
      for (final goal in _goals) {
        for (final days in const [3, 4, 5, 6]) {
          for (final level in _levels) {
            for (final tier in _tiers) {
              for (final minutes in const [30, 45]) {
                for (final phase in const [1, 2, 3]) {
                  SessionSetAllocator.debugLastAllowance = null;
                  final plan = gen(goal, days, level, tier, minutes, phase);
                  final d = dumpOf(plan, goal, days, level, tier, minutes, phase);
                  final key = d['k'] as String;
                  (world == 'on' ? on : off)[key] = d;
                  (world == 'on' ? onMap : offMap)[key] = jsonEncode(plan.toMap());
                  if (world == 'on' && SessionSetAllocator.debugLastAllowance != true) stampFalse.add(key);
                  if (world == 'off') expect(SessionSetAllocator.debugLastAllowance, isFalse, reason: key);
                }
              }
            }
          }
        }
      }
    }
    await config.delete('disable_balanced_week');

    // 1-2. Verdicts and majors.
    final rOn = {for (final e in on.entries) e.key: auditor.audit(e.value)};
    final rOff = {for (final e in off.entries) e.key: auditor.audit(e.value)};
    Map<String, int> verdicts(Map<String, PlanAuditResult> r) {
      final c = <String, int>{};
      for (final x in r.values) {
        c[x.verdict] = (c[x.verdict] ?? 0) + 1;
      }
      return c;
    }

    final newMajor = [
      for (final k in rOn.keys)
        if (!{for (final i in rOff[k]!.issues) if (i.severity == 'major') i.code}
            .containsAll({for (final i in rOn[k]!.issues) if (i.severity == 'major') i.code}))
          k,
    ];

    // 3-6. Groups at 0, rows, zero weeks, minutes.
    var newlyCalves30 = 0;
    final newlyOther = <String>[];
    final rowDiff = <String>[];
    final zeroOn = <String, int>{}, zeroOff = <String, int>{};
    var maxOver = 0;
    for (final k in on.keys) {
      final minutes = int.parse(k.split('|')[4]);
      final wOn = on[k]!['w'] as List, wOff = off[k]!['w'] as List;
      for (var w = 0; w < wOn.length; w++) {
        final vOn = (wOn[w] as Map)['v'] as Map<String, int>, vOff = (wOff[w] as Map)['v'] as Map<String, int>;
        if (w < 3) {
          for (final g in _groups) {
            if ((vOff[g] ?? 0) > 0 && (vOn[g] ?? 0) == 0) {
              if (g == 'Calves' && minutes == 30) {
                newlyCalves30++;
              } else {
                newlyOther.add('$k week ${w + 1} $g');
              }
            }
          }
        }
        final dOn = (wOn[w] as Map)['d'] as List, dOff = (wOff[w] as Map)['d'] as List;
        for (var i = 0; i < dOn.length; i++) {
          if (((dOn[i] as Map)['x'] as List).length != ((dOff[i] as Map)['x'] as List).length) {
            rowDiff.add('$k week ${w + 1} day $i');
          }
          final mins = (dOn[i] as Map)['min'] as int?;
          if (mins != null && mins - minutes > maxOver) maxOver = mins - minutes;
        }
      }
      for (final (dump, zero) in [(wOn, zeroOn), (wOff, zeroOff)]) {
        for (final g in _groups) {
          final s = [for (var w = 0; w < 3; w++) ((dump[w] as Map)['v'] as Map<String, int>)[g] ?? 0];
          if (s.any((x) => x > 0) && s.any((x) => x == 0)) zero[g] = (zero[g] ?? 0) + 1;
        }
      }
    }
    // ignore: avoid_print
    print('weekly minimum gate: ON ${verdicts(rOn)} OFF ${verdicts(rOff)}; new majors ${newMajor.length}; '
        'Calves newly 0 at 30: $newlyCalves30; zero weeks ON $zeroOn OFF $zeroOff; max over $maxOver; '
        'stamp false $stampFalse');

    expect(verdicts(rOn), {'suitable': 657, 'needs_work': 495});
    // Unit 3A (2026-11-15): OFF (2C-b off) 578 / 546 / 28 -> 587 / 537 / 28 under the goal's Cut / Maintain bands; ON
    // and every count below unchanged. With the goal training off everywhere the 2C-b value measured back exactly.
    expect(verdicts(rOff), {'suitable': 587, 'needs_work': 537, 'not_suitable': 28});
    expect(newMajor, isEmpty);
    expect(newlyOther, isEmpty, reason: 'only Calves at 30 may go to 0 (d45)');
    expect(newlyCalves30, 143);
    expect(rowDiff, isEmpty, reason: 'd44: the allowance adds sets, never an exercise');
    // Unit 2E (d51) closed the Biceps 13 / Triceps 9 pairs; Calves 49 is unchanged (d45 / d49).
    expect(zeroOn, {'Calves': 49});
    expect(zeroOff, {'Biceps': 14, 'Triceps': 19, 'Core': 42, 'Calves': 57});
    expect(maxOver, lessThanOrEqualTo(6), reason: 'd47');

    // 9. ON byte for byte.
    final onDigest = sha256Hex(utf8.encode([for (final k in onMap.keys) '$k:${sha256Hex(utf8.encode(onMap[k]!))}'].join('\n')));
    // ignore: avoid_print
    print('weekly minimum gate ON digest: $onDigest');
    expect(onDigest, _onDigest);

    // 7. The stamp and the fallback.
    expect(stampFalse, _fallback);
    for (final k in _fallback) {
      expect(onMap[k], offMap[k], reason: '$k: the fallback is R verbatim, week 2 included');
    }
  });

  // Unit 2E (OI-496, founder d51; plan docs/plans/2026-11-15-generator-step2e-arm-swap.md S8): the arm swap against its
  // test seam off (`SessionSetAllocator.debugArmSwap`), over the same 1,152 plans with the balanced week ON. A plan
  // changes only when, with the seam off, one variant has 0 Biceps or 0 Triceps while the other trains it.
  // Measured on the built tree: exactly 21 plans, and in each the arm pair is gone.
  // In every plan: no group trained in a plan-week (1-3) with the seam off is at 0 with it on; every day holds the same
  // rows; no new major code; the minutes stay within +6; a changed plan used the allowance.
  test('Unit 2E: the arm swap against its seam off (1,152 plans)', () async {
    final auditor = PlanAuditor(byExactName);
    final on = <String, Map<String, dynamic>>{}, off = <String, Map<String, dynamic>>{};
    final onStamp = <String, bool?>{};
    for (final seam in const [true, false]) {
      SessionSetAllocator.debugArmSwap = seam;
      try {
        for (final goal in _goals) {
          for (final days in const [3, 4, 5, 6]) {
            for (final level in _levels) {
              for (final tier in _tiers) {
                for (final minutes in const [30, 45]) {
                  for (final phase in const [1, 2, 3]) {
                    SessionSetAllocator.debugLastAllowance = null;
                    final d = dumpOf(gen(goal, days, level, tier, minutes, phase), goal, days, level, tier, minutes, phase);
                    final key = d['k'] as String;
                    (seam ? on : off)[key] = d;
                    if (seam) onStamp[key] = SessionSetAllocator.debugLastAllowance;
                  }
                }
              }
            }
          }
        }
      } finally {
        SessionSetAllocator.debugArmSwap = true;
      }
    }
    bool armPair(Map<String, dynamic> d) {
      final w = d['w'] as List;
      for (final g in const ['Biceps', 'Triceps']) {
        final s = [for (var i = 0; i < 3; i++) ((w[i] as Map)['v'] as Map<String, int>)[g] ?? 0];
        if (s.any((x) => x > 0) && s.any((x) => x == 0)) return true;
      }
      return false;
    }

    final changed = [for (final k in on.keys) if (jsonEncode(on[k]) != jsonEncode(off[k])) k];
    final newlyZero = <String>[], rowDiff = <String>[], newMajor = <String>[];
    var maxOver = 0, newlyTrained = 0;
    for (final k in on.keys) {
      final minutes = int.parse(k.split('|')[4]);
      final wOn = on[k]!['w'] as List, wOff = off[k]!['w'] as List;
      for (var w = 0; w < wOn.length; w++) {
        final vOn = (wOn[w] as Map)['v'] as Map<String, int>, vOff = (wOff[w] as Map)['v'] as Map<String, int>;
        if (w < 3) {
          for (final g in _groups) {
            if ((vOff[g] ?? 0) > 0 && (vOn[g] ?? 0) == 0) newlyZero.add('$k week ${w + 1} $g');
            if ((vOff[g] ?? 0) == 0 && (vOn[g] ?? 0) > 0) newlyTrained++;
          }
        }
        final dOn = (wOn[w] as Map)['d'] as List, dOff = (wOff[w] as Map)['d'] as List;
        for (var i = 0; i < dOn.length; i++) {
          if (((dOn[i] as Map)['x'] as List).length != ((dOff[i] as Map)['x'] as List).length) {
            rowDiff.add('$k week ${w + 1} day $i');
          }
          final mins = (dOn[i] as Map)['min'] as int?;
          if (mins != null && mins - minutes > maxOver) maxOver = mins - minutes;
        }
      }
      final majorsOff = {for (final i in auditor.audit(off[k]!).issues) if (i.severity == 'major') i.code};
      final majorsOn = {for (final i in auditor.audit(on[k]!).issues) if (i.severity == 'major') i.code};
      if (!majorsOff.containsAll(majorsOn)) newMajor.add(k);
    }
    // ignore: avoid_print
    print('arm swap gate: changed ${changed.length}; arm pairs off ${off.values.where(armPair).length} '
        'on ${on.values.where(armPair).length}; newly zero ${newlyZero.length}; newly trained $newlyTrained; '
        'max over $maxOver');

    expect(changed.length, 21);
    expect([for (final k in changed) if (!armPair(off[k]!)) k], isEmpty, reason: 'a changed plan had an arm pair');
    expect(off.values.where(armPair).length, 21);
    expect(on.values.where(armPair), isEmpty);
    expect(newlyZero, isEmpty, reason: 'S8: never at a group\'s cost');
    // Plan-weeks (weeks 1-3, any group) at 0 with the seam off and trained with it on (round 1 B7: the doc's figure).
    expect(newlyTrained, 34);
    expect(rowDiff, isEmpty, reason: 'd51: same exercise count');
    expect(newMajor, isEmpty);
    expect(maxOver, lessThanOrEqualTo(6), reason: 'd47');
    expect([for (final k in changed) if (onStamp[k] != true) k], isEmpty, reason: 'a swap runs in the allowance world');
  });

  test('2A off and 2B off: the switch changes nothing (48 plans at 30 minutes)', () async {
    final config = HiveService.instance.configBox;
    for (final flag in const ['disable_lead_first', 'disable_day_floor']) {
      await config.put(flag, true);
      try {
        String digest(bool switchOff) {
          final lines = <String>[];
          for (final goal in _goals) {
            for (final days in const [3, 5]) {
              for (final level in _levels) {
                for (final tier in const ['bodyweight', 'full_gym']) {
                  lines.add(sha256Hex(utf8.encode(jsonEncode(gen(goal, days, level, tier, 30, 1).toMap()))));
                  expect(SessionSetAllocator.debugLastAllowance, isFalse, reason: '$flag: never the allowance');
                }
              }
            }
          }
          return sha256Hex(utf8.encode(lines.join('\n')));
        }

        await config.delete('disable_balanced_week');
        final switchOn = digest(false);
        await config.put('disable_balanced_week', true);
        final switchOff = digest(true);
        expect(switchOn, switchOff, reason: '$flag set: 2C-b does not run');
      } finally {
        await config.delete(flag);
        await config.delete('disable_balanced_week');
      }
    }
  });
}
