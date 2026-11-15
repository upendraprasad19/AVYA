// Unit 3A (OI-487, founder d3 / d4 / d58-d60): the goal's rep table, the Strength focus and its rest, pure.
// The real-engine reach (Cut and Maintain differ in every profile; reps match the table) is the 3A gate.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/goal_reps.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../helpers/session_budget_fixtures.dart';

int base(String goal, String level, String archetype,
        {bool main = true, bool focus = false, bool enabled = true, int min = 6, int max = 12}) =>
    GoalReps.base(
      enabled: enabled,
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

  test('the switch off: today\'s lean for every goal, focus or not', () {
    for (final goal in ['lose_fat', 'general_fitness', 'build_muscle']) {
      expect([for (final a in phases) base(goal, 'beginner', a, enabled: false, focus: true, min: 6, max: 12)],
          [9, 6, 12, 9], reason: goal);
    }
  });

  group('rest (d60)', () {
    test('+30 s on H and M under the Strength focus at 60+ minutes; nothing on I or B; nothing with the switch off', () {
      const focus = GoalTraining(strengthFocus: true);
      int r(String a, GoalTraining gt, int m) => SessionBudget.restForGoal(a, gt, minutes: m);
      expect([for (final a in ['H', 'M', 'I', 'B']) r(a, focus, 60)], [180, 150, 75, 60]);
      expect([for (final a in ['H', 'M', 'I', 'B']) r(a, focus, 90)], [180, 150, 75, 60]);
      expect([for (final a in ['H', 'M', 'I', 'B']) r(a, const GoalTraining(), 60)], [150, 120, 75, 60]);
      expect([for (final a in ['H', 'M']) r(a, const GoalTraining(enabled: false, strengthFocus: true), 60)], [150, 120]);
      expect(r('H', GoalTraining.off, 90), 150);
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
      expect(run(const GoalTraining(enabled: false, strengthFocus: true)), run(const GoalTraining()));
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

    test('the switch off: today\'s bands', () {
      expect(SessionBudget.weeklyBand('general_fitness', 'beginner', goalTraining: false), (bottom: 10, top: 10));
      expect(SessionBudget.weeklyBand('lose_fat', 'beginner', goalTraining: false), (bottom: 10, top: 12));
      expect(SessionBudget.weeklyBand('general_fitness', 'advanced', goalTraining: false), (bottom: 12, top: 14));
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

    test('the switch off equals today for Cut', () {
      expect([for (final ph in [1, 2, 3, 4]) reps('lose_fat', 'intermediate', ph, gt: GoalTraining.off)], [
        ['9', '13', '14'],
        ['6', '10', '8'],
        ['12', '15', '20'],
        ['9', '13', '14'],
      ]);
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
      expect(total(const GoalTraining(enabled: false, strengthFocus: true)), total(const GoalTraining()));
    });
  });

  group('quad-first credit for 4-day Maintain (S5)', () {
    test('general_fitness at 4 days with the switch on; nowhere else new', () {
      bool q(String goal, int days, bool gt) =>
          SplitResolver.quadPrimaryCreditsGlutes(goal, days, 45, quadLegsB: true, balancedWeek: false, goalTraining: gt);
      expect(q('general_fitness', 4, true), isFalse, reason: 'a squat does not spend the Glutes top');
      expect(q('general_fitness', 4, false), isTrue, reason: 'the switch off: today');
      expect([for (final d in [3, 5]) q('general_fitness', d, true)], [true, true]);
      expect([for (final g in ['lose_fat', 'strength']) q(g, 4, true)], [true, true]);
    });
  });
}
