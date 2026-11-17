// Generator step 4 (OI-53, t404): the plan review WITH a simulated history. Skipped unless HISTORY_SIM_OUT names a
// directory, so CI never runs it:
//
//   HISTORY_SIM_OUT=/abs/dir TZ=Asia/Kolkata flutter test \
//     test/plan_generator/plan_audit/history_sim_dump_test.dart
//
// Volume titration and plateau escalation read the user's history (`exlog_*` e1RM, `readiness_*`), so the
// no-history 2,304-plan audit cannot see them. For every profile (3 goals x 3-6 days x 3 levels x 4 tiers x
// 30/45/60/90 minutes = 576) and scenario, this generates the earlier phase, logs its loaded lifts as sessions, writes
// readiness rows, then generates the next phase twice from the same history: both switches ON and opted in (the
// fresh-advance call) and both OFF. One line per (scenario, profile) in history_sim.jsonl.
//
// Scenarios: `HistoryScenario` in history_sim_lib.dart (the clock is pinned; history ends yesterday). The OFF world is
// the kill switches set with no opt-in, ON the switches unset and opted in (the lib's `worlds`, whose IDENTITY and
// KILLED worlds the gate checks). HISTORY_SIM_SCENARIOS=progress,decline,flat (any HistoryScenario names) narrows the
// run; the default is progress, decline, flat.
@Timeout(Duration(minutes: 180))
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
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plateau_scan.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

import '../../helpers/budget_invariant_oracle.dart';
import 'history_sim_lib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee4404';
  final outDir = Platform.environment['HISTORY_SIM_OUT'];
  final scenarios = (Platform.environment['HISTORY_SIM_SCENARIOS'] ?? 'progress,decline,flat')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName, byId;
  final today = DateTime(2026, 11, 16, 9);

  setUpAll(() async {
    if (outDir == null) return;
    tempDir = await Directory.systemTemp.createTemp('history_sim');
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
    byId = {for (final r in rows) (r['id'] ?? r['name']).toString(): r};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    setTestClockTo(today);
  });

  tearDownAll(() async {
    if (outDir == null) return;
    resetTestClock();
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // The ledger's own rule (SessionBudget.isBudgeted: no custom origin, not timed / cardio / distance, a library name).
  bool isBudgeted(PlannedExercise e) =>
      e.customOrigin == null &&
      !const {'timed', 'cardio', 'distance'}.contains(e.loggingType) &&
      byName.containsKey(e.exerciseName.toLowerCase());

  List<Map<String, dynamic>> weeksOf(Phase plan, bool quadGlutes) => [
        for (final w in plan.weekPlans)
          {
            'c': w.weekCharacter,
            'd': [
              for (final d in w.workoutDays)
                {
                  'x': [
                    for (final e in d.exercises)
                      [
                        e.exerciseName,
                        e.sets,
                        BudgetMuscleGroups.creditedOf(
                                [for (final m in ((byName[e.exerciseName.toLowerCase()]?['primary_muscles'] as List?) ?? e.primaryMuscles ?? const [])) '$m'],
                                quadPrimaryCreditsGlutes: quadGlutes)
                            .toList(),
                        e.exerciseType,
                        e.workingSets,
                        // x[5]: budgeted, the ledger's own rule (SessionBudget.isBudgeted: no custom origin, not
                        // timed / cardio / distance, a library name).
                        isBudgeted(e),
                      ]
                  ],
                  // 'l': the day's lead, SequencingEngine.openerOf over its budgeted rows (the gate's and R5's
                  // definition), as an index into 'x' (-1: none).
                  'l': (() {
                    final budgeted = [for (final e in d.exercises) if (isBudgeted(e)) e];
                    final opener = SequencingEngine.openerOf(budgeted);
                    return opener == null ? -1 : d.exercises.indexWhere((e) => identical(e, opener));
                  })(),
                  'min': (() {
                    try {
                      return SessionBudget.estimateDayMinutesFromPlanDay(d.toMap(), byId,
                          rowsByName: byName, finisher: [for (final f in d.finisher) f.toMap()]);
                    } catch (_) {
                      return null;
                    }
                  })(),
                }
            ],
          }
      ];

  test('history simulation (t404)', () async {
    final sim = HistorySim(byName: byName, today: today);
    final out = File('$outDir/history_sim.jsonl').openSync(mode: FileMode.write);
    var lines = 0;
    for (final name in scenarios) {
      final scenario = HistoryScenario.values.byName(name);
      final phase = HistorySim.phaseOf(scenario);
      for (final goal in const ['build_muscle', 'lose_fat', 'general_fitness']) {
        for (final days in const [3, 4, 5, 6]) {
          for (final level in const ['beginner', 'intermediate', 'advanced']) {
            for (final tier in const ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']) {
              for (final minutes in const [30, 45, 60, 90]) {
                await sim.clearHistory();
                await sim.setKilled(true);
                final planGoal = FitnessGoals.of(goal).planGoal;
                final quadGlutes = SplitResolver.quadPrimaryCreditsGlutes(planGoal, days, minutes,
                    quadLegsB: PlanEngineFlags.quadLegsBEnabled);
                final earlier = sim.gen(goal, days, level, tier, minutes, HistorySim.earlierPhaseOf(scenario), optIn: false);
                final logged = await sim.writeHistory(scenario, earlier, quadGlutes);
                await sim.setKilled(false);
                final deltas = VolumeTitration.resolveDeltas(phase: phase);
                final merged = PlateauScan.mergePlateauSetDeltas(deltas, phase: phase);
                final plateauNames = PlateauScan.plateauedExerciseNames(phase: phase).toList()..sort();
                final w = await sim.worlds(goal, days, level, tier, minutes, phase);
                final eff = PlanGenerator.effectiveLevel(level, phase);
                final band = SessionBudget.weeklyBand(planGoal, eff, goalTraining: PlanEngineFlags.goalTrainingEnabled);
                out.writeStringSync('${jsonEncode({
                  's': scenario.name,
                  'k': '$goal|$days|$level|$tier|$minutes|$phase',
                  'logged': logged,
                  'deltas': deltas,
                  'merged': merged,
                  'plateauNames': plateauNames,
                  'b': [band.bottom, band.top],
                  'cap': SessionBudget.sessionCap(planGoal, eff),
                  'fg': (w.focusGroups.toList()..sort()),
                  'ft': SessionBudget.focusWeeklyTop,
                  'fo': {
                    for (final v in w.stats.entries)
                      v.key: {
                        for (final g in historySimGroups)
                          if (BudgetInvariantOracle.floorOverTopSets(v.value, g) > 0)
                            g: BudgetInvariantOracle.floorOverTopSets(v.value, g),
                      },
                  },
                  'on': weeksOf(w.on, quadGlutes),
                  'off': weeksOf(w.off, quadGlutes),
                })}\n');
                lines++;
              }
            }
          }
        }
      }
    }
    out.closeSync();
    expect(lines, 576 * scenarios.length);
  }, skip: outDir == null ? 'set HISTORY_SIM_OUT to run the history simulation' : false);
}
