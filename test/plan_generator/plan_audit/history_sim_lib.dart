// Generator step 4 (OI-53, plan docs/plans/2026-11-16-generator-step4-titration-plateau.md section 4 item 3): the
// history simulation shared by the t404 dump (`history_sim_dump_test.dart`) and the CI gate
// (`titration_plateau_gate_test.dart`). Volume titration and plateau escalation read the user's history (`exlog_*`
// e1RM, `readiness_*`), so the no-history plan audit cannot see them: this writes a simulated history for a profile,
// then generates the next phase in four worlds from that same history.
//
// Worlds (per profile and scenario, in this order; `debugLastStats` is read right after ON, the last call):
//   OFF       kill switches set, no opt-in
//   IDENTITY  kill switches unset, no opt-in   -> must equal OFF (the opt-ins gate both features)
//   KILLED    kill switches set, opted in      -> must equal OFF (the kill switches turn both off)
//   ON        kill switches unset, opted in    (the fresh-advance call)
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import '../../helpers/budget_invariant_oracle.dart';

/// The ten budget groups the band and the ceiling are checked for.
const historySimGroups = [
  'Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Quads', 'Hamstrings', 'Glutes', 'Calves', 'Core', //
];
const historySimMajors = ['Chest', 'Back', 'Shoulders', 'Quads', 'Hamstrings', 'Glutes'];

/// The scenarios (plan section 1 and section 4 item 3).
enum HistoryScenario {
  /// Phase 1 history (4 weeks), every loaded lift +2.5 % a session, 6 green check-ins -> phase 2 (titration's +1).
  progress,

  /// As progress, each lift's last session 10 % lower -> phase 2 (titration's -1).
  decline,

  /// Phase 2's plan logged over 8 weeks at one load -> phase 3 (plateau needs >= 3 sessions over >= 28 days).
  flat,

  /// As flat, but per group one loaded compound is flat and every other loaded row declines in its last session, so
  /// a group gets a plateau +1 AND a titration -1 and `putIfAbsent` must keep the -1.
  mixed,

  /// Progress with [HistorySim.soreCount] of 6 check-ins at soreness 2 (3 of 6 trips the 40 % rule).
  sore,

  /// Progress with `disable_readiness` set: old green rows allow no +1 (T4).
  readinessOff,

  /// Progress with `physique_focus: glutes_legs` in the profile (the explicit focus replaces weakMuscles()).
  focus,
}

class HistorySim {
  HistorySim({required this.byName, required this.today});

  /// The exercise library by lowercase name.
  final Map<String, Map<String, dynamic>> byName;

  /// The pinned clock (history ends yesterday).
  final DateTime today;

  static const killSwitches = ['disable_volume_titration', 'disable_plateau_escalation'];

  String _dk(DateTime d) => istDateStr(d);

  Future<void> clearHistory() async {
    final wb = HiveService.instance.workoutBox;
    final hb = HiveService.instance.healthBox;
    for (final k in wb.keys.where((k) => k.toString().startsWith('exlog_')).toList()) {
      await wb.delete(k);
    }
    for (final k in hb.keys.where((k) => k.toString().startsWith('readiness_')).toList()) {
      await hb.delete(k);
    }
    await HiveService.instance.configBox.delete('disable_readiness');
    await HiveService.instance.userBox.delete('profile');
  }

  Future<void> setKilled(bool killed) async {
    final c = HiveService.instance.configBox;
    for (final k in killSwitches) {
      if (killed) {
        await c.put(k, true);
      } else {
        await c.delete(k);
      }
    }
  }

  bool isLoaded(PlannedExercise e) => e.loggingType == 'weight_reps' || e.loggingType == 'weighted_bodyweight';

  bool isCompound(PlannedExercise e) {
    if (e.exerciseType != null) return e.exerciseType!.toLowerCase() == 'compound';
    // The library's `exercise_type` is a LIST (['compound']); a toString() of it never equals 'compound' (B-pass F6).
    final t = byName[e.exerciseName.toLowerCase()]?['exercise_type'];
    final first = t is List ? (t.isEmpty ? null : t.first) : t;
    return first?.toString().toLowerCase() == 'compound';
  }

  /// Logs [plan]'s LOADED lifts as sessions over [weeks] weeks ending yesterday; returns the rows written.
  /// [factor] gives a session's load multiplier from the exercise name, its index (0-based) and the session count.
  Future<int> logHistory(Phase plan, int weeks, double Function(String name, int k, int n) factor) async {
    final wb = HiveService.instance.workoutBox;
    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: 7 * weeks));
    final days = plan.weekPlans.first.workoutDays.length;
    final step = 7 ~/ days;
    final sessions = <String, List<DateTime>>{};
    for (var w = 0; w < weeks; w++) {
      final week = plan.weekPlans[w % plan.weekPlans.length];
      for (var di = 0; di < week.workoutDays.length; di++) {
        final date = start.add(Duration(days: 7 * w + di * step));
        for (final e in week.workoutDays[di].exercises) {
          if (!isLoaded(e)) continue;
          (sessions[e.exerciseName] ??= []).add(date);
        }
      }
    }
    var n = 0;
    var idx = 0;
    for (final entry in sessions.entries) {
      final dates = entry.value;
      for (var k = 0; k < dates.length; k++) {
        final kg = (60.0 * factor(entry.key, k, dates.length) * 2).round() / 2;
        await wb.put('exlog_${_dk(dates[k])}_h${idx}_$k', {
          'exercise_name': entry.key,
          'date': _dk(dates[k]),
          'logging_type': 'weight_reps',
          'sets': [
            {'weight_kg': kg, 'reps_completed': 8},
          ],
        });
        n++;
      }
      idx++;
    }
    return n;
  }

  /// Six check-ins over the last 12 days, [soreCount] of them at soreness 2 (yellow), the rest green.
  Future<void> logReadiness({int soreCount = 0}) async {
    final hb = HiveService.instance.healthBox;
    for (var i = 1; i <= 6; i++) {
      final d = today.subtract(Duration(days: i * 2));
      final sore = i <= soreCount;
      await hb.put('readiness_${_dk(d)}', {
        'date': _dk(d),
        'sleep': 0,
        'soreness': sore ? 2 : 0,
        'energy': 0,
        'level': sore ? 'yellow' : 'green',
      });
    }
  }

  /// The mixed scenario's flat rows: walking [plan]'s loaded rows in plan order, a compound becomes flat when one of
  /// its credited groups has no flat row yet; a row is marked once.
  Set<String> mixedFlatNames(Phase plan, bool quadGlutes) {
    final flat = <String>{};
    final covered = <String>{};
    for (final w in plan.weekPlans) {
      for (final d in w.workoutDays) {
        for (final e in d.exercises) {
          if (!isLoaded(e) || !isCompound(e) || flat.contains(e.exerciseName)) continue;
          final groups = credited(e, quadGlutes);
          if (groups.any((g) => !covered.contains(g))) {
            flat.add(e.exerciseName);
            covered.addAll(groups);
          }
        }
      }
    }
    return flat;
  }

  /// The history for [scenario] after [earlier] was generated; returns the rows written.
  Future<int> writeHistory(HistoryScenario scenario, Phase earlier, bool quadGlutes, {int soreCount = 3}) async {
    final long = scenario == HistoryScenario.flat || scenario == HistoryScenario.mixed;
    final flatNames = scenario == HistoryScenario.mixed ? mixedFlatNames(earlier, quadGlutes) : const <String>{};
    final logged = await logHistory(earlier, long ? 8 : 4, (name, k, n) {
      if (scenario == HistoryScenario.flat) return 1.0;
      if (scenario == HistoryScenario.mixed) {
        if (flatNames.contains(name)) return 1.0;
        return (k == n - 1 && n >= 2) ? 0.9 : 1.0;
      }
      if (scenario == HistoryScenario.decline && k == n - 1 && n >= 2) return (1 + 0.025 * (k - 1)) * 0.9;
      return 1 + 0.025 * k;
    });
    await logReadiness(soreCount: scenario == HistoryScenario.sore ? soreCount : 0);
    if (scenario == HistoryScenario.readinessOff) {
      await HiveService.instance.configBox.put('disable_readiness', true);
    }
    if (scenario == HistoryScenario.focus) {
      await HiveService.instance.userBox.put('profile', {'physique_focus': 'glutes_legs'});
    }
    return logged;
  }

  /// The phase each scenario advances to.
  static int phaseOf(HistoryScenario s) => s == HistoryScenario.flat || s == HistoryScenario.mixed ? 3 : 2;

  /// The earlier phase each scenario logs.
  static int earlierPhaseOf(HistoryScenario s) => phaseOf(s) - 1;

  Phase gen(String goal, int days, String level, String tier, int minutes, int phase, {required bool optIn}) =>
      PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: const [],
        bodyFocus: const [],
        sessionDuration: minutes,
        previousWeights: const {},
        applyVolumeTitration: optIn,
        applyPlateauEscalation: optIn,
      );

  /// The four worlds for one profile from the history already written.
  Future<HistoryWorlds> worlds(String goal, int days, String level, String tier, int minutes, int phase) async {
    await setKilled(true);
    final off = gen(goal, days, level, tier, minutes, phase, optIn: false);
    await setKilled(false);
    final identity = gen(goal, days, level, tier, minutes, phase, optIn: false);
    await setKilled(true);
    final killed = gen(goal, days, level, tier, minutes, phase, optIn: true);
    await setKilled(false);
    final focusGroups =
        BudgetMuscleGroups.of(TrainingHistoryAnalyzer.resolveBodyFocus(explicitBodyFocus: const [], phase: phase));
    final on = gen(goal, days, level, tier, minutes, phase, optIn: true);
    final stats = Map<String, AllocationStats>.from(SessionSetAllocator.debugLastStats ?? const {});
    return HistoryWorlds(off: off, identity: identity, killed: killed, on: on, stats: stats, focusGroups: focusGroups);
  }

  // ── the row rules the gate checks (the ledger's own definitions) ──

  /// SessionBudget.isBudgeted: no custom origin, not timed / cardio / distance, a library name.
  bool isBudgeted(PlannedExercise e) =>
      e.customOrigin == null &&
      !const {'timed', 'cardio', 'distance'}.contains(e.loggingType) &&
      byName.containsKey(e.exerciseName.toLowerCase());

  Set<String> credited(PlannedExercise e, bool quadGlutes) => BudgetMuscleGroups.creditedOf(
        [for (final m in ((byName[e.exerciseName.toLowerCase()]?['primary_muscles'] as List?) ?? e.primaryMuscles ?? const [])) '$m'],
        quadPrimaryCreditsGlutes: quadGlutes,
      );

  /// The day's lead: SequencingEngine.openerOf over its budgeted rows (2A's, R5's and T1's definition).
  PlannedExercise? leadOf(WorkoutDay d) => SequencingEngine.openerOf([for (final e in d.exercises) if (isBudgeted(e)) e]);

  /// The day's non-lead budgeted rows crediting no focus group that sit past the lead + 1 (R2 / R5), each with how far
  /// past the lead it sits (sets - lead sets), so a gate can catch a break that only got DEEPER (B-pass F5).
  Map<String, int> r2Breaks(WorkoutDay d, Set<String> focus, bool quadGlutes) {
    final lead = leadOf(d);
    if (lead == null) return const {};
    return {
      for (final e in d.exercises)
        if (!identical(e, lead) &&
            isBudgeted(e) &&
            !credited(e, quadGlutes).any(focus.contains) &&
            e.sets > lead.sets + 1)
          e.exerciseName: e.sets - lead.sets,
    };
  }

  Map<String, int> groupSets(WeekPlan w, bool quadGlutes) {
    final out = <String, int>{};
    for (final d in w.workoutDays) {
      for (final e in d.exercises) {
        if (!isBudgeted(e)) continue;
        for (final g in credited(e, quadGlutes)) {
          out[g] = (out[g] ?? 0) + e.sets;
        }
      }
    }
    return out;
  }

  /// The stats variant of week [wi]: A for weeks 1 and 3, B for 2 and 4, A for every week of a 6-day plan.
  static String variantOf(int wi, int days) => days == 6 || wi.isEven ? 'A' : 'B';

  /// top(g): the focus top for a focus group, else the band top (phases 2-3; a lighter phase is not modelled).
  static int topOf(String g, Set<String> focus, int bandTop) => focus.contains(g) ? SessionBudget.focusWeeklyTop : bandTop;

  static int ceilingOf(String g, Set<String> focus, int bandTop, AllocationStats? stats) =>
      BudgetInvariantOracle.weekCeiling(topOf(g, focus, bandTop), stats, g);
}

class HistoryWorlds {
  HistoryWorlds({
    required this.off,
    required this.identity,
    required this.killed,
    required this.on,
    required this.stats,
    required this.focusGroups,
  });

  final Phase off, identity, killed, on;
  final Map<String, AllocationStats> stats;
  final Set<String> focusGroups;
}

/// Opens the boxes the generator reads (the same setup the plan audit uses).
Future<Map<String, Map<String, dynamic>>> seedLibrary(List<Map<String, dynamic>> rows) async {
  final exBox = Hive.box(HiveService.exerciseBoxName);
  for (final r in rows) {
    await exBox.put((r['id'] ?? r['name']).toString(), r);
  }
  return {for (final r in rows) (r['name'] as String).toLowerCase(): r};
}
