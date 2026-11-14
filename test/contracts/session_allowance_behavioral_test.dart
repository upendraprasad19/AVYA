// Unit 2C-b, S4 (docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md, founder d42 / d44 / d47): the one
// under-60 allowance. A ledger built with `allowance: true` under 60 minutes adds `SessionBudget.allowanceSeconds`
// (285 s) to each day's budget and forces nothing further (`forcingBound` 0: never stacked with the count floor's
// 300 s); at 60+ and without the flag it is today's ledger. The allocator re-runs the chosen worlds with it, at most the
// reference R's rows per day (d44: sets, never an extra exercise), and stamps `PopulatedDay.allowance` on every day
// when it used it; `PeriodizationEngine._weekTwoGains` follows that stamp, `VolumeTitration` never takes the allowance
// (plan round 4 R4-1: it titrates `WeekPlan`s, which carry no stamp).
//
// Pure Dart over crafted fixtures and a seeded sweep over the shipped library. Day budgets: 1440 s at 30 minutes
// (+285 with the allowance), 3000 s at 60. Through `generateV4`, the gate `weekly_minimum_gate_test.dart` covers the
// real plans (the fallback plans, 2A / 2B off).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/budget_invariant_oracle.dart';
import '../helpers/session_budget_fixtures.dart';

List<int> rowsOf(List<PopulatedDay> out, {bool b = false}) =>
    [for (final d in out) (b ? d.exercisesB : d.exercisesA).length];

/// A two-day plan, A = [p1, row1, p2, curlA, calfA], B = [p4, calfB, p5, curlB]: at 30 minutes R seats four rows a day.
(Fx, List<PopulatedDay>) shortWeek() {
  final f = Fx();
  for (final n in ['p1', 'p2', 'p4', 'p5']) {
    f.row(n, ['Chest']);
  }
  f.row('row1', ['Lats']);
  f.row('curlA', ['Biceps'], type: 'isolation');
  f.row('curlB', ['Biceps'], type: 'isolation');
  f.row('calfA', ['Gastrocnemius'], type: 'isolation');
  f.row('calfB', ['Gastrocnemius'], type: 'isolation');
  final dA = [f.ex('p1'), f.ex('row1'), f.ex('p2'), f.ex('curlA'), f.ex('calfA')];
  final dB = [f.ex('p4'), f.ex('calfB'), f.ex('p5'), f.ex('curlB')];
  return (f, [f.day('hypertrophy', dA, b: dB), f.day('hypertrophy', dA, b: dB)]);
}

/// The same days with every `allowance` stamp set to [allowance].
List<PopulatedDay> restamp(List<PopulatedDay> days, bool allowance) => [
      for (final d in days)
        PopulatedDay(
          name: d.name,
          focus: d.focus,
          dayType: d.dayType,
          intensity: d.intensity,
          exercisesA: d.exercisesA,
          exercisesB: d.exercisesB,
          allowance: allowance,
        ),
    ];

int weekSets(WeekPlan w) => [for (final d in w.workoutDays) for (final e in d.exercises) e.sets].fold(0, (a, b) => a + b);

void main() {
  group('the ledger (S4)', () {
    test('under 60 the allowance adds 285 s and the forcing bound is 0; at 60+ or without it, today\'s ledger', () {
      final (f, days) = shortWeek();
      final at30 = f.ctx(days, minutes: 30);
      final at60 = f.ctx(days, minutes: 60);
      expect(SessionBudget.allowanceSeconds, 285, reason: 'founder d47');
      final plain30 = BudgetLedger(at30, 1);
      final with30 = BudgetLedger(at30, 1, allowance: true);
      expect(with30.secondsLeft(0) - plain30.secondsLeft(0), closeTo(285, 1e-6));
      expect(plain30.forcingBound, SessionBudget.maxForcedOverSeconds);
      expect(with30.forcingBound, 0, reason: 'd42: the allowance and the count floor never stack');
      final with60 = BudgetLedger(at60, 1, allowance: true);
      expect(with60.secondsLeft(0), BudgetLedger(at60, 1).secondsLeft(0));
      expect(with60.forcingBound, SessionBudget.maxForcedOverSeconds);
      // A 40-minute value behaves as 30 for the allowance (under 60), a 59 too.
      for (final m in [40, 59]) {
        final c = f.ctx(days, minutes: m);
        expect(BudgetLedger(c, 1, allowance: true).secondsLeft(0) - BudgetLedger(c, 1).secondsLeft(0),
            closeTo(285, 1e-6),
            reason: '$m minutes');
      }
    });
  });

  group('the allocator\'s stamp (PopulatedDay.allowance)', () {
    test('true on every day only when 2C-b ran under 60: lead-first, floor ON, switch ON', () {
      final (f, days) = shortWeek();
      bool stamp(List<PopulatedDay> out) {
        final s = {for (final d in out) d.allowance};
        expect(s.length, 1, reason: 'one value per plan');
        expect(SessionSetAllocator.debugLastAllowance, s.single);
        return s.single;
      }

      expect(stamp(f.run(days, minutes: 30, is6Day: false, balancedWeek: true)), isTrue);
      expect(stamp(f.run(days, minutes: 45, is6Day: false, balancedWeek: true)), isTrue);
      expect(stamp(f.run(days, minutes: 30, is6Day: true, balancedWeek: true)), isTrue, reason: '6-day branch');
      expect(stamp(f.run(days, minutes: 60, is6Day: false, balancedWeek: true)), isFalse, reason: '60+');
      expect(stamp(f.run(days, minutes: 30, is6Day: false, balancedWeek: false)), isFalse, reason: 'switch OFF');
      expect(stamp(f.run(days, minutes: 30, is6Day: false, balancedWeek: true, dayFloor: false)), isFalse,
          reason: '2B off');
      expect(stamp(f.run(days, minutes: 30, is6Day: false, balancedWeek: true, leadFirst: false)), isFalse,
          reason: '2A off');
      expect(stamp(f.run(days, minutes: 30, is6Day: true, balancedWeek: true, dayFloor: false)), isFalse,
          reason: '2B off, 6-day');
    });

    test('the allowance adds sets on the rows R holds, never a row (d44), and the day ends inside budget + 285 s', () {
      for (final m in [30, 45]) {
        for (final is6 in [false, true]) {
          final (f, days) = shortWeek();
          final off = f.run(days, minutes: m, is6Day: is6, balancedWeek: false);
          final on = f.run(days, minutes: m, is6Day: is6, balancedWeek: true);
          final stats = SessionSetAllocator.debugLastStats!;
          expect(rowsOf(on), rowsOf(off), reason: '$m min, 6-day $is6, A');
          if (!is6) expect(rowsOf(on, b: true), rowsOf(off, b: true), reason: '$m min, B');
          expect(_aSets(on), greaterThanOrEqualTo(_aSets(off)), reason: '$m min, 6-day $is6');
          final ctx = f.ctx(days, minutes: m);
          for (final v in is6 ? const ['A'] : const ['A', 'B']) {
            _expectTime(on, stats[v]!, ctx, b: v == 'B', allowance: true);
          }
        }
      }
    });
  });

  group('the readers', () {
    // The week-2 +1 never binds on the clock in a crafted week (12 shapes probed at 30 / 45 minutes: it binds on the lead
    // + 1 hold and the weekly band first), so the reader's proof that it follows the stamp is the gate's exact verdict
    // counts on the real grid (weekly_minimum_gate_test.dart; without the stamp 2 more plans are suitable, plan §4.5).
    test('_weekTwoGains with the stamp keeps every week-2 day inside budget + the allowance; weeks 1 and 3 unchanged', () {
      final (f, days) = shortWeek();
      final ctx = f.ctx(days, minutes: 30);
      final on = f.run(days, minutes: 30, is6Day: false, balancedWeek: true);
      expect(on.first.allowance, isTrue);
      final withStamp = PeriodizationEngine.apply(populated: on, phase: 1, is6Day: false, budget: ctx);
      final without = PeriodizationEngine.apply(populated: restamp(on, false), phase: 1, is6Day: false, budget: ctx);
      // Week 2 (variant B) is the only week the stamp may change: weeks 1 and 3 equal.
      expect(weekSets(withStamp[0]), weekSets(without[0]));
      expect(weekSets(withStamp[2]), weekSets(without[2]));
      // Each week-2 day stays inside budget + the allowance: the allocation itself used it, and the stamped +1 may too.
      _expectWeekTime(withStamp[1], ctx, 285);
      _expectWeekTime(without[1], ctx, 285);
      // No days: nothing to read, no throw.
      expect(PeriodizationEngine.apply(populated: const [], phase: 1, is6Day: false, budget: ctx), isNotNull);
    });

    test('VolumeTitration never takes the allowance: at 30 minutes a +1 is accepted only inside the plain budget', () {
      // One 30-minute day: a budgeted Bench at 3 sets and an unbudgeted filler (time only) of n sets, for every n from an
      // empty day to a full one. A +1 on Bench is accepted only while the day still fits the PLAIN budget; with the
      // allowance (a ledger built with `allowance: true`) it would also be accepted up to 285 s past it.
      final ctx = testBudget(minutes: 30, names: const ['Bench']);
      final budget = BudgetLedger(ctx, 1).secondsLeft(0);
      double secs(List<PlannedExercise> day) => day.fold(
          0.0,
          (t, e) => t +
              SessionBudget.plannedExerciseSeconds(e, ctx, sets: e.sets, restSeconds: e.restSeconds));
      var bumped = 0, refused = 0;
      for (var n = 0; n <= 40; n++) {
        final day = [
          PlannedExercise(exerciseId: 'bench', exerciseName: 'Bench', loggingType: 'weight_reps', sets: 3, reps: '10',
              restSeconds: 90, primaryMuscles: const ['Chest']),
          if (n > 0)
            PlannedExercise(exerciseId: 'filler', exerciseName: 'Filler', loggingType: 'weight_reps', sets: n,
                reps: '10', restSeconds: 90, primaryMuscles: const ['Lats']),
        ];
        final weeks = [
          WeekPlan(weekNumber: 1, weekInPhase: 1, overloadNotes: '', weekCharacter: 'baseline', workoutDays: [
            WorkoutDay(dayNumber: 1, name: 'D', focus: '', exercises: day),
          ]),
        ];
        final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1}, budget: ctx).first.workoutDays.first.exercises;
        if (out.first.sets == 4) {
          bumped++;
          expect(secs(out), lessThanOrEqualTo(budget + 1e-6), reason: 'filler $n: the +1 fits the plain budget');
        } else {
          refused++;
        }
      }
      expect(bumped, greaterThan(0), reason: 'fixture: some days have room');
      expect(refused, greaterThan(0), reason: 'fixture: some days do not');
    });
  });

  group('invariants over the shipped library (seeded sweep, 2C-b ON)', () {
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
    final strengthRows = [
      for (final r in rows)
        if (const {'weight_reps', 'bodyweight_reps'}.contains(r['logging_type']) &&
            BudgetMuscleGroups.of([for (final m in (r['primary_muscles'] as List)) '$m']).isNotEmpty)
          r,
    ];

    test('220 random plans: time inside budget + the allowance (or the forcing bound), caps, tops; rows <= R under 60; '
        'at 60+ R exactly unless the minimum seated', () {
      final rnd = Random(20261114);
      const intensities = ['strength', 'hypertrophy', 'endurance'];
      const goals = ['build_muscle', 'strength', 'lose_fat', 'general_fitness'];
      const levels = ['beginner', 'intermediate', 'advanced'];
      var stamped = 0, fewerRows = 0, minimum60 = 0, equal60 = 0;
      final digestLines = <String>[];
      for (var plan = 0; plan < 220; plan++) {
        final nDays = 3 + rnd.nextInt(4);
        final is6 = nDays == 6;
        final minutes = const [30, 45, 60, 75, 90][rnd.nextInt(5)];
        final goal = goals[rnd.nextInt(4)];
        final level = levels[rnd.nextInt(3)];
        final focus = rnd.nextBool() ? <String>{BudgetMuscleGroups.groups[rnd.nextInt(10)]} : <String>{};
        final days = <PopulatedDay>[];
        for (var d = 0; d < nDays; d++) {
          List<PlannedExercise> pick() {
            final n = 3 + rnd.nextInt(7);
            final chosen = <String>{};
            while (chosen.length < n) {
              chosen.add(strengthRows[rnd.nextInt(strengthRows.length)]['name'] as String);
            }
            return [
              for (final name in chosen)
                PlannedExercise(
                  exerciseId: name.toLowerCase(),
                  exerciseName: name,
                  loggingType: byName[name.toLowerCase()]!['logging_type'] as String,
                  sets: 3,
                  reps: '10',
                  restSeconds: 75,
                  primaryMuscles: [for (final m in (byName[name.toLowerCase()]!['primary_muscles'] as List)) '$m'],
                ),
            ];
          }

          final a = pick();
          days.add(PopulatedDay(
            name: 'D$d',
            focus: 'F',
            dayType: 'push',
            intensity: intensities[rnd.nextInt(3)],
            exercisesA: a,
            exercisesB: is6 || rnd.nextBool() ? a : pick(),
          ));
        }
        final ctx = SessionBudgetContext(
          minutes: minutes,
          planGoal: goal,
          level: level,
          lighterPhase: false,
          focusGroups: focus,
          archetypeByName: {for (final e in byName.entries) e.key: SessionBudget.archetypeOfRow(e.value)},
        );
        final off = SessionSetAllocator.allocate(
            days: days, ctx: ctx, rowsByName: byName, is6Day: is6, balancedWeek: false);
        final offStats = SessionSetAllocator.debugLastStats!;
        // Whether R gives 2C-b a target: a group one variant credits and the other does not (d35; not on the 6-day
        // path), or a focus group a variant does not credit (d38); Calves under 45 never (d45).
        bool exempt(String g) => g == 'Calves' && minutes < 45;
        Set<String> cred(String v) => {for (final e in offStats[v]!.credited.entries) if (e.value > 0) e.key};
        final credA = cred('A'), credB = is6 ? credA : cred('B');
        final hasTarget = {...credA.difference(credB), ...credB.difference(credA)}.any((g) => !exempt(g)) ||
            focus.any((g) => !exempt(g) && (!credA.contains(g) || !credB.contains(g)));
        final on = SessionSetAllocator.allocate(
            days: days, ctx: ctx, rowsByName: byName, is6Day: is6, balancedWeek: true);
        final stats = SessionSetAllocator.debugLastStats!;
        digestLines.add('$plan:${on.first.allowance}:${_names(on)}:${_sets(on)}:'
            '${[for (final v in stats.keys.toList()..sort()) '$v${stats[v]!.minimumSeats}']}');
        if (stats.values.any((s) => s.timeForcedFirst + s.capForcedFirst > 0)) continue;
        final allowance = on.first.allowance;
        if (minutes >= 60) expect(allowance, isFalse, reason: 'plan $plan: never at 60+');
        if (allowance) stamped++;
        for (final v in is6 ? const ['A'] : const ['A', 'B']) {
          final b = v == 'B';
          _expectTime(on, stats[v]!, ctx, b: b, allowance: allowance, reason: 'plan $plan $v');
          if (minutes < 60) {
            final r0 = rowsOf(off, b: b), r1 = rowsOf(on, b: b);
            for (var d = 0; d < nDays; d++) {
              expect(r1[d], lessThanOrEqualTo(r0[d]), reason: 'plan $plan $v day $d: R\'s rows cap the day (d44)');
              if (r1[d] < r0[d]) fewerRows++;
            }
          }
        }
        if (minutes >= 60) {
          if (hasTarget) {
            minimum60++;
          } else {
            equal60++;
            expect(_names(on), _names(off), reason: 'plan $plan: at 60+ a plan with no target is R (round 3 R3-6)');
            expect(_sets(on), _sets(off), reason: 'plan $plan: at 60+ a plan with no target is R');
            expect(stats.values.every((s) => s.minimumSeats.isEmpty), isTrue, reason: 'plan $plan');
          }
        }
      }
      // ignore: avoid_print
      print('2C-b sweep: stamped $stamped, fewer-row variant-days $fewerRows, 60+ plans with a target $minimum60, '
          '60+ plans with none (equal to R) $equal60');
      expect(stamped, greaterThan(30), reason: 'the sweep must reach the allowance');
      // Every ON allocation of the sweep, byte for byte, as recorded on the built tree (2026-11-14): a change to any
      // 2C-b mechanism the sweep reaches turns this red (the mutation run in diagnose e9b3d7 says which).
      final digest = sha256Hex(utf8.encode(digestLines.join('\n')));
      // ignore: avoid_print
      print('2C-b sweep digest: $digest');
      expect(digest, '86d2017b6d9f47e66b8b960a8964c83fcd75a85a53b61d843096559bc7a77146');
      expect(equal60, greaterThan(30), reason: 'the sweep must reach 60+ plans');
    });
  });
}

int _aSets(List<PopulatedDay> out) => [for (final d in out) for (final e in d.exercisesA) e.sets].fold(0, (a, b) => a + b);

List<List<String>> _names(List<PopulatedDay> out) => [
      for (final d in out) [for (final e in d.exercisesA) e.exerciseName, '|', for (final e in d.exercisesB) e.exerciseName],
    ];
List<List<int>> _sets(List<PopulatedDay> out) => [
      for (final d in out) [for (final e in d.exercisesA) e.sets, -1, for (final e in d.exercisesB) e.sets],
    ];

/// A row's seconds as the allocator and week 2 price it.
double _priced(PlannedExercise e, SessionBudgetContext ctx) {
  final rest = SessionBudget.isBudgeted(e, ctx) || SessionBudget.isRepBased(e.loggingType)
      ? SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(e, ctx))
      : e.restSeconds;
  return SessionBudget.plannedExerciseSeconds(e, ctx, sets: e.sets, restSeconds: rest);
}

double _daySeconds(WorkoutDay d, SessionBudgetContext ctx) =>
    d.exercises.fold(0.0, (t, e) => t + _priced(e, ctx));

void _expectWeekTime(WeekPlan w, SessionBudgetContext ctx, int allowance) {
  final budget = BudgetLedger(ctx, 1).secondsLeft(0);
  for (final d in w.workoutDays) {
    expect(_daySeconds(d, ctx), lessThanOrEqualTo(budget + allowance + 1e-6), reason: d.name);
  }
}

/// The shared oracle over one allocated variant: time inside budget + the excused seconds (the allowance when
/// [allowance], else the count-forced and minimum-seat part within the forcing bound), the session cap, the weekly top
/// plus the floor's over-top sets.
void _expectTime(List<PopulatedDay> out, AllocationStats s, SessionBudgetContext ctx,
    {bool b = false, required bool allowance, String reason = ''}) {
  final ledger = BudgetLedger(ctx, out.length);
  for (var d = 0; d < out.length; d++) {
    final list = b ? out[d].exercisesB : out[d].exercisesA;
    for (final e in list) {
      final budgeted = SessionBudget.isBudgeted(e, ctx);
      ledger.add(
        d,
        budgeted
            ? BudgetMuscleGroups.creditedOf(e.primaryMuscles ?? const [],
                quadPrimaryCreditsGlutes: ctx.quadPrimaryCreditsGlutes)
            : const {},
        budgeted ? e.sets : 0,
        _priced(e, ctx),
      );
    }
    final excused = BudgetInvariantOracle.excusedSeconds(s, d, list, (e) => _priced(e, ctx),
        maxForcedOverSeconds: SessionBudget.maxForcedOverSeconds.toDouble(),
        allowanceSeconds: allowance ? SessionBudget.allowanceSeconds.toDouble() : 0);
    expect(-ledger.secondsLeft(d), lessThanOrEqualTo(excused + 1e-6), reason: '$reason day $d time');
  }
  for (final g in BudgetMuscleGroups.groups) {
    expect(ledger.week(g), lessThanOrEqualTo(BudgetInvariantOracle.weekCeiling(ledger.weeklyTop(g), s, g)),
        reason: '$reason $g week');
    for (var d = 0; d < out.length; d++) {
      expect(ledger.session(d, g), lessThanOrEqualTo(ledger.cap(g)), reason: '$reason $g day $d session');
    }
  }
}
