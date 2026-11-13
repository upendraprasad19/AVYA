// Unit 2B (OI-452, docs/plans/2026-11-13-generator-step2b-day-floor.md §2 F5 and §4, founder d30-d33): the shared
// harness of the whole-engine day-floor gate (`test/plan_generator/day_floor_gate_*_test.dart`). The REAL
// `PlanGenerator.generateV4`, each persona generated twice: the floor ON (the `disable_day_floor` key absent, the
// default) and OFF (the key set). Blocks: the probe's `pairs` (15 pairs x 4 goals x 3 levels x 3-6 days, phase 1, 60
// minutes), the same pairs at phase 4 (a lighter phase, d31), and `rep30` (the pinned phase-2 repeat over the pairs at
// 30 minutes, beginner, 3-6 days). Weeks 1-4. The sweep personas carry no focus group, so pass D's R2 exemption never
// meets a floored lead here.
//
// Asserted per (block, tier), counts pinned EXACTLY (measured on the 2B tree, so a better number reddens too):
//  - no day (ON) under 3 exercises;
//  - against the OFF run of the same persona, per week and day: no exercise is lost, only a day under 3 OFF gains
//    rows, and the days whose exercises are unchanged but whose sets fell (the pass-B knock-on) are counted;
//  - the restated invariant through the shared oracle (`budget_invariant_oracle.dart`): per week and group, the sets
//    <= the weekly top + the floor's over-top sets of that week's variant; no group over its session cap;
//  - the floor adds no budgeted row at its day's lead + 2 or more (Unit 2A's rule); the floor-off plans' own lead + 2
//    day-weeks (a 2A residue: the whole-plan fallback to the `main` world, where R2 does not apply) are pinned;
//  - the kill-switch proof (F5): the digest of every OFF plan's sha256 equals main 8a2e1c5a's, recorded in
//    `test/fixtures/day_floor_off_hashes.json` under `digest|<block>|<tier>`.
//
// The digests are recorded on main 8a2e1c5a by `day_floor_kill_switch_test.dart` (RECORD_DAY_FLOOR_HASHES=main), which
// imports only `day_floor_personas.dart` and so compiles there; this gate compares its OFF plans against them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import 'budget_invariant_oracle.dart';
import 'day_floor_personas.dart';
import 'injury_floor_sweep_lib.dart';

/// What one (block, tier) measured.
class DayFloorTally {
  int runs = 0;
  int dayWeeks = 0;
  int thinOn = 0;
  int thinOff = 0;
  int gained = 0;
  int knockOn = 0;
  int pinsDiffer = 0;
  /// Day-weeks with a budgeted row at the day's lead + 2 or more, the floor OFF: a Unit 2A residue (the whole-plan
  /// fallback to the `main` world, where R2 does not apply), not the floor's; pinned, and the floor may add none.
  int leadPlus2Off = 0;
  final offHashes = <String>[];
  final bad = <String, List<String>>{};
  void fail(String zero, String why) => (bad[zero] ??= []).add(why);

  /// The pinned shape: (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF).
  (int, int, int, int, int, int) get counts => (runs, dayWeeks, thinOff, gained, knockOn, leadPlus2Off);
}

typedef _Gen = ({Phase plan, Map<String, AllocationStats> stats});

class DayFloorGate {
  DayFloorGate(this.h);

  final SweepHarness h;
  late final Map<String, Map<String, dynamic>> _rows = {
    for (final r in (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).whereType<Map>())
      (r['name'] as String).toLowerCase(): Map<String, dynamic>.from(r),
  };

  bool _budgeted(PlannedExercise e) =>
      e.customOrigin == null &&
      const {'weight_reps', 'bodyweight_reps'}.contains(e.loggingType) &&
      _rows.containsKey(e.exerciseName.toLowerCase());

  _Gen _gen({
    required bool floor,
    required String tier,
    required String goal,
    required String level,
    required int days,
    required int phase,
    required List<String> injuries,
    Map<int, ({List<String> a, List<String> b})>? pins,
    int? minutes,
  }) {
    final box = HiveService.instance.configBox;
    try {
      if (floor) {
        box.delete('disable_day_floor');
      } else {
        box.put('disable_day_floor', true);
      }
      SessionSetAllocator.debugLastStats = null;
      final plan = h.gen(
          tier: tier, goal: goal, level: level, days: days, phase: phase, injuries: injuries, pins: pins, minutes: minutes);
      return (plan: plan, stats: SessionSetAllocator.debugLastStats!);
    } finally {
      box.delete('disable_day_floor');
    }
  }

  void _compare(DayFloorTally t, String label, String goal, String level, int days, int phase, _Gen on, _Gen off) {
    t.runs++;
    t.offHashes.add(dayFloorPlanHash(off.plan));
    final eff = PlanGenerator.effectiveLevel(level, phase);
    final lighter = PeriodizationEngine.archetypeForPhase(phase) == 'deload';
    final band = SessionBudget.weeklyBand(goal, eff);
    final top = lighter ? band.bottom : band.top;
    final cap = SessionBudget.sessionCap(goal, eff);
    final quadOwnsGlutes = goal == 'build_muscle' && days == 6;
    for (var w = 0; w < on.plan.weekPlans.length; w++) {
      final variant = (w == 1 || w == 3) && days != 6 ? 'B' : 'A';
      final stats = on.stats[variant];
      final week = <String, int>{};
      final dOn = on.plan.weekPlans[w].workoutDays;
      final dOff = off.plan.weekPlans[w].workoutDays;
      for (var d = 0; d < dOn.length; d++) {
        t.dayWeeks++;
        final a = dOn[d].exercises;
        final b = dOff[d].exercises;
        final where = '$label w${w + 1} d${d + 1}';
        if (a.length < 3) {
          t.thinOn++;
          t.fail('thin', '$where: ${a.length} exercises');
        }
        if (b.length < 3) t.thinOff++;
        final namesOn = [for (final e in a) e.exerciseName];
        final namesOff = [for (final e in b) e.exerciseName];
        for (final n in namesOff) {
          if (!namesOn.contains(n)) t.fail('lost', '$where: $n ($namesOff -> $namesOn)');
        }
        if (a.length > b.length) {
          t.gained++;
          if (b.length >= 3) t.fail('gained past 3', '$where: ${b.length} -> ${a.length}');
        }
        if (namesOn.join('|') == namesOff.join('|')) {
          final sOn = a.fold(0, (s, e) => s + e.sets);
          final sOff = b.fold(0, (s, e) => s + e.sets);
          if (sOn < sOff) t.knockOn++;
        }
        final session = <String, int>{};
        final budgetedRows = [
          for (final e in a)
            if (_budgeted(e)) e,
        ];
        for (final e in budgetedRows) {
          final muscles = [for (final m in _rows[e.exerciseName.toLowerCase()]!['primary_muscles'] as List) '$m'];
          for (final g in BudgetMuscleGroups.creditedOf(muscles, quadPrimaryCreditsGlutes: !quadOwnsGlutes)) {
            session[g] = (session[g] ?? 0) + e.sets;
            week[g] = (week[g] ?? 0) + e.sets;
          }
        }
        session.forEach((g, n) {
          if (n > cap) t.fail('session cap', '$where: $g $n > $cap');
        });
        final offPlus2 = _leadPlus2(b);
        if (offPlus2 != null) t.leadPlus2Off++;
        final onPlus2 = _leadPlus2(a);
        if (onPlus2 != null && offPlus2 == null) t.fail('lead + 2 added by the floor', '$where: $onPlus2');
      }
      week.forEach((g, n) {
        final ceiling = BudgetInvariantOracle.weekCeiling(top, stats, g);
        if (n > ceiling) t.fail('week top', '$label w${w + 1} $variant: $g $n > $ceiling (top $top)');
      });
    }
  }

  /// The first budgeted row of [day] at its lead's sets + 2 or more (the lead: `SequencingEngine.openerOf` over the
  /// budgeted rows, Unit 2A's definition), or null.
  String? _leadPlus2(List<PlannedExercise> day) {
    final rows = [
      for (final e in day)
        if (_budgeted(e)) e,
    ];
    final lead = SequencingEngine.openerOf(rows);
    if (lead == null) return null;
    for (final e in rows) {
      if (e.sets >= lead.sets + 2) return '${e.exerciseName} ${e.sets} vs lead ${lead.exerciseName} ${lead.sets}';
    }
    return null;
  }

  /// Every persona of [block] on [tier] (`day_floor_personas.dart`), each generated with the floor on and off. A
  /// pinned repeat's pins are the uninjured phase-1 plan generated with the floor ON (as the app does) and with it OFF;
  /// both repeats take the ON pins, so the comparison isolates the floor, and `pinsDiffer` counts the pin lists the
  /// worlds disagree on (0: an uninjured 30-minute plan is not floored, so the OFF repeat is exactly main's).
  DayFloorTally run(String block, String tier) {
    final t = DayFloorTally();
    final pinCache = <String, Map<int, ({List<String> a, List<String> b})>>{};
    final box = HiveService.instance.configBox;
    for (final p in dayFloorPersonas(block, tier)) {
      Map<int, ({List<String> a, List<String> b})>? pins;
      if (p.pinned) {
        pins = pinCache.putIfAbsent('${p.goal}|${p.level}|${p.days}', () {
          final on = dayFloorPins(h, p);
          box.put('disable_day_floor', true);
          try {
            if ('${dayFloorPins(h, p)}' != '$on') t.pinsDiffer++;
          } finally {
            box.delete('disable_day_floor');
          }
          return on;
        });
      }
      _Gen g(bool floor) => _gen(
          floor: floor,
          tier: p.tier,
          goal: p.goal,
          level: p.level,
          days: p.days,
          phase: p.phase,
          injuries: p.injuries,
          pins: pins,
          minutes: p.minutes);
      final on = g(true);
      final off = g(false);
      _compare(t, p.label, p.goal, p.level, p.days, p.phase, on, off);
    }
    return t;
  }

  /// Reports [t], then records or checks the OFF digest and asserts the pinned counts.
  void finish(String block, String tier, DayFloorTally t, (int, int, int, int, int, int) expected) {
    final digest = dayFloorDigest(t.offHashes);
    // ignore: avoid_print
    print('[day floor $block $tier] runs ${t.runs} day-weeks ${t.dayWeeks} thin ON ${t.thinOn} OFF ${t.thinOff} '
        'gained ${t.gained} knock-on ${t.knockOn} lead+2 OFF ${t.leadPlus2Off} pins differ ${t.pinsDiffer} OFF digest $digest '
        'bad ${{for (final e in t.bad.entries) e.key: e.value.length}}');
    for (final e in t.bad.entries) {
      // ignore: avoid_print
      print('  ${e.key}: ${e.value.take(5).toList()}');
    }
    final key = 'digest|$block|$tier';
    final file = File(dayFloorFixturePath);
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(fixture[key], {'runs': t.runs, 'sha256': digest},
        reason: '$key: the floor-off plans no longer equal main 8a2e1c5a (the kill switch, plan §2 F5)');
    expect(t.bad, isEmpty);
    expect(t.thinOn, 0);
    expect(t.pinsDiffer, 0);
    expect(t.counts, expected, reason: '(runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF) for $block $tier');
  }
}
