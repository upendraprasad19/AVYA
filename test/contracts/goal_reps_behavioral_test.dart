// Unit 3A (OI-487, founder d3 / d4 / d58-d60): the goal's rep table, the Strength focus and its rest, pure.
// The real-engine reach (Cut and Maintain differ in every profile; reps match the table) is the 3A gate.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/goal_reps.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../helpers/session_budget_fixtures.dart';

int base(String goal, String level, String archetype,
        {bool main = true, bool focus = false, int min = 6, int max = 12}) =>
    GoalReps.base(
      strengthFocus: focus,
      isMain: main,
      planGoal: goal,
      level: level,
      archetype: archetype,
      minReps: min,
      maxReps: max,
    );

void main() {
  const phases = ['hypertrophy', 'strength', 'metabolic', 'deload'];

  test('Cut main lifts: 8 / 6 / 8, deload 8 (intermediate, advanced); beginners 10 / 8 / 10, deload 10', () {
    for (final level in ['intermediate', 'advanced']) {
      expect([for (final a in phases) base('lose_fat', level, a, min: 4, max: 15)], [8, 6, 8, 8], reason: level);
    }
    expect([for (final a in phases) base('lose_fat', 'beginner', a, min: 4, max: 15)], [10, 8, 10, 10]);
  });

  test('Maintain main lifts: 10 / 8 / 10, deload 10, every level', () {
    for (final level in ['beginner', 'intermediate', 'advanced']) {
      expect([for (final a in phases) base('general_fitness', level, a, min: 4, max: 15)], [10, 8, 10, 10],
          reason: level);
    }
  });

  test('Build and the legacy strength token keep today\'s lean: mid / min / max / mid', () {
    for (final goal in ['build_muscle', 'strength', 'unknown']) {
      expect([for (final a in phases) base(goal, 'intermediate', a, min: 6, max: 12)], [9, 6, 12, 9], reason: goal);
    }
  });

  test('accessories keep today\'s lean (the 10-15 clamp is applied after the wave, by the caller)', () {
    for (final goal in ['lose_fat', 'general_fitness', 'build_muscle']) {
      expect([for (final a in phases) base(goal, 'intermediate', a, main: false, min: 8, max: 20)], [14, 8, 20, 14],
          reason: goal);
    }
    expect(GoalReps.clampsAccessories('lose_fat'), isTrue);
    expect(GoalReps.clampsAccessories('general_fitness'), isTrue);
    expect(GoalReps.clampsAccessories('build_muscle'), isFalse);
    expect(GoalReps.clampsAccessories('strength'), isFalse);
    expect((GoalReps.accessoryMin, GoalReps.accessoryMax), (10, 15));
  });

  test('the Strength focus: a main lift takes its range\'s low end in every phase but the deload, any goal', () {
    for (final goal in ['build_muscle', 'lose_fat', 'general_fitness']) {
      final got = [for (final a in phases) base(goal, 'intermediate', a, focus: true, min: 5, max: 12)];
      expect(got.sublist(0, 3), [5, 5, 5], reason: goal);
      expect(got[3], base(goal, 'intermediate', 'deload', min: 5, max: 12), reason: '$goal: deload keeps the goal');
    }
    expect(base('build_muscle', 'beginner', 'metabolic', focus: true, main: false, min: 8, max: 20), 20,
        reason: 'an accessory is untouched by the focus');
  });

  group('rest (d60)', () {
    test('+30 s on H and M under the Strength focus at 60+ minutes; nothing on I or B', () {
      const focus = GoalTraining(strengthFocus: true);
      int r(String a, GoalTraining gt, int m) => SessionBudget.restForGoal(a, gt, minutes: m);
      expect([for (final a in ['H', 'M', 'I', 'B']) r(a, focus, 60)], [180, 150, 75, 60]);
      expect([for (final a in ['H', 'M', 'I', 'B']) r(a, focus, 90)], [180, 150, 75, 60]);
      expect([for (final a in ['H', 'M', 'I', 'B']) r(a, const GoalTraining(), 60)], [150, 120, 75, 60]);
    });

    test('d64: no extra rest below 60 minutes (30 and 45 keep normal rest; the reps still take the low end)', () {
      const focus = GoalTraining(strengthFocus: true);
      expect([for (final m in [30, 45, 59, 60]) SessionBudget.restForGoal('H', focus, minutes: m)], [150, 150, 150, 180]);
      expect(SessionBudget.strengthFocusRestMinMinutes, 60);
    });

    // The allocator prices a NOT-budgeted rep-based row (a user's custom compound, archetype M) at restFor too, so its
    // 6 sets cost 6 x 30 s more under the focus and the budgeted isolation rows (archetype I, no extra rest) get fewer
    // sets. Priced at restForArchetype, the two worlds would be equal (mutation G13).
    test('a custom main lift is priced at the focus rest in the allocator (not-budgeted rows)', () {
      List<(String, int)> run(GoalTraining gt) {
        final f = Fx(goalTraining: gt);
        const names = ['IsoA', 'IsoB', 'IsoC', 'IsoD'];
        const muscles = ['Chest', 'Lats', 'Shoulders', 'Biceps'];
        for (var i = 0; i < names.length; i++) {
          f.row(names[i], [muscles[i]], type: 'isolation', reps: '10-15');
        }
        final days = [
          f.day('moderate', [f.ex('mine', sets: 6, rest: 100, customOrigin: 'user'), for (final n in names) f.ex(n)]),
        ];
        return setsOf(f.run(days, minutes: 60, is6Day: false)[0]);
      }

      expect(run(const GoalTraining()), [('mine', 6), ('IsoA', 4), ('IsoB', 4), ('IsoC', 3), ('IsoD', 3)]);
      expect(run(const GoalTraining(strengthFocus: true)),
          [('mine', 6), ('IsoA', 3), ('IsoB', 3), ('IsoC', 3), ('IsoD', 3)]);
    });

    // `_weekTwoGains` prices week 2's +1 set at restFor too (round 2, seat B): four M rows at 3 sets in a 60-minute day
    // gain 4 sets without the focus and 2 with it (each set costs 30 s more). Priced at restForArchetype, the focus
    // world would gain 4 as well.
    test('week 2 prices the +1 set at the focus rest (PeriodizationEngine.weekTwoGains)', () {
      Set<(int, int)> gains(GoalTraining gt) {
        final f = Fx(goalTraining: gt);
        const names = ['PressA', 'PressB', 'PressC', 'PressD'];
        const muscles = ['Chest', 'Lats', 'Quads', 'Hamstrings'];
        for (var i = 0; i < names.length; i++) {
          f.row(names[i], [muscles[i]]);
        }
        final days = [f.day('hypertrophy', [for (final n in names) f.ex(n, sets: 3)])];
        return PeriodizationEngine.weekTwoGains(days, false, f.ctx(days, minutes: 60), capToLead: false);
      }

      expect(gains(const GoalTraining()), {(0, 0), (0, 1), (0, 2), (0, 3)});
      expect(gains(const GoalTraining(strengthFocus: true)), {(0, 0), (0, 1)});
    });
  });

  group('bands (d3)', () {
    test('Maintain is two-thirds of Build; Cut is fewer than Build at every level; Build unchanged', () {
      expect([for (final l in ['beginner', 'intermediate', 'advanced']) SessionBudget.weeklyBand('general_fitness', l)],
          [(bottom: 7, top: 8), (bottom: 8, top: 11), (bottom: 9, top: 13)]);
      expect([for (final l in ['beginner', 'intermediate', 'advanced']) SessionBudget.weeklyBand('lose_fat', l)],
          [(bottom: 9, top: 11), (bottom: 10, top: 14), (bottom: 12, top: 16)]);
      expect([for (final l in ['beginner', 'intermediate', 'advanced']) SessionBudget.weeklyBand('build_muscle', l)],
          [(bottom: 10, top: 12), (bottom: 12, top: 16), (bottom: 14, top: 20)]);
    });
  });

  group('end to end: PeriodizationEngine.apply stamps the table (week 1 of each phase)', () {
    // press (compound, 6-12), lunge (compound, 10-15: the table's 6 / 8 stop at its floor, d58), raise (isolation,
    // 8-20: the accessory clamp), hold (timed: untouched).
    Fx lib() {
      final f = Fx(balancedWeek: false);
      f.row('press', ['Chest'], reps: '6-12');
      f.row('lunge', ['Quads'], reps: '10-15');
      f.row('raise', ['Shoulders'], type: 'isolation', reps: '8-20');
      return f;
    }

    SessionBudgetContext ctx(Fx f, String goal, String level, {GoalTraining gt = const GoalTraining(), int minutes = 60}) =>
        SessionBudgetContext(
          minutes: minutes,
          planGoal: goal,
          level: level,
          lighterPhase: false,
          focusGroups: const {},
          goalTraining: gt,
          archetypeByName: {for (final e in f.rows.entries) e.key: SessionBudget.archetypeOfRow(e.value)},
        );

    List<String> reps(String goal, String level, int phase, {GoalTraining gt = const GoalTraining()}) {
      final f = lib();
      final day = f.day('hypertrophy', [f.ex('press'), f.ex('lunge'), f.ex('raise')]);
      final weeks = PeriodizationEngine.apply(
          populated: [day], phase: phase, is6Day: true, budget: ctx(f, goal, level, gt: gt), leadFirst: false);
      return [for (final e in weeks.first.workoutDays.first.exercises) e.reps];
    }

    test('Cut intermediate: press 8 / 6 / 8 / 8; lunge stops at its floor 10; the raise sits in 10-15', () {
      expect([for (final ph in [1, 2, 3, 4]) reps('lose_fat', 'intermediate', ph)], [
        ['8', '10', '14'],
        ['6', '10', '10'],
        ['8', '10', '15'],
        ['8', '10', '14'],
      ]);
    });

    test('Maintain beginner: press 10 / 8 / 10 / 10', () {
      expect([for (final ph in [1, 2, 3, 4]) reps('general_fitness', 'beginner', ph)[0]], ['10', '8', '10', '10']);
    });

    test('Build: today (press mid 9 / min 6 / max 12 / mid 9; raise 14 / 8 / 20 / 14, no clamp)', () {
      expect([for (final ph in [1, 2, 3, 4]) reps('build_muscle', 'intermediate', ph)], [
        ['9', '13', '14'],
        ['6', '10', '8'],
        ['12', '15', '20'],
        ['9', '13', '14'],
      ]);
    });

    test('the Strength focus: main lifts at their floor in phases 1-3, the goal\'s rule in the deload', () {
      const focus = GoalTraining(strengthFocus: true);
      expect([for (final ph in [1, 2, 3, 4]) reps('build_muscle', 'intermediate', ph, gt: focus)], [
        ['6', '10', '14'],
        ['6', '10', '8'],
        ['6', '10', '20'],
        ['9', '13', '14'],
      ]);
    });

    // B-pass seat B: weeks 2-4 and the deload stash. The wave runs after the goal's base (weeks 1 / 2 the base, week 3
    // base - 2, week 4 round(0.8 x base)), then the row's range clamp, then (Cut / Maintain accessories) 10-15; the
    // stash `workingReps` is week 3's. A 10-15 clamp skipped after week 1 would leave the phase-2 raise at 8 in weeks 3-4.
    List<List<String>> fourWeeks(String goal, int phase, String name) {
      final f = lib()..row('norange', ['Back'], reps: '');
      final day = f.day('hypertrophy', [f.ex('press'), f.ex('lunge'), f.ex('raise'), f.ex('norange')]);
      final weeks = PeriodizationEngine.apply(
          populated: [day],
          phase: phase,
          is6Day: true,
          budget: ctx(f, goal, 'intermediate'),
          leadFirst: false,
          stashWorkingBase: true);
      String of(List<PlannedExercise> xs, {bool stash = false}) {
        final e = xs.firstWhere((x) => x.exerciseName == name);
        return (stash ? e.workingReps : e.reps) ?? '-';
      }

      return [
        [for (final w in weeks) of(w.workoutDays.first.exercises)],
        [of(weeks[3].workoutDays.first.exercises, stash: true)],
      ];
    }

    test('weeks 1-4 and the stash: wave after the goal base, then the range clamp, then 10-15', () {
      expect(fourWeeks('lose_fat', 1, 'press'), [
        ['8', '8', '6', '6'],
        ['6'],
      ]);
      expect(fourWeeks('lose_fat', 2, 'press'), [
        ['6', '6', '6', '6'],
        ['6'],
      ]);
      expect(fourWeeks('lose_fat', 1, 'raise'), [
        ['14', '14', '12', '11'],
        ['12'],
      ]);
      expect(fourWeeks('lose_fat', 2, 'raise'), [
        ['10', '10', '10', '10'],
        ['10'],
      ]);
      expect(fourWeeks('general_fitness', 1, 'press'), [
        ['10', '10', '8', '8'],
        ['8'],
      ]);
      for (final goal in ['lose_fat', 'general_fitness']) {
        for (final ph in [1, 2, 3, 4]) {
          for (final r in fourWeeks(goal, ph, 'raise')[0]) {
            expect(int.parse(r), inInclusiveRange(10, 15), reason: '$goal phase $ph raise');
          }
        }
      }
    });

    test('a row with no rep range takes the legacy path for every goal (outside the table and the clamp)', () {
      for (final goal in ['lose_fat', 'general_fitness', 'build_muscle']) {
        expect(fourWeeks(goal, 1, 'norange'), [
          ['10', '10', '8', '8'],
          ['8'],
        ], reason: goal);
      }
    });

    test('the stamped rest: 150 + 30 for the press (H) under the focus at 60 minutes, 150 at 45 (d64)', () {
      final f = lib();
      int restAt(int minutes) {
        final day = f.day('hypertrophy', [f.ex('press'), f.ex('raise')]);
        final c = ctx(f, 'build_muscle', 'intermediate', gt: const GoalTraining(strengthFocus: true), minutes: minutes);
        final weeks = PeriodizationEngine.apply(populated: [day], phase: 1, is6Day: true, budget: c, leadFirst: false);
        return weeks.first.workoutDays.first.exercises.first.restSeconds;
      }

      // press is an H row (a compound whose range starts at 6 or lower): 150, +30 under the focus at 60+.
      expect([restAt(45), restAt(60)], [150, 180]);
    });

    test('the allocator prices the focus rest: a full 60-minute day fits fewer sets with it', () {
      final f = Fx(balancedWeek: false);
      for (var i = 0; i < 8; i++) {
        f.row('c$i', [const ['Chest', 'Back', 'Quads', 'Hamstrings', 'Shoulders', 'Glutes', 'Biceps', 'Triceps'][i]]);
      }
      int total(GoalTraining gt) {
        final day = f.day('hypertrophy', [for (var i = 0; i < 8; i++) f.ex('c$i')]);
        final out = SessionSetAllocator.allocate(
            days: [day],
            ctx: ctx(f, 'build_muscle', 'advanced', gt: gt),
            rowsByName: f.rows,
            is6Day: true,
            balancedWeek: false);
        return out.first.exercisesA.fold(0, (a, e) => a + e.sets);
      }

      expect(total(const GoalTraining(strengthFocus: true)), lessThan(total(const GoalTraining())));
    });
  });

  group('quad-first credit for 4-day Maintain (S5)', () {
    test('general_fitness at 4 days; nowhere else new', () {
      bool q(String goal, int days) =>
          SplitResolver.quadPrimaryCreditsGlutes(goal, days, 45, quadLegsB: true, balancedWeek: false);
      expect(q('general_fitness', 4), isFalse, reason: 'a squat does not spend the Glutes top');
      expect([for (final d in [3, 5]) q('general_fitness', d)], [true, true]);
      expect([for (final g in ['lose_fat', 'strength']) q(g, 4)], [true, true]);
    });
  });
}
