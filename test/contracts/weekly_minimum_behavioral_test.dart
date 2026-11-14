// Unit 2C-b, S3 (docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md, founder d35 / d38 / d45 / d49): the
// weekly minimum. A variant's targets are (1, d35) a group the other variant credits and this one does not, (2, d38) a
// focus group it does not credit and (3) a protective group R or step 1 credits that a re-run zeroed; Calves under 45
// minutes is never a target. Credit counts a kept library hold's groups (`AllocationStats.credited`). After pass A,
// A2 and the floor, the minimum pass seats each target still at 0 on its cheapest remaining slot at 2 sets: never an
// admitted, reservation-blocked or count-refused slot, never past the day's admitted-row target, a session cap or
// another group's weekly top, and within the ledger's forcing bound (300 s at 60+, 0 with the allowance). Seats go to
// `AllocationStats.minimumSeats` (B inherits A's on copied days), never to `countForced`. 2C-b runs only on the
// lead-first path with the floor ON; the kill switch reaches it as `allocate(balancedWeek:)`.
//
// Pure Dart over crafted fixtures (each worked by a probe run, then checked against the rule): two 60-minute days of a
// bench press plus four custom rows (customs keep their sets and spend the day's time: 18 s are left after them and
// the bench), then a curl the clock refuses (256.8 s at 2 sets: within the 300 s forcing bound, not within the 18 s
// left). Variant B trains Biceps; A does not, so Biceps is A's target 1. The walk, the protect-first step, the
// fallback and the row cap's effect on real plans are pinned on the real engine by weekly_minimum_gate_test.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/budget_invariant_oracle.dart';
import '../helpers/session_budget_fixtures.dart';

AllocationStats statsA() => SessionSetAllocator.debugLastStats!['A']!;
AllocationStats statsB() => SessionSetAllocator.debugLastStats!['B']!;

Map<int, List<String>> seats(AllocationStats s) => {
      for (final e in s.minimumSeats.entries) e.key: [for (final m in e.value) '${m.name}:${m.group}'],
    };

bool hasCurl(List<PopulatedDay> out) => out.any((d) => d.exercisesA.any((e) => e.exerciseName == 'curlA'));

Fx base({List<String> curl = const ['Biceps']}) {
  final f = Fx();
  f.row('bench', ['Chest']);
  f.row('curlA', curl, type: 'isolation');
  f.row('curlB', ['Biceps'], type: 'isolation');
  f.row('fly', ['Chest'], type: 'isolation');
  f.row('dip', ['Chest'], reps: '6-10');
  f.row('curlhold', ['Biceps'], type: 'isolation', logging: 'timed');
  return f;
}

/// Two days: A = [bench, customs (sets [cs]), (curlhold), curlA], B = [bench, curlB, fly]; plus [extraChestDays] days of
/// three Chest rows (the same list in both variants, so B copies them).
List<PopulatedDay> week(Fx f, List<int> cs, {bool hold = false, int extraChestDays = 0, List<int>? day1}) {
  List<PlannedExercise> cus(String p, List<int> sets) =>
      [for (var i = 0; i < sets.length; i++) f.ex('$p$i', sets: sets[i], rest: 100, customOrigin: 'user')];
  List<PlannedExercise> dayA(String p, List<int> sets) => [
        f.ex('bench'),
        ...cus(p, sets),
        if (hold) f.ex('curlhold', logging: 'timed', sets: 3, rest: 30),
        f.ex('curlA'),
      ];
  final dB = [f.ex('bench'), f.ex('curlB'), f.ex('fly')];
  final a1 = dayA('cv', day1 ?? cs);
  return [
    f.day('hypertrophy', dayA('cu', cs), b: dB),
    f.day('hypertrophy', a1, b: day1 == null ? dB : a1),
    for (var i = 0; i < extraChestDays; i++) f.day('hypertrophy', [f.ex('bench'), f.ex('dip'), f.ex('fly')]),
  ];
}

/// A row's seconds as the allocator prices it.
double priced(PlannedExercise e, SessionBudgetContext ctx) {
  final rest = SessionBudget.isBudgeted(e, ctx) || SessionBudget.isRepBased(e.loggingType)
      ? SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(e, ctx))
      : e.restSeconds;
  return SessionBudget.plannedExerciseSeconds(e, ctx, sets: e.sets, restSeconds: rest);
}

/// The shared oracle's time check over variant A: a minimum seat is excused within the forcing bound.
void expectTime(List<PopulatedDay> out, AllocationStats s, SessionBudgetContext ctx) {
  final ledger = BudgetLedger(ctx, out.length);
  for (var d = 0; d < out.length; d++) {
    for (final e in out[d].exercisesA) {
      final budgeted = SessionBudget.isBudgeted(e, ctx);
      ledger.add(d, budgeted ? BudgetMuscleGroups.creditedOf(e.primaryMuscles ?? const []) : const {},
          budgeted ? e.sets : 0, priced(e, ctx));
    }
    final excused = BudgetInvariantOracle.excusedSeconds(s, d, out[d].exercisesA, (e) => priced(e, ctx),
        maxForcedOverSeconds: SessionBudget.maxForcedOverSeconds.toDouble());
    expect(-ledger.secondsLeft(d), lessThanOrEqualTo(excused + 1e-6), reason: 'day $d time');
  }
}

void main() {
  group('target 1 (d35) and the minimum pass', () {
    test('A\'s clock-refused curl is seated at 2 sets for Biceps, which B trains; never count-forced; off: no curl', () {
      final f = base();
      final days = week(f, const [4, 4, 4, 3]);
      final off = f.run(days, minutes: 60, is6Day: false, balancedWeek: false);
      expect(hasCurl(off), isFalse, reason: 'fixture: R leaves A without Biceps');
      expect(statsA().credited.containsKey('Biceps'), isFalse);
      expect(statsB().credited['Biceps'], greaterThan(0), reason: 'fixture: B trains Biceps');
      expect(statsA().minimumSeats, isEmpty);

      final on = f.run(days, minutes: 60, is6Day: false, balancedWeek: true);
      expect(setsOf(on[0]), [('bench', 2), ('cu0', 4), ('cu1', 4), ('cu2', 4), ('cu3', 3), ('curlA', 2)]);
      expect(setsOf(on[1]), [('bench', 2), ('cv0', 4), ('cv1', 4), ('cv2', 4), ('cv3', 3)],
          reason: 'one seat: Biceps is no longer at 0');
      expect(seats(statsA()), {0: ['curlA:Biceps']});
      expect(statsA().countForced, isEmpty, reason: 'a minimum seat is never count-forced');
      expect(statsA().credited['Biceps'], 2);
      expect(on.first.allowance, isFalse, reason: '60 minutes: no allowance');
      // Within the forcing bound: the seat runs the day 238.8 s past its budget, excused as a minimum seat.
      expectTime(on, statsA(), f.ctx(days, minutes: 60));
    });

    test('the forcing bound: a curl that would run the day more than 300 s over is not seated', () {
      final f = base();
      final days = week(f, const [4, 4, 4, 4]); // 168 s over before the curl: + 256.8 > 300
      final on = f.run(days, minutes: 60, is6Day: false, balancedWeek: true);
      expect(hasCurl(on), isFalse);
      expect(statsA().minimumSeats, isEmpty);
    });

    test('the count: a day at its admitted-row target refuses (beginner, max 5: four customs + the bench)', () {
      final f = base();
      final days = week(f, const [4, 4, 4, 3]);
      final on = f.run(days, minutes: 60, level: 'beginner', is6Day: false, balancedWeek: true);
      expect(hasCurl(on), isFalse);
      expect(statsA().minimumSeats, isEmpty);
    });

    test('another group\'s weekly top: a curl that also credits Chest, past its top, is not seated', () {
      final f = base(curl: const ['Biceps', 'Chest']);
      final days = week(f, const [4, 4, 4, 3], extraChestDays: 3);
      final on = f.run(days, minutes: 60, is6Day: false, balancedWeek: true);
      expect(statsA().weekly['Chest'], greaterThanOrEqualTo(SessionBudget.weeklyBand('build_muscle', 'intermediate').top),
          reason: 'fixture: Chest at or past its top');
      expect(hasCurl(on), isFalse);
      expect(statsA().minimumSeats, isEmpty);
    });

    test('a copied B day inherits A\'s minimum seat on it', () {
      final f = base();
      // Day 0 cannot take the curl (the forcing bound); day 1 can, and B copies day 1 (same list in both variants).
      final days = week(f, const [4, 4, 4, 4], day1: const [4, 4, 4, 3]);
      final on = f.run(days, minutes: 60, is6Day: false, balancedWeek: true);
      expect(seats(statsA()), {1: ['curlA:Biceps']});
      expect(seats(statsB()), {1: ['curlA:Biceps']});
      expect(setsOf(on[1], b: true), setsOf(on[1]));
    });
  });

  group('target 2 (d38), hold credit', () {
    test('a focus group the plan does not train is seated (the 6-day branch: no target 1)', () {
      final f = base();
      final days = week(f, const [4, 4, 4, 3]);
      final off = f.run(days, minutes: 60, focus: const {'Biceps'}, is6Day: true, balancedWeek: false);
      expect(hasCurl(off), isFalse);
      final on = f.run(days, minutes: 60, focus: const {'Biceps'}, is6Day: true, balancedWeek: true);
      expect(setsOf(on[0]).last, ('curlA', 2));
      expect(seats(statsA()), {0: ['curlA:Biceps']});
      // Without the focus nothing on the 6-day path is a target.
      final plain = f.run(days, minutes: 60, is6Day: true, balancedWeek: true);
      expect(hasCurl(plain), isFalse);
      expect(statsA().minimumSeats, isEmpty);
    });

    test('a group only a kept hold trains is credited, so it is not a target (advanced: room for a row)', () {
      final f = base();
      final days = week(f, const [4, 3, 3, 3], hold: true);
      final on = f.run(days, minutes: 60, level: 'advanced', is6Day: false, balancedWeek: true);
      expect(statsA().weekly.containsKey('Biceps'), isFalse, reason: 'fixture: no budgeted Biceps in A');
      expect(statsA().holdGroups, {'Biceps'});
      expect(statsA().credited['Biceps'], 1);
      expect(hasCurl(on), isFalse);
      expect(statsA().minimumSeats, isEmpty);
    });
  });

  group('where it runs', () {
    test('2A off and 2B off are the pre-2C-b allocation whatever the switch; the switch off is R', () {
      final f = base();
      final days = week(f, const [4, 4, 4, 3]);
      for (final (lf, fl) in const [(false, true), (true, false), (false, false)]) {
        final off = f.run(days, minutes: 60, is6Day: false, leadFirst: lf, dayFloor: fl, balancedWeek: false);
        final on = f.run(days, minutes: 60, is6Day: false, leadFirst: lf, dayFloor: fl, balancedWeek: true);
        expect([for (final d in on) setsOf(d)], [for (final d in off) setsOf(d)], reason: 'leadFirst $lf dayFloor $fl');
        expect([for (final d in on) setsOf(d, b: true)], [for (final d in off) setsOf(d, b: true)]);
        expect(statsA().minimumSeats, isEmpty);
        expect(on.every((d) => !d.allowance), isTrue);
      }
    });

    test('Calves under 45 is never a target: a 30-minute 6-day Calves focus leaves A without Calves', () {
      final f = Fx();
      for (final n in ['p1', 'p2']) {
        f.row(n, ['Chest']);
      }
      f.row('row1', ['Lats']);
      f.row('sq', ['Quads']);
      f.row('curlA', ['Biceps'], type: 'isolation');
      f.row('calfA', ['Gastrocnemius'], type: 'isolation');
      final dA = [f.ex('p1'), f.ex('row1'), f.ex('sq'), f.ex('p2'), f.ex('curlA'), f.ex('calfA')];
      final days = [f.day('hypertrophy', dA), f.day('hypertrophy', dA)];
      final on = f.run(days, minutes: 30, focus: const {'Calves'}, is6Day: true, balancedWeek: true);
      expect(on.any((d) => d.exercisesA.any((e) => e.exerciseName == 'calfA')), isFalse);
      expect(statsA().credited.containsKey('Calves'), isFalse);
      expect(statsA().minimumSeats, isEmpty);
    });

    test('Calves under 45, the 5-day path (d49): a 30-minute Calves focus is not a target, so the walk keeps R', () {
      final f = Fx();
      for (final n in ['p1', 'p2']) {
        f.row(n, ['Chest']);
      }
      f.row('row1', ['Lats']);
      f.row('sq', ['Quads']);
      f.row('calfA', ['Gastrocnemius'], type: 'isolation');
      final dA = [f.ex('p1'), f.ex('row1'), f.ex('sq'), f.ex('p2'), f.ex('calfA')];
      final days = [f.day('hypertrophy', dA), f.day('hypertrophy', dA)];
      final on = f.run(days, minutes: 30, focus: const {'Calves'}, is6Day: false, balancedWeek: true);
      // A Calves target would walk calfA in ahead of p2 on day 0 (measured: [p1 3, row1 3, sq 2, calfA 2]).
      for (final d in on) {
        expect(setsOf(d), [('p1', 3), ('row1', 3), ('sq', 2), ('p2', 2)]);
      }
      expect(statsA().credited.containsKey('Calves'), isFalse);
      expect(statsA().minimumSeats, isEmpty);
      // At 45 the focus is honoured as before (calfA in R already).
      final at45 = f.run(days, minutes: 45, focus: const {'Calves'}, is6Day: false, balancedWeek: true);
      expect(at45.every((d) => d.exercisesA.any((e) => e.exerciseName == 'calfA')), isTrue);
    });
  });
}
