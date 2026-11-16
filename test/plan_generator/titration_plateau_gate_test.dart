// Generator step 4 (OI-53) gate: volume titration and plateau escalation, switched on, over a simulated history
// (plan docs/plans/2026-11-16-generator-step4-titration-plateau.md section 4 item 3; diagnose 7c4e2a).
//
// Per profile and scenario the shared simulation (`plan_audit/history_sim_lib.dart`) writes a history and generates
// the advance in four worlds: OFF (kill switches set, no opt-in), IDENTITY (switches unset, no opt-in), KILLED
// (switches set, opted in) and ON (switches unset, opted in: the fresh-advance call). Hard zeros on the ON plan's
// FINAL rows (titration runs after the allocator, so never `debugLastStats`' sets):
//   - IDENTITY and KILLED equal OFF (the opt-ins and the kill switches each turn both features off);
//   - no NEW non-focus row past its day's lead + 1 (2A's R2 / R5; lead = SequencingEngine.openerOf over budgeted rows);
//   - no new 1-set row (d65: never below 2);
//   - no day both longer than OFF and over the plan audit's time bound;
//   - no group-week over the ceiling: top(g) (the focus top for a focus group) + the floor's seats past it
//     (`BudgetInvariantOracle`, variant A for weeks 1 / 3, B for 2 / 4, A for a 6-day plan);
//   - no group-week over the raw top(g) with ON > OFF in a week whose picks did not change.
// Scenario checks: mixed keeps every merged -1 (putIfAbsent) and has groups that test it; sore (3 of 6) and
// readiness-off change nothing; sore at 2 of 6 does; flat keeps the d82 net (under-bottom group-weeks ON <= OFF, no
// major group-week at 0 only in ON). Positive pins: a focus row above lead + 1 gained a set (flat), a lead took a
// trim (decline), so a stricter mutant cannot pass silently.
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
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plateau_scan.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

import 'plan_audit/history_sim_lib.dart';

const _goals = ['build_muscle', 'lose_fat', 'general_fitness'];
const _days = [3, 4, 5, 6];
const _levels = ['beginner', 'intermediate', 'advanced'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _minutes = [30, 45, 60, 90];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee4405';
  final today = DateTime(2026, 11, 16, 9);
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName, byId;
  late HistorySim sim;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('titration_gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    byName = await seedLibrary(rows);
    byId = {for (final r in rows) (r['id'] ?? r['name']).toString(): r};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    setTestClockTo(today);
    sim = HistorySim(byName: byName, today: today);
  });

  tearDownAll(() async {
    resetTestClock();
    await sim.setKilled(false);
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  int? minutesOf(WorkoutDay d) {
    try {
      return SessionBudget.estimateDayMinutesFromPlanDay(d.toMap(), byId,
          rowsByName: byName, finisher: [for (final f in d.finisher) f.toMap()]);
    } catch (_) {
      return null;
    }
  }

  List<String> namesOf(WeekPlan w) => [for (final d in w.workoutDays) for (final e in d.exercises) e.exerciseName]..sort();

  test('titration and plateau escalation: the lead-first rule, the band and the time hold over a simulated history',
      () async {
    final failures = <String>[];
    final c = <String, int>{};
    void count(String k, [int n = 1]) => c[k] = (c[k] ?? 0) + n;
    void fail(String k, String msg) {
      count('FAIL $k');
      if (failures.length < 40) failures.add('$k: $msg');
    }

    // (scenario, label, levels, soreCount)
    final runs = <(HistoryScenario, String, List<String>, int)>[
      (HistoryScenario.progress, 'progress', _levels, 0),
      (HistoryScenario.decline, 'decline', _levels, 0),
      (HistoryScenario.flat, 'flat', _levels, 0),
      (HistoryScenario.mixed, 'mixed', _levels, 0),
      (HistoryScenario.sore, 'sore3', const ['intermediate'], 3),
      (HistoryScenario.sore, 'sore2', const ['intermediate'], 2),
      (HistoryScenario.readinessOff, 'readinessOff', const ['intermediate'], 0),
      (HistoryScenario.focus, 'focus', const ['intermediate'], 0),
    ];

    for (final (scenario, label, levels, soreCount) in runs) {
      final phase = HistorySim.phaseOf(scenario);
      for (final goal in _goals) {
        for (final days in _days) {
          for (final level in levels) {
            for (final tier in _tiers) {
              for (final minutes in _minutes) {
                final key = '$label|$goal|$days|$level|$tier|$minutes';
                count('$label plans');
                await sim.clearHistory();
                await sim.setKilled(true);
                final planGoal = FitnessGoals.of(goal).planGoal;
                final quadGlutes = SplitResolver.quadPrimaryCreditsGlutes(planGoal, days, minutes,
                    quadLegsB: PlanEngineFlags.quadLegsBEnabled);
                final earlier = sim.gen(goal, days, level, tier, minutes, HistorySim.earlierPhaseOf(scenario), optIn: false);
                await sim.writeHistory(scenario, earlier, quadGlutes, soreCount: soreCount);

                if (scenario == HistoryScenario.mixed) {
                  // The merge, read with the switches on: a group with a plateau +1 and a titration -1 keeps the -1.
                  await sim.setKilled(false);
                  final deltas = VolumeTitration.resolveDeltas(phase: phase);
                  final plateaued = PlateauScan.plateauedGroups(phase: phase);
                  final merged = PlateauScan.mergePlateauSetDeltas(deltas, phase: phase);
                  for (final g in plateaued) {
                    if (deltas[g] == -1) {
                      count('mixed groups with both');
                      if (merged[g] != -1) fail('merge', '$key $g merged ${merged[g]}');
                    }
                  }
                }

                final w = await sim.worlds(goal, days, level, tier, minutes, phase);
                final offMap = jsonEncode(w.off.toMap());
                if (jsonEncode(w.identity.toMap()) != offMap) fail('identity', key);
                if (jsonEncode(w.killed.toMap()) != offMap) fail('killed', key);
                final onEqualsOff = jsonEncode(w.on.toMap()) == offMap;
                if (!onEqualsOff) count('$label plans changed');
                if ((label == 'sore3' || label == 'readinessOff') && !onEqualsOff) fail(label, '$key ON != OFF');

                final eff = PlanGenerator.effectiveLevel(level, phase);
                final band = SessionBudget.weeklyBand(planGoal, eff, goalTraining: PlanEngineFlags.goalTrainingEnabled);
                final focus = w.focusGroups;
                final bound = minutes + (minutes < 60 ? 6 : 5);

                for (var wi = 0; wi < w.on.weekPlans.length; wi++) {
                  final won = w.on.weekPlans[wi], woff = w.off.weekPlans[wi];
                  for (var di = 0; di < won.workoutDays.length; di++) {
                    final mOn = minutesOf(won.workoutDays[di]), mOff = minutesOf(woff.workoutDays[di]);
                    if (mOn != null && mOff != null && mOn > mOff) {
                      count('$label days longer');
                      if (mOn > bound) fail('time', '$key w$wi d$di $mOff -> $mOn (bound $bound)');
                    }
                  }
                  if (won.weekCharacter == 'deload') continue;
                  final samePicks = namesOf(won).join('|') == namesOf(woff).join('|');
                  final variant = HistorySim.variantOf(wi, days);
                  final gOn = sim.groupSets(won, quadGlutes), gOff = sim.groupSets(woff, quadGlutes);
                  for (final g in historySimGroups) {
                    final a = gOn[g] ?? 0, b = gOff[g] ?? 0;
                    final ceiling = HistorySim.ceilingOf(g, focus, band.top, w.stats[variant]);
                    if (a > ceiling) fail('ceiling', '$key w$wi $g $a > $ceiling');
                    if (samePicks && a > HistorySim.topOf(g, focus, band.top) && a > b) {
                      fail('raw top', '$key w$wi $g $b -> $a');
                    }
                    if (a > 0 || b > 0) {
                      if (a < band.bottom) count('$label under-bottom ON');
                      if (b < band.bottom) count('$label under-bottom OFF');
                    }
                    if (historySimMajors.contains(g) && a == 0 && b > 0) count('$label majors at 0 only ON');
                  }
                  for (var di = 0; di < won.workoutDays.length; di++) {
                    final dOn = won.workoutDays[di], dOff = woff.workoutDays[di];
                    final newBreaks = sim.r2Breaks(dOn, focus, quadGlutes).difference(sim.r2Breaks(dOff, focus, quadGlutes));
                    if (newBreaks.isNotEmpty) fail('R2', '$key w$wi d$di $newBreaks');
                    int ones(WorkoutDay d) => d.exercises.where((e) => sim.isBudgeted(e) && e.sets == 1).length;
                    if (ones(dOn) > ones(dOff)) fail('1-set', '$key w$wi d$di');
                    final lOn = sim.leadOf(dOn), lOff = sim.leadOf(dOff);
                    if (lOn != null && lOff != null && lOn.exerciseName == lOff.exerciseName && lOn.sets < lOff.sets) {
                      count('$label leads trimmed');
                    }
                    if (lOn != null) {
                      final offSets = {for (final e in dOff.exercises) e.exerciseName: e.sets};
                      for (final e in dOn.exercises) {
                        if (identical(e, lOn) || !sim.isBudgeted(e)) continue;
                        if (sim.credited(e, quadGlutes).any(focus.contains) &&
                            e.sets > lOn.sets + 1 &&
                            e.sets > (offSets[e.exerciseName] ?? 99)) {
                          count('$label focus rows above lead + 1 that gained');
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // ignore: avoid_print
    print('titration / plateau gate: ${(c.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join(', ')}');
    expect(failures, isEmpty, reason: failures.join('\n'));
    expect(c['progress plans'], 576);
    expect(c['sore3 plans'], 192);
    // d82: rotation and the plateau +1 leave the flat world no worse at the band bottom, and no major newly at 0.
    expect(c['flat under-bottom ON'] ?? 0, lessThanOrEqualTo(c['flat under-bottom OFF'] ?? 0));
    expect(c['flat majors at 0 only ON'] ?? 0, 0);
    // Positive pins, measured on the build 2026-11-16 (a stricter mutant lowers them; any generator change re-measures
    // them, as the other generator gates do): the T1 focus exemption, T2 taking the lead, mixed's merge cases, the
    // 40 % rule's boundary, and the titrated plans themselves.
    expect(c['flat focus rows above lead + 1 that gained'], 48, reason: 'T1 focus exemption');
    expect(c['decline leads trimmed'], 685, reason: 'T2 may take the lead (d65) under the R2 guard');
    expect(c['mixed groups with both'], 1612, reason: 'the merge check must not be vacuous');
    expect(c['sore2 plans changed'], 48, reason: '2 of 6 sore check-ins do not stop a +1');
    expect(c['progress plans changed'], 126);
    expect(c['decline plans changed'], 373);
    expect(c['flat plans changed'], 446);
    // Reported (stated in the plan, section 3): the d82 net on flat and its cost on mixed.
    expect((c['flat under-bottom OFF'], c['flat under-bottom ON']), (9956, 9830));
    expect((c['mixed under-bottom OFF'], c['mixed under-bottom ON']), (9939, 9956));
  });
}
