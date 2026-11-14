// Unit 2C-b (docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md §5, founder d35-d49): the whole-engine gate
// for the weekly minimum and the under-60 allowance. The real PlanGenerator.instance.generateV4 runs the audit grid at
// 30 and 45 minutes (4 goals x 3 / 4 / 5 / 6 days x 3 levels x 4 tiers x phases 1-3: 1,152 plans, no injuries, no
// history) with 2C's kill switch `disable_balanced_week` unset (ON) and set (OFF: below 60 minutes 2C-a never acts, so
// OFF is the pre-2C-b tree). Every expected value was computed from the measurement dumps before this gate was run
// (the chosen prototype run b25 against merged main de30a0a7, both 30 / 45 restricted; plan §4.1, §7 option (a)), and
// the built allocator reproduces b25's 2,304-plan dump byte for byte.
//
//  1. Verdicts (the audit lib, its over-time bound at +6, d47): ON 657 suitable / 495 needs_work / 0 not_suitable;
//     OFF 578 / 546 / 28 (the 28 Shoulders-zero lose_fat / general_fitness plans, fixed by the swap design).
//  2. No plan gains a major issue code against OFF.
//  3. A group OFF trains in a plan-week (1-3) is never at 0 ON, except Calves at 30 minutes (d45): exactly 143.
//  4. Every day holds exactly OFF's rows, all four weeks (d44: the allowance adds sets, never an exercise).
//  5. (plan, group) pairs with a zero week among weeks 1-3: ON 71 (Biceps 13, Triceps 9, Calves 49), OFF 132.
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
/// Item 9: the ON grid's digest on the built tree (2026-11-14).
const _onDigest = '7420fa3251fa6cb98d6b2e73fcb0127868644454e23ca8084e22836ed54d24ee';

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
  });

  tearDownAll(() async {
    final config = HiveService.instance.configBox;
    for (final k in const ['disable_balanced_week', 'disable_lead_first', 'disable_day_floor']) {
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
                      return SessionBudget.estimateDayMinutesFromPlanDay(d.toMap(), byId, rowsByName: byName);
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
    expect(verdicts(rOff), {'suitable': 578, 'needs_work': 546, 'not_suitable': 28});
    expect(newMajor, isEmpty);
    expect(newlyOther, isEmpty, reason: 'only Calves at 30 may go to 0 (d45)');
    expect(newlyCalves30, 143);
    expect(rowDiff, isEmpty, reason: 'd44: the allowance adds sets, never an exercise');
    expect(zeroOn, {'Biceps': 13, 'Triceps': 9, 'Calves': 49});
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
