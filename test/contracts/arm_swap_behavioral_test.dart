// Unit 2E (OI-496, founder d51; plan docs/plans/2026-11-15-generator-step2e-arm-swap.md S1-S7): under 60 minutes, a
// variant whose week holds 0 Biceps or 0 Triceps while the other variant trains them swaps the day's last
// over-served row for the arm row, at 2 sets. The row count is unchanged, and the day is no longer than before. The
// seat is a `minimumSeats` entry. The swap's victim may be:
// - a budgeted admitted row or a kept library hold;
// - never rank 0, the day's opener, a minimum seat or a focus row;
// - only a row each of whose groups another row of the day also credits.
// S6: an arm group that B gains late in the 2C-b fixpoint becomes a target of A too.
//
// Pure Dart over crafted fixtures (`session_budget_fixtures.dart`), found by a probe sweep. Two 30-minute days:
// - day 0's A list is a row (Back, rank 0), a 3-set custom (it spends the day's time), two library holds and a curl;
// - B trains Biceps (curlB).
// R (the floor re-run) admits the row and both holds and the clock refuses the curl. The allowance re-run keeps R's 4
// rows (d44), so the minimum pass refuses the curl, and only the swap seats it. The real-engine reach (the 23 audit
// plans) is pinned by test/plan_generator/arm_swap_gate_test.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

Fx lib({List<String> hold0 = const ['Back'], List<String> hold1 = const ['Back'], List<String> arm = const ['Biceps']}) {
  final f = Fx();
  f.row('row', ['Back']);
  f.row('bench', ['Chest']);
  f.row('hold0', hold0, type: 'isolation', logging: 'timed');
  f.row('hold1', hold1, type: 'isolation', logging: 'timed');
  f.row('curlA', arm, type: 'isolation');
  f.row('curlB', arm, type: 'isolation');
  return f;
}

List<PopulatedDay> week(Fx f, {int custom = 3}) {
  final dA = [
    f.ex('row'),
    if (custom > 0) f.ex('mine', sets: custom, rest: 100, customOrigin: 'user'),
    f.ex('hold0', logging: 'timed', sets: 3, rest: 30),
    f.ex('hold1', logging: 'timed', sets: 3, rest: 30),
    f.ex('curlA'),
  ];
  final dB = [f.ex('bench'), f.ex('curlB'), f.ex('row')];
  return [
    f.day('hypertrophy', dA, b: dB),
    f.day('hypertrophy', [f.ex('bench'), f.ex('row')], b: [f.ex('bench'), f.ex('row')]),
  ];
}

List<String> names(List<PlannedExercise> xs) => [for (final e in xs) e.exerciseName];

/// The whole plan's shape: names and sets of both variants, every day.
List<Object> shape(List<PopulatedDay> out) => [
      for (final d in out) ...[setsOf(d), setsOf(d, b: true)],
    ];

List<PopulatedDay> runArm(Fx f, List<PopulatedDay> days,
    {required bool on, int minutes = 30, String level = 'beginner', Set<String> focus = const {}, bool? balancedWeek}) {
  SessionSetAllocator.debugArmSwap = on;
  try {
    return f.run(days,
        minutes: minutes, level: level, is6Day: false, focus: focus, balancedWeek: balancedWeek);
  } finally {
    SessionSetAllocator.debugArmSwap = true;
  }
}

void main() {
  tearDown(() => SessionSetAllocator.debugArmSwap = true);

  group('the swap', () {
    test('a hold victim: the last over-served hold gives way to the curl (seated at 2, grown to 3); the row count is unchanged', () {
      for (final level in ['beginner', 'intermediate']) {
        final f = lib();
        final off = runArm(f, week(f), on: false, level: level);
        final on = runArm(f, week(f), on: true, level: level);
        expect(names(off[0].exercisesA), ['row', 'mine', 'hold0', 'hold1'], reason: '$level: R refuses the curl');
        expect(names(on[0].exercisesA), ['row', 'mine', 'hold0', 'curlA'], reason: level);
        // Seated at 2 sets by the swap, then grown to the base 3 by pass B like every seat.
        expect(on[0].exercisesA.last.sets, 3);
        expect(on[0].exercisesA.length, off[0].exercisesA.length);
        expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats[0], [(name: 'curlA', group: 'Biceps')]);
        expect(SessionSetAllocator.debugLastStats!['A']!.credited['Biceps'], 3);
        expect(on[0].allowance, isTrue, reason: 'the allowance world ran, no fallback to R');
        // Week 2 (B) and day 1 are untouched.
        expect([setsOf(on[0], b: true), setsOf(on[1]), setsOf(on[1], b: true)],
            [setsOf(off[0], b: true), setsOf(off[1]), setsOf(off[1], b: true)]);
      }
    });

    test('a hold whose group no other row of the day credits is not a victim: the walk passes it', () {
      // hold1 (last) is the day's only Core row, so the swap walks on to hold0 (Back, which the row also credits).
      final f = lib(hold1: const ['Core']);
      final on = runArm(f, week(f), on: true);
      expect(names(on[0].exercisesA), ['row', 'mine', 'hold1', 'curlA']);
    });

    test('no over-served row at all: no swap', () {
      // Both holds are the day's only row of their group (Core, Glutes); the row is rank 0 and the opener.
      final f = lib(hold0: const ['Glutes'], hold1: const ['Core']);
      final off = runArm(f, week(f), on: false);
      final on = runArm(f, week(f), on: true);
      expect(shape(on), shape(off));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });

    test('a focus-group row is never a victim (d38)', () {
      final f = lib();
      final off = runArm(f, week(f), on: false, focus: const {'Back'});
      final on = runArm(f, week(f), on: true, focus: const {'Back'});
      expect(names(on[0].exercisesA).where((n) => n.startsWith('hold')), names(off[0].exercisesA).where((n) => n.startsWith('hold')));
    });
  });

  // A budgeted victim (probe-found): day 0's A list opens with an isolation (fly, rank 0), then a second Back row
  // (pullover), then the day's opener (row, a compound, so the walk puts the curl behind it), a custom of [custom] sets
  // and the curl. At 30 minutes R admits fly, pullover and row; the curl has no room.
  Fx libB({List<String> fly = const ['Chest'], List<String> pullover = const ['Back'], List<String> arm = const ['Biceps']}) {
    final f = Fx();
    f.row('row', ['Back']);
    f.row('bench', ['Chest']);
    f.row('fly', fly, type: 'isolation');
    f.row('pullover', pullover, type: 'isolation');
    f.row('curlA', arm, type: 'isolation');
    f.row('curlB', const ['Biceps'], type: 'isolation');
    for (var i = 0; i < 6; i++) {
      f.row('press$i', ['Chest']);
    }
    return f;
  }

  List<PopulatedDay> weekB(Fx f, {int custom = 2, int chestDay1 = 0}) => [
        f.day('hypertrophy', [
          f.ex('fly'),
          f.ex('pullover'),
          f.ex('row'),
          if (custom > 0) f.ex('mine', sets: custom, rest: 100, customOrigin: 'user'),
          f.ex('curlA'),
        ], b: [
          f.ex('bench'),
          f.ex('curlB'),
          f.ex('row')
        ]),
        f.day('hypertrophy', [f.ex('bench'), f.ex('row'), for (var i = 0; i < chestDay1; i++) f.ex('press$i')],
            b: [f.ex('bench'), f.ex('row'), for (var i = 0; i < chestDay1; i++) f.ex('press$i')]),
      ];

  group('budgeted victims', () {
    test('a budgeted row whose group no other row of ITS DAY credits is not a victim, though the week trains it', () {
      // pullover is day 0's only Glutes row; day 1 trains Glutes (bridge), so the week would keep Glutes and only the
      // day-level rule refuses.
      final f = libB(pullover: const ['Glutes']);
      f.row('bridge', const ['Glutes']);
      final days = weekB(f);
      final withBridge = [
        days[0],
        f.day('hypertrophy', [f.ex('bench'), f.ex('row'), f.ex('bridge')], b: [f.ex('bench'), f.ex('row'), f.ex('bridge')]),
      ];
      final on = runArm(f, withBridge, on: true);
      expect(names(on[0].exercisesA), contains('pullover'));
    });

    test('the last over-served budgeted row (pullover, a second Back row) gives way to the curl', () {
      for (final level in ['beginner', 'intermediate']) {
        final f = libB();
        final off = runArm(f, weekB(f), on: false, level: level);
        final on = runArm(f, weekB(f), on: true, level: level);
        expect(names(off[0].exercisesA), ['fly', 'pullover', 'row', 'mine'], reason: level);
        expect(names(on[0].exercisesA), ['fly', 'row', 'mine', 'curlA'], reason: level);
        expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats[0], [(name: 'curlA', group: 'Biceps')]);
      }
    });

    test('never rank 0 (fly) or the opener (row), and never a row whose group no other row credits (pullover)', () {
      // fly and row both credit Back, so each is over-served; pullover is the day's only Glutes row.
      final f = libB(fly: const ['Back'], pullover: const ['Glutes']);
      final off = runArm(f, weekB(f), on: false);
      final on = runArm(f, weekB(f), on: true);
      expect(shape(on), shape(off));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });

    test('a focus-group budgeted row is never a victim (d38)', () {
      final f = libB();
      final on = runArm(f, weekB(f), on: true, focus: const {'Back'});
      expect(names(on[0].exercisesA), contains('pullover'));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });
  });

  group('armFits (the seat check, pure)', () {
    final f = lib();
    // The swap runs only in the allowance world, whose forcing bound is 0.
    BudgetLedger fresh({int minutes = 30}) =>
        BudgetLedger(f.ctx(const [], minutes: minutes, level: 'beginner'), 2, allowance: true);

    test('the session cap of every group of the arm row', () {
      final l = fresh();
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 10, 0), isTrue);
      l.add(0, const {'Biceps'}, l.cap('Biceps') - 1, 0);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 10, 0), isFalse, reason: 'cap - 1 + 2');
    });

    test('the weekly top of every OTHER group (the target itself is at 0, so its own top never binds)', () {
      final l = fresh();
      l.add(1, const {'Chest'}, l.weeklyTop('Chest') - 1, 0);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps', 'Chest'}, 'Biceps', 10, 0), isFalse);
      final m = fresh();
      m.add(1, const {'Biceps'}, m.weeklyTop('Biceps') - 1, 0);
      // Not reachable in the allocator (the target is at 0), but the check is per other group by design.
      expect(SessionSetAllocator.armFits(m, 0, const {'Biceps'}, 'Biceps', 10, 0), isTrue);
    });

    test('time: within the forcing bound, or no longer than the day was before the swap', () {
      final l = fresh();
      final left = l.secondsLeft(0);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', left, left), isTrue, reason: 'exact fill');
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', left + 1, left), isFalse);
      // A day already 100 s over: the arm row may cost what the victim freed, no more.
      l.add(0, const {}, 0, left + 100);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 0, -100), isTrue);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 1, -100), isFalse);
      // A victim that freed 60 s on that day: 60 s of arm row fit, 61 do not.
      l.add(0, const {}, 0, -60);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 60, -100), isTrue);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 61, -100), isFalse);
    });
  });

  group('the swap never passes a bound the plan kept without it', () {
    test('time, the session cap and the weekly top, over a sweep (hold and budgeted fixtures)', () {
      var runs = 0;
      for (final minutes in [30, 45]) {
        for (final level in ['beginner', 'intermediate']) {
          for (var k = 0; k <= 10; k++) {
            for (final chest in [0, 2, 4, 6]) {
              for (final (f, days) in [
                () {
                  final f = lib();
                  return (f, week(f, custom: k));
                }(),
                () {
                  final f = libB(arm: const ['Biceps', 'Chest']);
                  return (f, weekB(f, custom: k, chestDay1: chest));
                }(),
              ]) {
                final off = runArm(f, days, on: false, minutes: minutes, level: level);
                final on = runArm(f, days, on: true, minutes: minutes, level: level);
                final ctx = f.ctx(days, minutes: minutes, level: level);
                final ledger = BudgetLedger(ctx, days.length);
                for (final b in [false, true]) {
                  List<List<PlannedExercise>> rows(List<PopulatedDay> out) =>
                      [for (final d in out) b ? d.exercisesB : d.exercisesA];
                  final lOff = SessionSetAllocator.plainLedgerForTest(rows(off), ctx, f.rows);
                  final lOn = SessionSetAllocator.plainLedgerForTest(rows(on), ctx, f.rows);
                  final why = '$minutes min, $level, custom $k, chest $chest, ${b ? 'B' : 'A'}';
                  for (var d = 0; d < days.length; d++) {
                    final bound = SessionBudget.allowanceSeconds.toDouble();
                    final overOn = -lOn.secondsLeft(d), overOff = -lOff.secondsLeft(d);
                    expect(overOn <= (overOff > bound ? overOff : bound) + 1e-6, isTrue, reason: '$why day $d time');
                    for (final g in const ['Chest', 'Back', 'Biceps', 'Glutes']) {
                      final on1 = lOn.session(d, g), off1 = lOff.session(d, g);
                      expect(on1 <= ledger.cap(g) || on1 <= off1, isTrue, reason: '$why day $d $g cap');
                    }
                  }
                  for (final g in const ['Chest', 'Back', 'Biceps', 'Glutes']) {
                    final on1 = lOn.week(g), off1 = lOff.week(g);
                    expect(on1 <= ledger.weeklyTop(g) || on1 <= off1, isTrue, reason: '$why $g top');
                  }
                }
                runs++;
              }
            }
          }
        }
      }
      expect(runs, 352);
    });
  });

  group('where it runs', () {
    test('60 and 90 minutes: never (the swap runs only in the allowance world)', () {
      for (final minutes in [60, 90]) {
        for (var k = 0; k <= 12; k++) {
          final f = lib();
          expect(shape(runArm(f, week(f, custom: k), on: true, minutes: minutes)),
              shape(runArm(f, week(f, custom: k), on: false, minutes: minutes)),
              reason: '$minutes minutes, custom $k');
        }
      }
    });

    test('only Biceps and Triceps: a Calves or Core arm row is never swapped in', () {
      for (final g in ['Calves', 'Core', 'Chest']) {
        final f = lib(arm: [g]);
        expect(shape(runArm(f, week(f), on: true, minutes: 45)), shape(runArm(f, week(f), on: false, minutes: 45)),
            reason: g);
        expect(shape(runArm(f, week(f), on: true)), shape(runArm(f, week(f), on: false)), reason: g);
      }
      final t = lib(arm: const ['Triceps']);
      expect(names(runArm(t, week(t), on: true)[0].exercisesA), contains('curlA'), reason: 'Triceps is swapped in');
    });

    test('the kill switch (balanced week off): the swap does not run, the plan is R', () {
      final f = lib();
      final on = runArm(f, week(f), on: true, balancedWeek: false);
      final off = runArm(f, week(f), on: false, balancedWeek: false);
      expect(shape(on), shape(off));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });

    test('a custom-filler sweep at 30 / 45 minutes: rows per day never change, and an added row is a minimum seat', () {
      var swapped = 0;
      for (final minutes in [30, 45]) {
        for (var k = 0; k <= 12; k++) {
          final f = lib();
          final off = runArm(f, week(f, custom: k), on: false, minutes: minutes);
          final on = runArm(f, week(f, custom: k), on: true, minutes: minutes);
          final seats = SessionSetAllocator.debugLastStats!['A']!.minimumSeats;
          for (var d = 0; d < on.length; d++) {
            expect(on[d].exercisesA.length, off[d].exercisesA.length, reason: '$minutes min, custom $k, day $d');
            expect(on[d].exercisesB.length, off[d].exercisesB.length, reason: '$minutes min, custom $k, day $d B');
            // When the run without the swap fell back to R (the terminal guard) and the run with it did not, the two
            // are different worlds (measured: 45 minutes, custom 8): only the row count is compared.
            if (on[0].allowance != off[0].allowance) continue;
            final added = names(on[d].exercisesA).toSet().difference(names(off[d].exercisesA).toSet());
            for (final n in added) {
              expect(seats[d]?.map((m) => m.name), contains(n), reason: '$minutes min, custom $k, day $d: $n');
              swapped++;
            }
          }
        }
      }
      expect(swapped, 2, reason: 'measured: 30 min custom 3, 45 min custom 9');
    });
  });
}
