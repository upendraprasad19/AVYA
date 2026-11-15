// Unit 2D (OI-453, plan docs/plans/2026-11-15-generator-step2d-repeat-minutes.md S5): a repeat at more minutes
// carries accessory candidates beside each day (`PopulatedDay.repeatAccessoriesA/B`). `SessionSetAllocator.allocate`
// allocates exactly as before, then appends the candidates that fit the day's PLAIN budget (no under-60 allowance,
// d44), the session cap, the weekly top and the level's exercise count, at 2 sets, then grows them to the base sets.
// Week 2's variant first reserves the +1 sets `PeriodizationEngine.weekTwoGains` grants the allocation, and the week-2
// pass visits the appended rows last and never takes one as the day's lead, so every pinned row keeps its week-2 set.
//
// Pure Dart over crafted fixtures (`session_budget_fixtures.dart`). The real-engine reach is pinned by
// test/plan_generator/repeat_minutes_gate_test.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

Fx lib() {
  final f = Fx();
  f.row('bench', ['Chest']);
  f.row('row', ['Back']);
  f.row('squat', ['Quads']);
  f.row('fly', ['Chest'], type: 'isolation');
  f.row('curl', ['Biceps'], type: 'isolation');
  f.row('pushdown', ['Triceps'], type: 'isolation');
  f.row('raise', ['Shoulders'], type: 'isolation');
  f.row('legext', ['Quads'], type: 'isolation');
  f.row('plank', ['Core'], type: 'isolation', logging: 'timed');
  return f;
}

PopulatedDay rday(List<PlannedExercise> a,
        {List<PlannedExercise>? b, List<PlannedExercise> ca = const [], List<PlannedExercise>? cb}) =>
    PopulatedDay(
      name: 'D',
      focus: 'F',
      dayType: 'push',
      intensity: 'hypertrophy',
      exercisesA: a,
      exercisesB: b ?? a,
      repeatAccessoriesA: ca,
      repeatAccessoriesB: cb ?? ca,
    );

List<String> names(List<PlannedExercise> xs) => [for (final e in xs) e.exerciseName];

void main() {
  group('the step appends after the allocation', () {
    test('time left: the first candidate is seated at 2 then grown to 3 sets after the pins; pins unchanged', () {
      final f = lib();
      final pins = [f.ex('bench'), f.ex('row')];
      final without = f.run([rday(pins)], minutes: 90);
      final withC = f.run([rday(pins, ca: [f.ex('fly'), f.ex('curl')])], minutes: 90);
      expect(setsOf(withC[0]).take(2).toList(), setsOf(without[0]), reason: 'pins keep their sets');
      expect(setsOf(withC[0]).skip(2).toList(), [('fly', 3), ('curl', 3)]);
      expect(withC[0].appendedA, 2);
      expect(SessionSetAllocator.debugLastStats!['A']!.repeatAccessorySeats[0],
          [(name: 'fly', sets: 3), (name: 'curl', sets: 3)]);
    });

    test('no candidates: the allocation is returned as the same object (both 2A paths)', () {
      final f = lib();
      for (final lf in [true, false]) {
        final days = [rday([f.ex('bench'), f.ex('row')])];
        final a = f.run(days, minutes: 90, leadFirst: lf);
        final b = f.run(days, minutes: 90, leadFirst: lf);
        expect([for (final d in a) setsOf(d)], [for (final d in b) setsOf(d)]);
        expect(a[0].appendedA, 0);
      }
    });

    test('the step runs on the lead-first-off path too', () {
      final f = lib();
      final out = f.run([rday([f.ex('bench'), f.ex('row')], ca: [f.ex('curl')])], minutes: 90, leadFirst: false);
      expect(names(out[0].exercisesA), ['bench', 'row', 'curl']);
    });

    test('no time left: nothing is appended', () {
      final f = lib();
      // Seven compounds fill a 30-minute day long before the candidate.
      final pins = [for (final n in ['bench', 'row', 'squat']) f.ex(n)];
      final out = f.run([rday(pins, ca: [f.ex('curl')])], minutes: 30);
      expect(names(out[0].exercisesA), names(pins));
      expect(out[0].appendedA, 0);
    });
  });

  group('the seat checks (seatRepeatVariantForTest)', () {
    test('the level exercise count refuses', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 90, level: 'beginner');
      final max = SessionBudget.countMax('beginner') < SessionBudget.hardMax
          ? SessionBudget.countMax('beginner')
          : SessionBudget.hardMax;
      final rows = [for (var i = 0; i < max; i++) f.ex('c$i', sets: 1, customOrigin: 'user', rest: 10)];
      final seats = SessionSetAllocator.seatRepeatVariantForTest([rows], [[f.ex('curl')]], ctx, f.rows);
      expect(seats[0], isEmpty);
      final fewer = SessionSetAllocator.seatRepeatVariantForTest([rows.sublist(1)], [[f.ex('curl')]], ctx, f.rows);
      expect(names(fewer[0]), ['curl'], reason: 'one under the count, it is seated');
    });

    test('the weekly top refuses, and a same-name row on any day refuses', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 90);
      final ledger = BudgetLedger(ctx, 1);
      final top = ledger.weeklyTop('Chest');
      // Two days whose Chest rows reach the top: no fly fits; a curl does.
      final full = [
        [f.ex('bench', sets: top - 3), f.ex('row')],
        [f.ex('bench', sets: 3), f.ex('curl')],
      ];
      final seats = SessionSetAllocator.seatRepeatVariantForTest(full, [[f.ex('fly'), f.ex('curl')], []], ctx, f.rows);
      expect(names(seats[0]), isEmpty, reason: 'fly: Chest at its top; curl: day 1 already holds a curl');
    });

    test('rank-major across days: rank 0 of every day before rank 1', () {
      final f = lib();
      f.row('curl2', ['Biceps'], type: 'isolation');
      f.row('curl3', ['Biceps'], type: 'isolation');
      f.row('curlp', ['Biceps'], type: 'isolation');
      final ctx = f.ctx(const [], minutes: 90);
      final top = BudgetLedger(ctx, 3).weeklyTop('Biceps');
      // Biceps room for exactly two 2-set seats in the week (a third day holds the rest).
      final rows = [
        [f.ex('bench')],
        [f.ex('squat')],
        [f.ex('curlp', sets: top - 4)],
      ];
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        rows,
        [
          [f.ex('curl'), f.ex('curl2')],
          [f.ex('curl3')],
          const [],
        ],
        ctx,
        f.rows,
      );
      expect(names(seats[0]), ['curl'], reason: "day 0's rank 1 waits for day 1's rank 0");
      expect(names(seats[1]), ['curl3']);
    });

    test('the lead cap: a non-focus accessory never ends more than 1 set above the lead', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 90);
      final seats =
          SessionSetAllocator.seatRepeatVariantForTest([[f.ex('bench', sets: 1)]], [[f.ex('curl')]], ctx, f.rows);
      expect(seats[0].single.sets, 2, reason: 'lead at 1: the accessory stops at 2');
      final focus = f.ctx(const [], minutes: 90, focus: {'Biceps'});
      final seatsF =
          SessionSetAllocator.seatRepeatVariantForTest([[f.ex('bench', sets: 1)]], [[f.ex('curl')]], focus, f.rows);
      expect(seatsF[0].single.sets, 3, reason: 'a focus accessory is exempt (d27)');
      final off = SessionSetAllocator.seatRepeatVariantForTest([[f.ex('bench', sets: 1)]], [[f.ex('curl')]], ctx, f.rows,
          leadFirst: false);
      expect(off[0].single.sets, 3, reason: 'lead-first off: no cap');
    });

    test('the rebuilt plain ledger prices each row as the allocator does (timed: own rest; rep-based custom: archetype rest)',
        () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 60);
      final hold = f.ex('plank', logging: 'timed', sets: 3, rest: 30);
      final custom = f.ex('mine', sets: 3, customOrigin: 'user', rest: 200);
      final bench = f.ex('bench');
      final ledger = SessionSetAllocator.plainLedgerForTest([
        [bench, hold, custom],
      ], ctx, f.rows);
      double at(PlannedExercise e, int rest) =>
          SessionBudget.plannedExerciseSeconds(e, ctx, sets: e.sets, restSeconds: rest);
      int archRest(PlannedExercise e) => SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(e, ctx));
      expect(archRest(hold), isNot(30), reason: 'the fixture must tell the two rests apart');
      expect(archRest(custom), isNot(200));
      final spent = at(bench, archRest(bench)) + at(hold, 30) + at(custom, archRest(custom));
      expect(ledger.secondsLeft(0), closeTo(BudgetLedger(ctx, 1).secondsLeft(0) - spent, 1e-9));
      expect(ledger.week('Chest'), 3, reason: 'only the budgeted bench credits a group');
    });

    test('a candidate that is not budgeted (a custom, a timed row) is never seated', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 90);
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
          [[f.ex('bench')]], [[f.ex('plank', logging: 'timed'), f.ex('mine', customOrigin: 'user')]], ctx, f.rows);
      expect(seats[0], isEmpty);
    });

    test('the plain budget: the under-60 allowance never buys an accessory (d44)', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 45);
      final plain = BudgetLedger(ctx, 1).secondsLeft(0);
      final curl2 = SessionBudget.plannedExerciseSeconds(f.ex('curl'), ctx,
          sets: 2, restSeconds: SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(f.ex('curl'), ctx)));
      // One custom row (it keeps its sets and spends time only) leaves less than a 2-set curl of PLAIN time; the
      // allowance (285 s) would cover it.
      double cost(int sets) => SessionBudget.plannedExerciseSeconds(f.ex('mine', sets: sets, customOrigin: 'user'), ctx,
          sets: sets, restSeconds: SessionBudget.restForArchetype('M'));
      var k = 1;
      while (plain - cost(k) >= curl2) {
        k++;
      }
      expect(plain - cost(k) + SessionBudget.allowanceSeconds, greaterThan(curl2), reason: 'the allowance would fit it');
      List<PlannedExercise> filler(int sets) => [f.ex('mine', sets: sets, customOrigin: 'user')];
      expect(SessionSetAllocator.seatRepeatVariantForTest([filler(k)], [[f.ex('curl')]], ctx, f.rows)[0], isEmpty);
      expect(
          SessionSetAllocator.seatRepeatVariantForTest([filler(k - 2)], [[f.ex('curl')]], ctx, f.rows)[0],
          isNotEmpty,
          reason: 'with the time back, it is seated');
    });
  });

  group('variants', () {
    test('6-day: B is A, the same list object', () {
      final f = lib();
      final out = f.run([rday([f.ex('bench'), f.ex('row')], ca: [f.ex('curl')])], minutes: 90, is6Day: true);
      expect(identical(out[0].exercisesA, out[0].exercisesB), isTrue);
      expect(out[0].appendedB, out[0].appendedA);
    });

    test('non-6-day: B is seated on its own ledger from its own candidates', () {
      final f = lib();
      final out = f.run([
        rday([f.ex('bench'), f.ex('row')], b: [f.ex('squat'), f.ex('row')], ca: [f.ex('curl')], cb: [f.ex('legext')]),
      ], minutes: 90, is6Day: false);
      expect(names(out[0].exercisesA).last, 'curl');
      expect(names(out[0].exercisesB).last, 'legext');
      expect(out[0].appendedB, 1);
    });

    test('the output keeps every field of the allocation, the allowance stamp included', () {
      final f = lib();
      final out = f.run([rday([f.ex('bench'), f.ex('row')], ca: [f.ex('curl')])], minutes: 45);
      final ref = f.run([rday([f.ex('bench'), f.ex('row')])], minutes: 45);
      expect(out[0].allowance, ref[0].allowance);
      expect([out[0].name, out[0].focus, out[0].dayType, out[0].intensity],
          [ref[0].name, ref[0].focus, ref[0].dayType, ref[0].intensity]);
    });
  });

  group('week 2 (PeriodizationEngine)', () {
    List<int> weekTwoSets(List<PopulatedDay> days, SessionBudgetContext ctx, {required bool is6Day}) {
      final weeks = PeriodizationEngine.apply(populated: days, phase: 1, is6Day: is6Day, budget: ctx, leadFirst: true);
      return [for (final e in weeks[1].workoutDays[0].exercises) e.sets];
    }

    test('every pinned row keeps its week-2 set when accessories are appended (the reserve)', () {
      final f = lib();
      // A custom row of k sets moves the day's leftover time through every boundary, so some k leaves room for an
      // accessory OR the week-2 gains, not both.
      for (final (minutes, k, six) in [
        for (final m in [45, 60, 90])
          for (var k = 0; k <= 12; k++)
            for (final six in [true, false]) (m, k, six),
      ]) {
        final pins = [
          f.ex('bench'),
          f.ex('row'),
          f.ex('squat'),
          if (k > 0) f.ex('mine', sets: k, customOrigin: 'user'),
        ];
        final ctx = f.ctx(const [], minutes: minutes);
        final without = f.run([rday(pins)], minutes: minutes, is6Day: six);
        final withC = f.run([
          rday(pins, ca: [f.ex('fly'), f.ex('curl'), f.ex('pushdown'), f.ex('raise'), f.ex('legext')]),
        ], minutes: minutes, is6Day: six);
        final w0 = weekTwoSets(without, ctx, is6Day: six);
        final w1 = weekTwoSets(withC, ctx, is6Day: six);
        expect(w1.take(w0.length).toList(), w0, reason: 'at $minutes minutes, filler $k sets, 6-day $six');
      }
    });

    test('an appended row is never the week-2 lead: a custom-only day keeps its gain', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 90);
      final custom = f.ex('mine', sets: 4, customOrigin: 'user', rest: 60);
      final day = PopulatedDay(
        name: 'D',
        focus: 'F',
        dayType: 'push',
        intensity: 'hypertrophy',
        exercisesA: [custom],
        exercisesB: [custom, f.ex('curl', sets: 2)],
        appendedB: 1,
      );
      final gains = PeriodizationEngine.weekTwoGains([day], true, ctx, capToLead: true);
      expect(gains.contains((0, 0)), isTrue,
          reason: 'the custom gains: with the appended curl as the lead (2 sets) it would be capped at 3');
    });
  });
}
