// Unit 2B (OI-452, docs/plans/2026-11-13-generator-step2b-day-floor.md, founder d30-d33): the 3-exercise day floor.
// After pass A2, a day whose rows (budgeted and not) are under min(3, its reach) seats a remaining slot at 2 sets past
// a group's weekly top: no limit on the excess (d30), in every phase (d31), up to its reach (d32), not bound by the
// clock (d33); never past a session cap, never a slot the rank-0 reservation blocked. Choice (F2): the fewest groups
// over their top, then the least excess, then the cheapest; ties to the lowest rank. F3: the Unit 2A worlds are chosen
// with the floor off, then the chosen A and B are re-run with it on (B copying the floored A). F4: each seat is
// recorded in `AllocationStats.floorSeats` with `overTop` and `overClock`; a floor seat is never in `countForced`; a
// day's `belowCount` label is the one pass A2 left, taken before the floor. Kill switch `disable_day_floor`
// (`PlanEngineFlags.dayFloorEnabled`, default ON), overridable by `allocate(dayFloor:)`, in both 2A paths.
//
// Pure Dart over crafted fixtures (plus a Hive config box for the kill-switch group). Every expected list was worked
// by hand from the rule and the budget's time model, then run: a compound ('M', 120 s rest) costs 336 s at 2 sets,
// an isolation ('I', 75 s) 256.8 s; day budgets 840 s at 20 minutes (count floor 3), 1440 s at 30 (floor 4), 3000 s
// at 60 (floor 5). Bands: build_muscle intermediate top 16 / cap 8 (lighter: top 12), beginner top 12 / cap 6;
// general_fitness beginner top 10 / cap 6. Pass A seats in rank order across the days (all rank 0 first), at 2 sets.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/budget_invariant_oracle.dart';
import '../helpers/session_budget_fixtures.dart';

AllocationStats statsA() => SessionSetAllocator.debugLastStats!['A']!;
AllocationStats statsB() => SessionSetAllocator.debugLastStats!['B']!;

/// A floor seat as `name:sets:overTop groups:overClock` (records holding a List do not compare by value).
String seat(FloorSeat s) => '${s.name}:${s.sets}:${s.overTop.join('+')}:${s.overClock}';
Map<int, List<String>> seats(AllocationStats s) => {
      for (final e in s.floorSeats.entries) e.key: [for (final x in e.value) seat(x)],
    };
List<int> rows(List<PopulatedDay> out, {bool b = false}) =>
    [for (final d in out) (b ? d.exercisesB : d.exercisesA).length];

/// A row's seconds as the allocator and week 2 price it (`PeriodizationEngine._weekTwoGains`' rule).
double priced(PlannedExercise e, SessionBudgetContext ctx) {
  final rest = SessionBudget.isBudgeted(e, ctx) || SessionBudget.isRepBased(e.loggingType)
      ? SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(e, ctx))
      : e.restSeconds;
  return SessionBudget.plannedExerciseSeconds(e, ctx, sets: e.sets, restSeconds: rest);
}

/// Checks the restated invariant (the shared oracle) over one allocated variant: week <= top + the floor's over-top
/// sets, the session cap, time <= budget + the excused seconds; and that no floor seat is count-forced.
void expectOracle(Fx _, List<PopulatedDay> out, AllocationStats s, SessionBudgetContext ctx, {bool b = false}) {
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
        priced(e, ctx),
      );
    }
    final excused = BudgetInvariantOracle.excusedSeconds(s, d, list, (e) => priced(e, ctx),
        maxForcedOverSeconds: SessionBudget.maxForcedOverSeconds.toDouble());
    expect(-ledger.secondsLeft(d), lessThanOrEqualTo(excused + 1e-6), reason: 'day $d time');
  }
  for (final g in BudgetMuscleGroups.groups) {
    expect(ledger.week(g), lessThanOrEqualTo(BudgetInvariantOracle.weekCeiling(ledger.weeklyTop(g), s, g)),
        reason: '$g week');
    for (var d = 0; d < out.length; d++) {
      expect(ledger.session(d, g), lessThanOrEqualTo(ledger.cap(g)), reason: '$g day $d session');
    }
  }
  expect(BudgetInvariantOracle.floorSeatsDisjointFromCountForced(s), isTrue);
}

/// Five days of five Back compounds (`Row dr`), build_muscle intermediate unless stated.
Fx fiveByFive() {
  final f = Fx();
  for (var d = 0; d < 5; d++) {
    for (var r = 0; r < 5; r++) {
      f.row('Row $d$r', ['Lats']);
    }
  }
  return f;
}

List<PopulatedDay> fiveByFiveDays(Fx f, {List<int> perDay = const [5, 5, 5, 5, 5]}) => [
      for (var d = 0; d < 5; d++) f.day('hypertrophy', [for (var r = 0; r < perDay[d]; r++) f.ex('Row $d$r')]),
    ];

void main() {
  group('F1. the rule', () {
    test('seats past the weekly top: five Back days, 60 minutes, every day ends at 3 rows', () {
      // Pass A: rank 0 on all five days (Back 10), rank 1 on days 0-2 (16, the top); the rest are refused by the top
      // ([2, 2, 2, 1, 1] rows; reach 5 = the count floor, so pass A2 runs and refuses them too: `cap_top`). The floor,
      // one seat per day per round: round 1 seats each day's next slot (rank order: equal groups, excess and cost), round
      // 2 the second on days 3 and 4. Back ends at 16 + 7 seats x 2 = 30, every seat over the top, none over the clock.
      for (final lf in [false, true]) {
        final f = fiveByFive();
        final days = fiveByFiveDays(f);
        final out = f.run(days, leadFirst: lf, dayFloor: true);
        expect(rows(out), [3, 3, 3, 3, 3], reason: 'leadFirst $lf');
        expect(seats(statsA()), {
          0: ['Row 02:2:Back:false'],
          1: ['Row 12:2:Back:false'],
          2: ['Row 22:2:Back:false'],
          3: ['Row 31:2:Back:false', 'Row 32:2:Back:false'],
          4: ['Row 41:2:Back:false', 'Row 42:2:Back:false'],
        });
        expect(statsA().weekly['Back'], 30);
        // Each seat's exact excess: Back was at or past its top before every seat, so each adds its full 2 sets.
        expect({for (final v in statsA().floorSeats.values) for (final x in v) '${x.overBy}:${x.overSeconds}'},
            {'{Back: 2}:0.0'});
        expect({for (final d in out) for (final e in d.exercisesA) e.sets}, {2});
        expect(statsA().belowCount, {0: 'cap_top', 1: 'cap_top', 2: 'cap_top', 3: 'cap_top', 4: 'cap_top'});
        expect(statsA().countForced, isEmpty);
        expectOracle(f, out, statsA(), f.ctx(days));

        final off = f.run(days, leadFirst: lf, dayFloor: false);
        expect(rows(off), [2, 2, 2, 1, 1]);
        expect(statsA().floorSeats, isEmpty);
        expect(statsA().weekly['Back'], 16);
      }
    });

    test('never past a session cap: a lead seated at 3 leaves room for one more Back slot, not two (beginner, cap 6)', () {
      // Day 0: Row (Back, the lead), PullA and PullB (Back + Biceps); days 1-6: one Curl each, Biceps 12 = the top.
      // Lead world (kept: same rows as main): Row at 3; PullA and PullB refused by the Biceps top. The floor seats PullA
      // (Back 3 + 2 = 5 <= 6), then PullB would make Back 7 > 6: refused, the day ends at 2 rows. In the main world (the
      // rule off) Row sits at 2, so both seat (Back 6): the cap is the only thing that stopped PullB. (Row ends at 4:
      // pass C grows the lead after the floor, Back 4 + 2 = 6 = the cap.)
      final f = Fx()
        ..row('Row', ['Lats'])
        ..row('PullA', ['Lats', 'Biceps'])
        ..row('PullB', ['Lats', 'Biceps'])
        ..row('Curl', ['Biceps'], type: 'isolation', reps: '10-15');
      final days = [
        f.day('hypertrophy', [f.ex('Row'), f.ex('PullA'), f.ex('PullB')]),
        for (var i = 0; i < 6; i++) f.day('hypertrophy', [f.ex('Curl')]),
      ];
      final out = f.run(days, level: 'beginner', leadFirst: true, dayFloor: true);
      expect(statsA().leadWorld, 'lead');
      expect(setsOf(out[0]), [('Row', 4), ('PullA', 2)]);
      expect(seats(statsA()), {
        0: ['PullA:2:Biceps:false'],
      });
      expectOracle(f, out, statsA(), f.ctx(days, level: 'beginner'));

      final main = f.run(days, level: 'beginner', leadFirst: false, dayFloor: true);
      expect(setsOf(main[0]), [('Row', 2), ('PullA', 2), ('PullB', 2)]);
      expect(seats(statsA()), {
        0: ['PullA:2:Biceps:false', 'PullB:2:Biceps:false'],
      });
    });

    test('never a slot the rank-0 reservation blocked', () {
      // general_fitness beginner (Chest top 10). Day 0: Bench (Chest), Row (Back), Fly (Chest); days 1-5: Bench. Rank 0
      // on day 0: Bench fits but 10 - 2 < 2 x 5 later Chest leads, so the reservation blocks it. Days 1-5 seat Bench
      // (Chest 10); Row seats; Fly is refused by the top. The floor may seat Fly (past the top) but never Bench: the day
      // ends [Row, Fly]. Seating Bench as well would be the cheaper-tie order's second pick.
      final f = Fx()
        ..row('Bench', ['Chest'])
        ..row('Row', ['Lats'])
        ..row('Fly', ['Chest'], type: 'isolation', reps: '10-15');
      final days = [
        f.day('hypertrophy', [f.ex('Bench'), f.ex('Row'), f.ex('Fly')]),
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('Bench')]),
      ];
      final out = f.run(days, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: true);
      expect([for (final e in out[0].exercisesA) e.exerciseName], ['Row', 'Fly']);
      expect(seats(statsA()), {
        0: ['Fly:2:Chest:false'],
      });
      expect(statsA().weekly['Chest'], 12);
      expectOracle(f, out, statsA(), f.ctx(days, goal: 'general_fitness', level: 'beginner'));
    });

    test('not bound by the clock (d33); the label is the one pass A2 left (clock), taken before the floor', () {
      // 30 minutes, general_fitness beginner; days 1-5 Row (Back 10 = the top). Day 0: a not-budgeted Sink (6 sets),
      // ChestA, ChestB, BackX; reach 4 = the count floor. ChestA fits; ChestB does not fit the clock, and pass A2 refuses
      // it too (it would end the day more than 300 s over): the label is `clock`. BackX is refused by the top. The
      // floor (rows 2 < 3) prefers ChestB (no group over its top) to BackX and seats it past the clock (`overClock`).
      // The day still has 3 < 4 rows, so it keeps the label A2 left: `clock`. Read after the floor it would be
      // `cap_top` (the only slot left, BackX, is blocked by the top).
      final f = Fx()
        ..row('ChestA', ['Chest'])
        ..row('ChestB', ['Chest'])
        ..row('BackX', ['Lats'])
        ..row('Row', ['Lats']);
      final days = [
        f.day('hypertrophy',
            [f.ex('Sink', sets: 6, customOrigin: 'repeat_pin'), f.ex('ChestA'), f.ex('ChestB'), f.ex('BackX')]),
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('Row')]),
      ];
      final ctx = f.ctx(days, minutes: 30, goal: 'general_fitness', level: 'beginner');
      final out = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: true);
      expect([for (final e in out[0].exercisesA) e.exerciseName], ['Sink', 'ChestA', 'ChestB']);
      expect(seats(statsA()), {
        0: ['ChestB:2::true'],
      });
      expect(statsA().belowCount, {0: 'clock'});
      expect(statsA().countForced, isEmpty);
      expect(statsA().forcedDays, isEmpty);
      expectOracle(f, out, statsA(), ctx);

      // overClock is exact: the seat's 336 s did not fit what was left, so the day ends over its budget by exactly
      // (sink + ChestA + ChestB) - 1440, and that overrun is all the oracle excuses.
      final ledger = BudgetLedger(ctx, days.length);
      for (final e in out[0].exercisesA) {
        ledger.add(0, const {}, 0, priced(e, ctx));
      }
      expect(ledger.secondsLeft(0), lessThan(0));
      expect(ledger.secondsLeft(0) + 336, greaterThan(0), reason: 'ChestA left less than 336 s, more than 0');
      // `overSeconds` is exactly the day's overrun (the part of the seat that did not fit), not the seat's 336 s.
      expect(statsA().floorSeats[0]!.single.overSeconds, closeTo(-ledger.secondsLeft(0), 1e-6));
      expect(statsA().floorSeats[0]!.single.overBy, isEmpty);

      final off = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: false);
      expect([for (final e in off[0].exercisesA) e.exerciseName], ['Sink', 'ChestA']);
      expect(statsA().belowCount, {0: 'clock'});
    });

    test('the reach (d32): a day handed 2 slots is floored to 2, not skipped', () {
      // Day 4 has two slots only. Pass A: [2, 2, 2, 1, 1]; the floor: days 0-3 to 3, day 4 to its reach, 2.
      final f = fiveByFive();
      final days = fiveByFiveDays(f, perDay: [5, 5, 5, 5, 2]);
      final out = f.run(days, leadFirst: false, dayFloor: true);
      expect(rows(out), [3, 3, 3, 3, 2]);
      expect(seats(statsA())[4], ['Row 41:2:Back:false']);
      expect(statsA().selectorThin, [4]);
      expect(statsA().weekly['Back'], 28);
    });

    test('a lighter (deload) phase is floored too (d31): its top is the band bottom, 12', () {
      // Pass A: rank 0 on five days (10), rank 1 on day 0 (12); [2, 1, 1, 1, 1]. The floor: 2 rounds, 9 seats; Back 30.
      final f = fiveByFive();
      final days = fiveByFiveDays(f);
      final out = f.run(days, lighter: true, leadFirst: false, dayFloor: true);
      expect(rows(out), [3, 3, 3, 3, 3]);
      expect(statsA().weekly['Back'], 30);
      expect([for (final v in statsA().floorSeats.values) v.length], [1, 2, 2, 2, 2]);
      expectOracle(f, out, statsA(), f.ctx(days, lighter: true));
      final off = f.run(days, lighter: true, leadFirst: false, dayFloor: false);
      expect(rows(off), [2, 1, 1, 1, 1]);
    });

    test('below 25 minutes (count floor 3) a floored day is in neither verdict list', () {
      // 20 minutes: 840 s. Day 0: ChestA, ChestB (672 s), BackX refused by the top (Back 10 from days 1-5). Floored past
      // the top and past the clock (336 > 168 s left); 3 rows = the count floor, so no `belowCount`, and reach 3 is not
      // `selectorThin`. Floor off: 2 rows, `cap_top`.
      final f = Fx()
        ..row('ChestA', ['Chest'])
        ..row('ChestB', ['Chest'])
        ..row('BackX', ['Lats'])
        ..row('Row', ['Lats']);
      final days = [
        f.day('hypertrophy', [f.ex('ChestA'), f.ex('ChestB'), f.ex('BackX')]),
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('Row')]),
      ];
      final out = f.run(days, minutes: 20, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: true);
      expect(rows(out)[0], 3);
      expect(seats(statsA()), {
        0: ['BackX:2:Back:true'],
      });
      expect(statsA().belowCount.containsKey(0), isFalse);
      expect(statsA().selectorThin.contains(0), isFalse);
      expectOracle(f, out, statsA(), f.ctx(days, minutes: 20, goal: 'general_fitness', level: 'beginner'));
      f.run(days, minutes: 20, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: false);
      expect(statsA().belowCount, {0: 'cap_top'});
    });
  });

  group('F2. the order', () {
    ({int over, int excess, double seconds}) k(int o, int x, double s) => (over: o, excess: x, seconds: s);

    test('the fewest groups over their top decides first, whatever the excess and the cost', () {
      expect(SessionSetAllocator.floorPrefers(k(1, 8, 400), k(2, 2, 200)), isTrue);
      expect(SessionSetAllocator.floorPrefers(k(2, 2, 200), k(1, 8, 400)), isFalse);
      expect(SessionSetAllocator.floorPrefers(k(0, 0, 900), k(1, 1, 100)), isTrue);
    });

    test('then the least excess, whatever the cost', () {
      expect(SessionSetAllocator.floorPrefers(k(1, 2, 400), k(1, 4, 200)), isTrue);
      expect(SessionSetAllocator.floorPrefers(k(1, 4, 200), k(1, 2, 400)), isFalse);
    });

    test('then the cheapest; a full tie keeps the earlier (lower-rank) candidate', () {
      expect(SessionSetAllocator.floorPrefers(k(1, 2, 256.8), k(1, 2, 336)), isTrue);
      expect(SessionSetAllocator.floorPrefers(k(1, 2, 336), k(1, 2, 256.8)), isFalse);
      expect(SessionSetAllocator.floorPrefers(k(1, 2, 336), k(1, 2, 336)), isFalse);
    });

    test('in a week: an isolation is seated before the compounds ranked above it, then the lowest rank', () {
      // Day 3 also lists a Back isolation (Pullover) after its five rows. Round 1 on day 3: Row 31, Row 32, ...,
      // Pullover all take Back past the top by the same amount; Pullover is cheapest (256.8 < 336). Round 2: Row 31.
      final f = fiveByFive()..row('Pullover', ['Lats'], type: 'isolation', reps: '10-15');
      final days = fiveByFiveDays(f);
      days[3] = f.day('hypertrophy', [for (var r = 0; r < 5; r++) f.ex('Row 3$r'), f.ex('Pullover')]);
      final out = f.run(days, leadFirst: false, dayFloor: true);
      expect([for (final e in out[3].exercisesA) e.exerciseName], ['Row 30', 'Row 31', 'Pullover']);
      expect(seats(statsA())[3], ['Pullover:2:Back:false', 'Row 31:2:Back:false']);
    });

    test('in a week: a slot taking one group past its top before one taking two', () {
      // build_muscle beginner (top 12). Days 1-6: PullUp (Back + Biceps), so both groups reach 12. Day 0: Bench, then X
      // (Back + Biceps), then Y (Back). Round 1 seats Y (one group over), round 2 X (two).
      final f = Fx()
        ..row('Bench', ['Chest'])
        ..row('PullUp', ['Lats', 'Biceps'])
        ..row('X', ['Lats', 'Biceps'])
        ..row('Y', ['Lats']);
      final days = [
        f.day('hypertrophy', [f.ex('Bench'), f.ex('X'), f.ex('Y')]),
        for (var i = 0; i < 6; i++) f.day('hypertrophy', [f.ex('PullUp')]),
      ];
      f.run(days, level: 'beginner', leadFirst: false, dayFloor: true);
      expect(seats(statsA())[0], ['Y:2:Back:false', 'X:2:Back+Biceps:false']);
    });

    // B-pass seat 3, finding 3-2: a group the seat takes exactly TO its top (excess 0), or leaves under it (negative
    // excess), is not over: it adds nothing to the over count, the excess sum, `overTop` or `overBy`.
    test('a group landing exactly at its top is not over: the full tie keeps the earlier slot, overTop names Back only',
        () {
      // build_muscle beginner (top 12). Days 1-5: PullUp (Back + Biceps), day 6: Row (Back): Back 12, Biceps 10. Day 0:
      // Bench, then X (Back + Biceps: Biceps lands at 12, not over), then Y (Back). Both take one group 2 past its top
      // at 336 s, so X (earlier) is seated first, recording Back alone; then Y (Back 16, overBy capped at 2).
      final f = Fx()
        ..row('Bench', ['Chest'])
        ..row('PullUp', ['Lats', 'Biceps'])
        ..row('Row', ['Lats'])
        ..row('X', ['Lats', 'Biceps'])
        ..row('Y', ['Lats']);
      final days = [
        f.day('hypertrophy', [f.ex('Bench'), f.ex('X'), f.ex('Y')]),
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('PullUp')]),
        f.day('hypertrophy', [f.ex('Row')]),
      ];
      f.run(days, level: 'beginner', leadFirst: false, dayFloor: true);
      expect(seats(statsA())[0], ['X:2:Back:false', 'Y:2:Back:false']);
      expect([for (final s in statsA().floorSeats[0]!) s.overBy], [
        {'Back': 2},
        {'Back': 2},
      ]);
    });

    test('a group left under its top does not lower the excess: the full tie keeps the earlier slot', () {
      // Days 1-6: Row (Back): Back 12, Biceps 0. Day 0: Bench, then Y (Back), then X (Back + Biceps, Biceps 2 of 12).
      // Both take Back 2 past its top; X's Biceps headroom (-10) does not make its excess smaller, so Y stays first.
      final f = Fx()
        ..row('Bench', ['Chest'])
        ..row('Row', ['Lats'])
        ..row('X', ['Lats', 'Biceps'])
        ..row('Y', ['Lats']);
      final days = [
        f.day('hypertrophy', [f.ex('Bench'), f.ex('Y'), f.ex('X')]),
        for (var i = 0; i < 6; i++) f.day('hypertrophy', [f.ex('Row')]),
      ];
      f.run(days, level: 'beginner', leadFirst: false, dayFloor: true);
      expect(seats(statsA())[0], ['Y:2:Back:false', 'X:2:Back:false']);
    });
  });

  group('F3. the worlds', () {
    test('the worlds are chosen with the floor off; the chosen world is re-run with it', () {
      // Three days of L, Y, Z (Back), intermediate. Floor off: the lead world seats each L at 3 and leaves day 0 at 2
      // rows where main has 3, so it is worse; the capped world (main's seating) is kept. The floor then re-runs the
      // capped world: day 2 gains Z past the top. Chosen with the floor on, the lead world (3 rows a day with each L at
      // 3) would have been kept instead.
      final f = Fx();
      for (final n in ['L', 'Y', 'Z']) {
        f.row(n, ['Lats']);
      }
      final days = [for (var i = 0; i < 3; i++) f.day('hypertrophy', [f.ex('L'), f.ex('Y'), f.ex('Z')])];
      final out = f.run(days, leadFirst: true, dayFloor: true);
      expect(statsA().leadWorld, 'capped');
      expect([for (final d in out) setsOf(d)], [
        for (var i = 0; i < 3; i++) [('L', 2), ('Y', 2), ('Z', 2)],
      ]);
      expect(seats(statsA()), {
        2: ['Z:2:Back:false'],
      });
      f.run(days, leadFirst: true, dayFloor: false);
      expect(statsA().leadWorld, 'capped');
    });

    test('B copies the FLOORED A: a copied day carries its floor sets and its floorSeats into B', () {
      // Five days; B differs on day 4 only (Alt rows). B's days 0-3 are A's floored days; B's day 4, with A's 24 Back
      // sets on days 0-3, has no room: the empty-day guard forces Alt 40 and the floor adds Alt 41 and Alt 42.
      for (final lf in [true, false]) {
        final f = fiveByFive();
        for (var r = 0; r < 5; r++) {
          f.row('Alt 4$r', ['Lats']);
        }
        final days = fiveByFiveDays(f);
        days[4] = f.day('hypertrophy', [for (var r = 0; r < 5; r++) f.ex('Row 4$r')],
            b: [for (var r = 0; r < 5; r++) f.ex('Alt 4$r')]);
        final out = f.run(days, is6Day: false, leadFirst: lf, dayFloor: true);
        expect(rows(out, b: true), [3, 3, 3, 3, 3], reason: 'leadFirst $lf');
        for (var d = 0; d < 4; d++) {
          expect(setsOf(out[d], b: true), setsOf(out[d]));
          expect(seats(statsB())[d], seats(statsA())[d], reason: 'day $d floorSeats copied');
        }
        expect(seats(statsB())[4], ['Alt 41:2:Back:false', 'Alt 42:2:Back:false']);
        expect(statsB().forcedDays, [4]);
        expect(statsB().weekly['Back'], 30);
        expectOracle(f, out, statsB(), f.ctx(days), b: true);
      }
    });
  });

  group('F4. floorSeats', () {
    test('a floor seat is never in countForced, and overClock is false when the seat fits', () {
      final f = fiveByFive();
      final days = fiveByFiveDays(f);
      f.run(days, minutes: 30, leadFirst: false, dayFloor: true);
      // At 30 minutes (1440 s) three 2-set compounds take 1008 s: every seat fits.
      expect({for (final v in statsA().floorSeats.values) for (final s in v) s.overClock}, {false});
      expect(BudgetInvariantOracle.floorSeatsDisjointFromCountForced(statsA()), isTrue);
    });

    // B-pass seat 3, finding 3-1: the oracle is exact per group and per day, over hand-built stats.
    test('the oracle sums each group\'s own overBy and each day\'s own overSeconds, nothing per seat or per name', () {
      FloorSeat fs(String name, Map<String, int> overBy, double overSeconds) => (
            name: name,
            sets: 2,
            overTop: overBy.keys.toList(),
            overBy: overBy,
            overClock: overSeconds > 0,
            overSeconds: overSeconds,
          );
      final s = AllocationStats();
      s.floorSeats[0] = [
        fs('A', {'Chest': 1, 'Back': 2}, 0),
        fs('A', {'Back': 2}, 120.5),
      ];
      s.floorSeats[2] = [fs('B', {'Biceps': 2}, 40)];
      expect(BudgetInvariantOracle.floorOverTopSets(s, 'Chest'), 1);
      expect(BudgetInvariantOracle.floorOverTopSets(s, 'Back'), 4);
      expect(BudgetInvariantOracle.floorOverTopSets(s, 'Biceps'), 2);
      expect(BudgetInvariantOracle.floorOverTopSets(s, 'Quads'), 0);
      expect(BudgetInvariantOracle.weekCeiling(12, s, 'Chest'), 13);
      expect(BudgetInvariantOracle.floorOverClockSeconds(s, 0), 120.5);
      expect(BudgetInvariantOracle.floorOverClockSeconds(s, 1), 0);
      expect(BudgetInvariantOracle.floorOverClockSeconds(s, 2), 40);
      expect(BudgetInvariantOracle.floorOverTopSets(null, 'Back'), 0);
    });
  });

  group('interactions', () {
    test('a floored lead: leadSeats names it at 2 bound by its group, and R2 holds the rest to it + 1', () {
      // Beginner. Day 0: Curl (rank 0), Row (rank 1, the opener: a compound). Days 1-6: RowK, Back 12 = the top before
      // rank 1. Row is refused in pass A and floored at 2. With the lead-first rule, pass C holds Curl to 2 + 1 = 3;
      // without it, Curl grows to 5.
      final f = Fx()
        ..row('Curl', ['Biceps'], type: 'isolation', reps: '10-15')
        ..row('Row', ['Lats'])
        ..row('RowK', ['Lats']);
      final days = [
        f.day('hypertrophy', [f.ex('Curl'), f.ex('Row')]),
        for (var i = 0; i < 6; i++) f.day('hypertrophy', [f.ex('RowK')]),
      ];
      final out = f.run(days, level: 'beginner', leadFirst: true, dayFloor: true);
      expect(statsA().leadWorld, 'lead');
      expect(setsOf(out[0]), [('Curl', 3), ('Row', 2)]);
      final lead = statsA().leadSeats.firstWhere((e) => e.day == 0);
      expect((lead.name, lead.rank, lead.sets, lead.boundBy), ('Row', 1, 2, 'Back'));
      expect(seats(statsA()), {
        0: ['Row:2:Back:false'],
      });
      final off = f.run(days, level: 'beginner', leadFirst: false, dayFloor: true);
      expect(setsOf(off[0]), [('Curl', 5), ('Row', 2)]);
    });

    test('week 2 gains nothing on a group over its top; week 4 leaves a floor seat at 2', () {
      final f = fiveByFive();
      final days = fiveByFiveDays(f);
      final ctx = f.ctx(days);
      final out = SessionSetAllocator.allocate(days: days, ctx: ctx, rowsByName: f.rows, is6Day: true, dayFloor: true);
      final weeks = PeriodizationEngine.apply(populated: out, phase: 1, is6Day: true, budget: ctx);
      for (final w in [0, 1, 2, 3]) {
        expect({for (final d in weeks[w].workoutDays) for (final e in d.exercises) e.sets}, {2},
            reason: 'week ${w + 1}');
        // ... and every week keeps the floored rows (3 a day): no later week drops a floor seat.
        expect([for (final d in weeks[w].workoutDays) d.exercises.length], [3, 3, 3, 3, 3], reason: 'week ${w + 1}');
      }
    });

    test('an evicted hold: the floor counts the day without it', () {
      // 30 minutes, general_fitness beginner; days 1-5 Row (Back 10). Day 0: chest, back, back2, plank and hollow (6
      // sets each, 684 s). chest gives the day its first Chest credit and evicts hollow (reach 5 > the floor 4); back and
      // back2 are refused by the top. Rows: chest + plank = 2, so the floor seats back (336 s of the 420 left). Floor
      // off, chest grows to 4 in that time instead.
      final f = Fx()
        ..row('chest', ['Chest'])
        ..row('back', ['Lats'])
        ..row('back2', ['Lats'])
        ..row('Row', ['Lats'])
        ..row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed')
        ..row('hollow', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      final days = [
        f.day('hypertrophy', [
          f.ex('chest'),
          f.ex('back'),
          f.ex('back2'),
          f.ex('plank', sets: 6, logging: 'timed', rest: 60),
          f.ex('hollow', sets: 6, logging: 'timed', rest: 60),
        ]),
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('Row')]),
      ];
      final out = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: true);
      expect(setsOf(out[0]), [('chest', 2), ('back', 2), ('plank', 6)]);
      expect(seats(statsA()), {
        0: ['back:2:Back:false'],
      });
      final off = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner', leadFirst: false, dayFloor: false);
      expect(setsOf(off[0]), [('chest', 4), ('plank', 6)]);
    });

    test('the count target: the PREMISE that lets canFloor skip a target guard', () {
      // Not a behaviour test (B-pass seat 2, finding 2-1): a slot is target-removed only once the day holds the level's
      // count max in rows (`seated[d] >= target[d]`, target = count max - the not-budgeted rows), and the floor acts only
      // below 3 rows, so a target-removed slot can never be floored. That holds while every count max is at least the
      // floor's 3; this pins the premise, so lowering a count max under 3 reddens here before canFloor needs a guard.
      for (final level in ['beginner', 'intermediate', 'advanced', 'unknown']) {
        expect(SessionBudget.countMax(level), greaterThanOrEqualTo(3), reason: level);
      }
    });
  });

  group('F5. the kill switch disable_day_floor and the dayFloor argument', () {
    late Directory tempDir;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('day_floor_ks');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await Hive.openBox(HiveService.configBoxName);
      HiveService.instance.markInitializedForTests();
    });
    tearDownAll(() async {
      await HiveService.instance.configBox.delete('disable_day_floor');
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    List<List<(String, int)>> run(Fx f, List<PopulatedDay> days, {required bool lf, bool? fl}) {
      final out = f.run(days, is6Day: false, leadFirst: lf, dayFloor: fl);
      return [for (final d in out) ...[setsOf(d), setsOf(d, b: true)]];
    }

    test('absent: the floor runs in both 2A paths; set: it does not; the argument overrides the box', () async {
      for (final lf in [true, false]) {
        final f = fiveByFive();
        final days = fiveByFiveDays(f);
        final on = run(f, days, lf: lf, fl: true);
        final off = run(f, days, lf: lf, fl: false);
        expect(on, isNot(off));

        await HiveService.instance.configBox.delete('disable_day_floor');
        expect(run(f, days, lf: lf), on, reason: 'leadFirst $lf, flag absent');
        await HiveService.instance.configBox.put('disable_day_floor', true);
        try {
          expect(run(f, days, lf: lf), off, reason: 'leadFirst $lf, flag set');
          expect(statsA().floorSeats, isEmpty);
          expect(run(f, days, lf: lf, fl: true), on, reason: 'leadFirst $lf, argument overrides');
        } finally {
          await HiveService.instance.configBox.delete('disable_day_floor');
        }
      }
    });
  });
}
