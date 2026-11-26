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

PopulatedDay rday(
  List<PlannedExercise> a, {
  List<PlannedExercise>? b,
  List<PlannedExercise> ca = const [],
  List<PlannedExercise>? cb,
}) => PopulatedDay(
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
      final withC = f.run([
        rday(pins, ca: [f.ex('fly'), f.ex('curl')]),
      ], minutes: 90);
      expect(setsOf(withC[0]).take(2).toList(), setsOf(without[0]), reason: 'pins keep their sets');
      expect(setsOf(withC[0]).skip(2).toList(), [('fly', 3), ('curl', 3)]);
      expect(withC[0].appendedA, 2);
      expect(SessionSetAllocator.debugLastStats!['A']!.repeatAccessorySeats[0], [
        (name: 'fly', sets: 3),
        (name: 'curl', sets: 3),
      ]);
    });

    test('no candidates, or none that fit: allocate equals the core allocation (both 2A paths, both variants)', () {
      final f = lib();
      List<Object> shape(List<PopulatedDay> out) => [
        for (final d in out) ...[setsOf(d), setsOf(d, b: true), d.allowance, d.appendedA, d.appendedB],
      ];
      for (final lf in [true, false]) {
        for (final (minutes, days) in [
          (
            90,
            [
              rday([f.ex('bench'), f.ex('row')], b: [f.ex('squat'), f.ex('row')]),
            ],
          ),
          (
            45,
            [
              rday([f.ex('bench'), f.ex('row')]),
              rday([f.ex('squat')]),
            ],
          ),
          // A candidate that cannot fit (no time left at 30 minutes) leaves the core allocation as it was.
          (
            30,
            [
              rday(
                [
                  for (final x in ['bench', 'row', 'squat']) f.ex(x),
                ],
                ca: [f.ex('curl')],
              ),
            ],
          ),
        ]) {
          for (final six in [true, false]) {
            final ctx = f.ctx(days, minutes: minutes);
            final core = SessionSetAllocator.allocateCoreForTest(
              days: days,
              ctx: ctx,
              rowsByName: f.rows,
              is6Day: six,
              leadFirst: lf,
            );
            final out = f.run(days, minutes: minutes, leadFirst: lf, is6Day: six);
            expect(shape(out), shape(core), reason: 'leadFirst $lf, $minutes minutes, 6-day $six');
            expect(out.every((d) => d.appendedA == 0 && d.appendedB == 0), isTrue);
          }
        }
      }
    });

    test('the step runs on the lead-first-off path too', () {
      final f = lib();
      final out = f.run(
        [
          rday([f.ex('bench'), f.ex('row')], ca: [f.ex('curl')]),
        ],
        minutes: 90,
        leadFirst: false,
      );
      expect(names(out[0].exercisesA), ['bench', 'row', 'curl']);
    });

    test('no time left: nothing is appended', () {
      final f = lib();
      // Three compounds at the allocator's sets fill a 30-minute day: no time is left for the 2-set curl.
      final pins = [
        for (final n in ['bench', 'row', 'squat']) f.ex(n),
      ];
      final out = f.run([
        rday(pins, ca: [f.ex('curl')]),
      ], minutes: 30);
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
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        [rows],
        [
          [f.ex('curl')],
        ],
        ctx,
        f.rows,
      );
      expect(seats[0], isEmpty);
      final fewer = SessionSetAllocator.seatRepeatVariantForTest(
        [rows.sublist(1)],
        [
          [f.ex('curl')],
        ],
        ctx,
        f.rows,
      );
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
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        full,
        [
          [f.ex('fly'), f.ex('curl')],
          [],
        ],
        ctx,
        f.rows,
      );
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
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        [
          [f.ex('bench', sets: 1)],
        ],
        [
          [f.ex('curl')],
        ],
        ctx,
        f.rows,
      );
      expect(seats[0].single.sets, 2, reason: 'lead at 1: the accessory stops at 2');
      final focus = f.ctx(const [], minutes: 90, focus: {'Biceps'});
      final seatsF = SessionSetAllocator.seatRepeatVariantForTest(
        [
          [f.ex('bench', sets: 1)],
        ],
        [
          [f.ex('curl')],
        ],
        focus,
        f.rows,
      );
      expect(seatsF[0].single.sets, 3, reason: 'a focus accessory is exempt (d27)');
      final off = SessionSetAllocator.seatRepeatVariantForTest(
        [
          [f.ex('bench', sets: 1)],
        ],
        [
          [f.ex('curl')],
        ],
        ctx,
        f.rows,
        leadFirst: false,
      );
      expect(off[0].single.sets, 3, reason: 'lead-first off: no cap');
    });

    test(
      'the rebuilt plain ledger prices each row as the allocator does (timed: own rest; rep-based custom: archetype rest)',
      () {
        final f = lib();
        final ctx = f.ctx(const [], minutes: 60);
        final hold = f.ex('plank', logging: 'timed', sets: 3, rest: 30);
        final custom = f.ex('mine', sets: 3, customOrigin: 'user', rest: 200);
        final bench = f.ex('bench');
        final ledger = SessionSetAllocator.plainLedgerForTest(
          [
            [bench, hold, custom],
          ],
          ctx,
          f.rows,
        );
        double at(PlannedExercise e, int rest) =>
            SessionBudget.plannedExerciseSeconds(e, ctx, sets: e.sets, restSeconds: rest);
        int archRest(PlannedExercise e) => SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(e, ctx));
        expect(archRest(hold), isNot(30), reason: 'the fixture must tell the two rests apart');
        expect(archRest(custom), isNot(200));
        final spent = at(bench, archRest(bench)) + at(hold, 30) + at(custom, archRest(custom));
        expect(ledger.secondsLeft(0), closeTo(BudgetLedger(ctx, 1).secondsLeft(0) - spent, 1e-9));
        expect(ledger.week('Chest'), 3, reason: 'only the budgeted bench credits a group');
      },
    );

    test('a candidate that is not budgeted (a custom, a timed row) is never seated', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 90);
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        [
          [f.ex('bench')],
        ],
        [
          [f.ex('plank', logging: 'timed'), f.ex('mine', customOrigin: 'user')],
        ],
        ctx,
        f.rows,
      );
      expect(seats[0], isEmpty);
    });

    test('the plain budget: the under-60 allowance never buys an accessory (d44)', () {
      final f = lib();
      final ctx = f.ctx(const [], minutes: 45);
      final plain = BudgetLedger(ctx, 1).secondsLeft(0);
      final curl2 = SessionBudget.plannedExerciseSeconds(
        f.ex('curl'),
        ctx,
        sets: 2,
        restSeconds: SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(f.ex('curl'), ctx)),
      );
      // One custom row (it keeps its sets and spends time only) leaves less than a 2-set curl of PLAIN time; the
      // allowance (285 s) would cover it.
      double cost(int sets) => SessionBudget.plannedExerciseSeconds(
        f.ex('mine', sets: sets, customOrigin: 'user'),
        ctx,
        sets: sets,
        restSeconds: SessionBudget.restForArchetype('M'),
      );
      var k = 1;
      while (plain - cost(k) >= curl2) {
        k++;
      }
      expect(
        plain - cost(k) + SessionBudget.allowanceSeconds,
        greaterThan(curl2),
        reason: 'the allowance would fit it',
      );
      List<PlannedExercise> filler(int sets) => [f.ex('mine', sets: sets, customOrigin: 'user')];
      expect(
        SessionSetAllocator.seatRepeatVariantForTest(
          [filler(k)],
          [
            [f.ex('curl')],
          ],
          ctx,
          f.rows,
        )[0],
        isEmpty,
      );
      expect(
        SessionSetAllocator.seatRepeatVariantForTest(
          [filler(k - 2)],
          [
            [f.ex('curl')],
          ],
          ctx,
          f.rows,
        )[0],
        isNotEmpty,
        reason: 'with the time back, it is seated',
      );
    });
  });

  group('variants', () {
    test('6-day: B is A, the same list object', () {
      final f = lib();
      final out = f.run(
        [
          rday([f.ex('bench'), f.ex('row')], ca: [f.ex('curl')]),
        ],
        minutes: 90,
        is6Day: true,
      );
      expect(identical(out[0].exercisesA, out[0].exercisesB), isTrue);
      expect(out[0].appendedB, out[0].appendedA);
    });

    test('non-6-day: B is seated on its own ledger from its own candidates', () {
      final f = lib();
      final out = f.run(
        [
          rday([f.ex('bench'), f.ex('row')], b: [f.ex('squat'), f.ex('row')], ca: [f.ex('curl')], cb: [f.ex('legext')]),
        ],
        minutes: 90,
        is6Day: false,
      );
      expect(names(out[0].exercisesA).last, 'curl');
      expect(names(out[0].exercisesB).last, 'legext');
      expect(out[0].appendedB, 1);
    });

    test('the output keeps every field of the allocation, the allowance stamp included', () {
      final f = lib();
      final out = f.run([
        rday([f.ex('bench'), f.ex('row')], ca: [f.ex('curl')]),
      ], minutes: 45);
      final ref = f.run([
        rday([f.ex('bench'), f.ex('row')]),
      ], minutes: 45);
      expect(out[0].allowance, ref[0].allowance);
      expect(
        [out[0].name, out[0].focus, out[0].dayType, out[0].intensity],
        [ref[0].name, ref[0].focus, ref[0].dayType, ref[0].intensity],
      );
    });
  });

  group('the 1e-6 margin (B-pass seat B, finding 5)', () {
    // Costs carry the 1.20 time factor, so a seat that fills the plain day to the second can read as over by a rounding
    // error once the week-2 pass sums the same rows in another order. The seat therefore refuses an exact fill. A custom
    // filler's rest is searched for a day whose leftover equals the seat's cost (to under 1e-6); a timed custom keeps its own rest.
    ({SessionBudgetContext ctx, PlannedExercise filler})? exactFill(Fx f, int sets) {
      final curl = f.ex('curl');
      for (final minutes in [45, 60, 90]) {
        final ctx = f.ctx(const [], minutes: minutes);
        final arch = SessionBudget.archetypeOfPlanned(curl, ctx);
        final rest = SessionBudget.restForArchetype(arch);
        final need = SessionBudget.exerciseSeconds(archetype: arch, sets: sets, restSeconds: rest);
        for (var k = 1; k <= 8; k++) {
          for (var r = 0; r <= 400; r++) {
            final filler = f.ex('mine', sets: k, logging: 'timed', customOrigin: 'user', rest: r);
            final left = SessionSetAllocator.plainLedgerForTest(
              [
                [filler],
              ],
              ctx,
              f.rows,
            ).secondsLeft(0);
            if (left - need >= 0 && left - need < 1e-6) return (ctx: ctx, filler: filler);
          }
        }
      }
      return null;
    }

    test('a 2-set seat that would fill the day exactly is refused', () {
      final f = lib();
      final fx = exactFill(f, 2);
      expect(fx, isNotNull, reason: 'the search must find an exact fill');
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        [
          [fx!.filler],
        ],
        [
          [f.ex('curl')],
        ],
        fx.ctx,
        f.rows,
      );
      expect(seats[0], isEmpty);
    });

    test('a grow to 3 sets that would fill the day exactly stops at 2', () {
      final f = lib();
      final fx = exactFill(f, 3);
      expect(fx, isNotNull, reason: 'the search must find an exact fill');
      final seats = SessionSetAllocator.seatRepeatVariantForTest(
        [
          [fx!.filler],
        ],
        [
          [f.ex('curl')],
        ],
        fx.ctx,
        f.rows,
      );
      expect([for (final e in seats[0]) e.sets], [2]);
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
        final withC = f.run(
          [
            rday(pins, ca: [f.ex('fly'), f.ex('curl'), f.ex('pushdown'), f.ex('raise'), f.ex('legext')]),
          ],
          minutes: minutes,
          is6Day: six,
        );
        final w0 = weekTwoSets(without, ctx, is6Day: six);
        final w1 = weekTwoSets(withC, ctx, is6Day: six);
        expect(w1.take(w0.length).toList(), w0, reason: 'at $minutes minutes, filler $k sets, 6-day $six');
      }
    });

    test('two days with different A and B lists: every pinned row of every day keeps its week-2 set', () {
      // B-pass seat B, finding 1: a one-day fixture whose A and B lists are equal cannot see a reserve taken from the
      // wrong variant or booked on the wrong day, nor a gain on one day spending the weekly top an appended row needs
      // on another. Chest rows on both days walk the Chest week toward its top.
      final f = lib();
      for (var i = 0; i < 8; i++) {
        f.row('press$i', ['Chest']);
      }
      List<List<int>> allWeekTwo(List<PopulatedDay> days, SessionBudgetContext ctx, bool six) {
        final weeks = PeriodizationEngine.apply(populated: days, phase: 1, is6Day: six, budget: ctx, leadFirst: true);
        return [
          for (final d in weeks[1].workoutDays) [for (final e in d.exercises) e.sets],
        ];
      }

      var compared = 0;
      for (final minutes in [60, 90]) {
        for (var k = 0; k <= 7; k++) {
          for (final six in [true, false]) {
            for (var j = 0; j <= 10; j++) {
              final aDay0 = [f.ex('bench'), f.ex('row')];
              final bDay0 = [f.ex('squat'), f.ex('row'), for (var i = 0; i < k ~/ 2; i++) f.ex('press$i')];
              final aDay1 = [f.ex('row'), f.ex('squat')];
              // A custom filler of j sets on day 1's B list walks that day's leftover time through every boundary, so a
              // reserve booked on the wrong day shows.
              final bDay1 = [
                f.ex('bench'),
                for (var i = k ~/ 2; i < k; i++) f.ex('press$i'),
                if (j > 0) f.ex('mine', sets: j, customOrigin: 'user'),
              ];
              List<PopulatedDay> days({required bool cands}) => [
                rday(aDay0, b: bDay0, ca: cands ? [f.ex('curl')] : const [], cb: cands ? [f.ex('fly')] : const []),
                rday(
                  aDay1,
                  b: bDay1,
                  ca: cands ? [f.ex('fly'), f.ex('raise')] : const [],
                  cb: cands ? [f.ex('curl'), f.ex('pushdown')] : const [],
                ),
              ];
              final ctx = f.ctx(const [], minutes: minutes);
              final w0 = allWeekTwo(f.run(days(cands: false), minutes: minutes, is6Day: six), ctx, six);
              final w1 = allWeekTwo(f.run(days(cands: true), minutes: minutes, is6Day: six), ctx, six);
              for (var d = 0; d < w0.length; d++) {
                expect(
                  w1[d].take(w0[d].length).toList(),
                  w0[d],
                  reason: 'day $d at $minutes minutes, $k Chest rows, filler $j, 6-day $six',
                );
                compared++;
              }
            }
          }
        }
      }
      expect(compared, 704);
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
      expect(
        gains.contains((0, 0)),
        isTrue,
        reason: 'the custom gains: with the appended curl as the lead (2 sets) it would be capped at 3',
      );
    });
  });
}
