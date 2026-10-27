// B2 Task 3 (docs/plans/2026-10-22-session-set-budget.md): the session set
// allocator. Pure Dart over crafted fixtures, plus a seeded invariant sweep over
// the shipped library.
//
// Every literal in the crafted tests was computed first with an independent
// reference model of the plan's algorithm (written from the plan text, not from
// the Dart code), then checked by hand where it was small enough to.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

AllocationStats statsA() => SessionSetAllocator.debugLastStats!['A']!;
AllocationStats statsB() => SessionSetAllocator.debugLastStats!['B']!;

void main() {
  group('priority-rank admission', () {
    test('priority: a day of 4 chest exercises is [4, 4, removed, removed], never [2, 2, 2, 2]', () {
      final f = Fx();
      for (final n in ['c1', 'c2', 'c3', 'c4']) {
        f.row(n, ['Chest']);
      }
      final days = [f.day('strength', [for (final n in ['c1', 'c2', 'c3', 'c4']) f.ex(n)])];
      final out = f.run(days, minutes: 90);
      expect(setsOf(out[0]), [('c1', 4), ('c2', 4)]);
      expect(statsA().weekly['Chest'], 8);
    });

    test('round-robin by rank: 4 days of Back lead lifts all keep 4 sets', () {
      final f = Fx();
      f.row('row', ['Lats']);
      f.row('pulldown', ['Lats']);
      final days = [
        for (var i = 0; i < 4; i++) f.day('strength', [f.ex('row'), f.ex('pulldown')]),
      ];
      final out = f.run(days, minutes: 90);
      for (final d in out) {
        expect(setsOf(d), [('row', 4)]);
      }
      expect(statsA().capForcedFirst, 0);
      expect(statsA().timeForcedFirst, 0);
      expect(statsA().weekly['Back'], 16);
    });

    test('rank-0 reservation: every lead lift keeps >= 2 sets when the group top binds', () {
      // general_fitness beginner: Chest top 10, cap 6. Days desire 4 / 3 / 2 / 2.
      final f = Fx();
      f.row('bench', ['Chest']);
      f.row('press', ['Triceps'], type: 'isolation', reps: '10-15');
      final days = [
        for (final i in ['strength', 'hypertrophy', 'endurance', 'endurance'])
          f.day(i, [f.ex('bench'), f.ex('press')]),
      ];
      final out = f.run(days, minutes: 90, goal: 'general_fitness', level: 'beginner');
      expect([for (final d in out) d.exercisesA.first.sets], [4, 2, 2, 2]);
      expect(statsA().capForcedFirst, 0);
      expect(statsA().weekly['Chest'], 10);
      // Day 2 wanted 3 and got 2 because the reservation protected days 3 and 4;
      // the stats name the group that bound it.
      final lead = statsA().firstLifts.where((l) => l.rank == 0).toList();
      expect(lead.length, 4);
      expect(lead[1].sets, 2);
      expect(lead[1].desired, 3);
      expect(lead[1].boundBy, 'Chest');
    });

    test('rank-0 reservation counts only the later days whose lead lift credits the SAME group', () {
      // Six strength days, six different lead groups. A reservation that counted every
      // later day would hold 2 x 5 sets of Chest back and refuse the first lead lift.
      final f = Fx();
      final names = {
        'bench': 'Chest', 'row': 'Lats', 'sq': 'Quads', 'rdl': 'Hamstrings', 'ht': 'Glutes',
        'ohp': 'Shoulders',
      };
      names.forEach((n, m) => f.row(n, [m]));
      final days = [for (final n in names.keys) f.day('strength', [f.ex(n)])];
      final out = f.run(days, minutes: 90, goal: 'general_fitness', level: 'beginner');
      expect([for (final d in out) d.exercisesA.first.sets], [5, 5, 5, 5, 5, 5]);
      expect(statsA().forcedDays, isEmpty);
      expect(statsA().timeForcedFirst, 0);
      expect(statsA().capForcedFirst, 0);
    });

    test('boundBy is reported only while the lead lift is still below its desired sets', () {
      // Day 0's lead lift gets 2 of its desired 3 because four later days' lead lifts
      // (Chest, top 10) are protected. Those four are then refused for time (a 270 s
      // gap fits a 2-set Biceps curl, 257 s, but not a 2-set Chest lift, 282 s), so
      // the reservation was never needed and the floor pass grows day 0's lift to 5.
      final f = Fx();
      f.row('cl', ['Chest']);
      f.row('bi', ['Biceps'], type: 'isolation', reps: '10-15');
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      final gap = (30 - SessionBudget.warmCoolMinutes(30)) * 60 -
          SessionBudget.exerciseSeconds(archetype: 'B', sets: 6, restSeconds: 141);
      expect(gap, closeTo(270.0, 1e-6));
      expect(SessionBudget.exerciseSeconds(archetype: 'M', sets: 2, restSeconds: 75), greaterThan(gap));
      expect(SessionBudget.exerciseSeconds(archetype: 'I', sets: 2, restSeconds: 75), lessThan(gap));
      final days = [
        f.day('hypertrophy', [f.ex('cl')]),
        for (var i = 0; i < 4; i++)
          f.day('hypertrophy', [
            f.ex('plank', sets: 6, logging: 'timed', rest: 141),
            f.ex('cl'),
            f.ex('bi'),
          ]),
      ];
      final out = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner');
      expect(setsOf(out[0]), [('cl', 5)]);
      for (final d in out.skip(1)) {
        expect(setsOf(d).where((e) => e.$1 != 'plank'), [('bi', 2)]);
      }
      expect(statsA().weekly['Chest'], 5);
      expect(statsA().timeForcedFirst, 0);
      final first = statsA().firstLifts.firstWhere((l) => l.day == 0);
      expect(first.sets, 5);
      expect(first.desired, 3);
      expect(first.boundBy, isNull);
    });

    test('boundBy is null when only TIME held the lead lift below its desired sets (B-pass R1 P2-1)', () {
      // general_fitness beginner (Chest cap 6, top 10), one strength day (150 s rests,
      // desired 4) on 30 minutes = 1440 s. A 6-set timed row at 70 s rest costs 744 s,
      // leaving 696 s: three sets of the Chest lift fit (594 s), four do not (816 s).
      // The ledger already holds the 3 granted sets when the allocator asks what stopped
      // the 4th, so the question is "would ONE more fit?" (3 + 1 <= 6): only time says no.
      final f = Fx();
      f.row('cl', ['Chest']);
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      expect(SessionBudget.exerciseSeconds(archetype: 'B', sets: 6, restSeconds: 70), closeTo(744.0, 1e-6));
      expect(SessionBudget.exerciseSeconds(archetype: 'M', sets: 3, restSeconds: 150), closeTo(594.0, 1e-6));
      expect(SessionBudget.exerciseSeconds(archetype: 'M', sets: 4, restSeconds: 150), closeTo(816.0, 1e-6));
      final days = [
        f.day('strength', [f.ex('plank', sets: 6, logging: 'timed', rest: 70), f.ex('cl')]),
      ];
      final out = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner');
      expect(setsOf(out[0]).where((e) => e.$1 == 'cl'), [('cl', 3)]);
      final first = statsA().firstLifts.single;
      expect(first.sets, 3);
      expect(first.desired, 4);
      expect(first.boundBy, isNull);
    });
  });

  group('time', () {
    List<(String, String)> eight() => [
          ('chest', 'Chest'), ('back', 'Lats'), ('delts', 'Lateral Delts'), ('bi', 'Biceps'),
          ('tri', 'Triceps'), ('quad', 'Quads'), ('ham', 'Hamstrings'), ('glute', 'Glutes'),
        ];

    (List<PopulatedDay>, Fx) dayOf(String intensity) {
      final f = Fx();
      for (final (n, m) in eight()) {
        f.row(n, [m]);
      }
      return ([f.day(intensity, [for (final (n, _) in eight()) f.ex(n)])], f);
    }

    double secondsOf(PopulatedDay d, Fx f, String intensity) => [
          for (final e in d.exercisesA)
            SessionBudget.exerciseSeconds(
              archetype: SessionBudget.archetypeOfRow(f.rows[e.exerciseName.toLowerCase()]!),
              sets: e.sets,
              restSeconds: SessionBudget.restFor(intensity),
            ),
        ].fold(0.0, (a, b) => a + b);

    test('no cap binds (one exercise per group): only time does, and the day fits', () {
      final budget = (30 - SessionBudget.warmCoolMinutes(30)) * 60;
      final (hyp, fh) = dayOf('hypertrophy');
      final (str, fs) = dayOf('strength');
      final outH = fh.run(hyp, minutes: 30);
      final outS = fs.run(str, minutes: 30);
      expect(setsOf(outH[0]), [('chest', 4), ('back', 3), ('delts', 3)]);
      expect(setsOf(outS[0]), [('chest', 4), ('back', 3)]);
      expect(secondsOf(outH[0], fh, 'hypertrophy'), lessThanOrEqualTo(budget));
      expect(secondsOf(outS[0], fs, 'strength'), lessThanOrEqualTo(budget));
      // The same exercise list holds fewer sets on a strength day (150 s rests).
      int total(PopulatedDay d) => d.exercisesA.fold(0, (a, e) => a + e.sets);
      expect(total(outS[0]), lessThan(total(outH[0])));
    });
  });

  group('caps and tops', () {
    test('session cap: intermediate 8 per muscle, focus 12', () {
      final f = Fx();
      for (var i = 0; i < 6; i++) {
        f.row('c$i', ['Chest']);
      }
      List<PopulatedDay> mk() => [f.day('strength', [for (var i = 0; i < 6; i++) f.ex('c$i')])];
      final plain = f.run(mk(), minutes: 90);
      expect(setsOf(plain[0]), [('c0', 4), ('c1', 4)]);
      final focus = f.run(mk(), minutes: 90, focus: {'Chest'});
      expect(setsOf(focus[0]), [('c0', 4), ('c1', 4), ('c2', 4)]);
    });

    test('weekly top: a non-focus group stays at 16 (intermediate build_muscle)', () {
      final f = Fx();
      final days = <PopulatedDay>[];
      for (var d = 0; d < 5; d++) {
        f.row('c${d}0', ['Chest']);
        f.row('c${d}1', ['Chest']);
        days.add(f.day('strength', [f.ex('c${d}0'), f.ex('c${d}1')]));
      }
      final out = f.run(days, minutes: 90);
      expect([for (final d in out) d.exercisesA.first.sets], [4, 4, 4, 2, 2]);
      expect(statsA().weekly['Chest'], 16);
      expect([for (final d in out) d.exercisesA.length], [1, 1, 1, 1, 1]);
    });

    test('lighter phase: every weekly total stays at the band bottom, focus included', () {
      final f = Fx();
      final days = <PopulatedDay>[];
      for (var d = 0; d < 4; d++) {
        final names = [for (var j = 0; j < 3; j++) 'c$d$j'];
        for (final n in names) {
          f.row(n, ['Chest']);
        }
        days.add(f.day('hypertrophy', [for (final n in names) f.ex(n)]));
      }
      f.run(days, minutes: 90, lighter: true, focus: {'Chest'});
      expect(statsA().weekly['Chest'], 12);
    });

    test('lighter phase: a focus group falls back to the ordinary session cap of 8, not 12', () {
      final f = Fx();
      for (var i = 0; i < 6; i++) {
        f.row('c$i', ['Chest']);
      }
      List<PopulatedDay> mk() => [f.day('strength', [for (var i = 0; i < 6; i++) f.ex('c$i')])];
      // Weekly top is the band bottom (12) here, so a third 4-set lift would fit the
      // week and the 12-set focus cap; only the ordinary cap of 8 refuses it.
      final lighter = f.run(mk(), minutes: 90, lighter: true, focus: {'Chest'});
      expect(setsOf(lighter[0]), [('c0', 4), ('c1', 4)]);
      final ordinary = f.run(mk(), minutes: 90, focus: {'Chest'});
      expect(setsOf(ordinary[0]), [('c0', 4), ('c1', 4), ('c2', 4)]);
    });

    test('focus reaches past the ordinary top (16) and stops at 25', () {
      final f = Fx();
      final days = <PopulatedDay>[];
      for (var d = 0; d < 4; d++) {
        f.row('c${d}0', ['Chest']);
        f.row('c${d}1', ['Chest']);
        days.add(f.day('strength', [f.ex('c${d}0'), f.ex('c${d}1')]));
      }
      f.run(days, minutes: 90, focus: {'Chest'});
      expect(statsA().weekly['Chest'], 25);
    });

    test('terminates: every focus exercise at 5 sets with time left returns', () {
      final f = Fx();
      for (var i = 0; i < 3; i++) {
        f.row('c$i', ['Chest']);
      }
      final days = [for (var i = 0; i < 3; i++) f.day('strength', [f.ex('c$i')])];
      final out = f.run(days, minutes: 90, focus: {'Chest'});
      expect([for (final d in out) d.exercisesA.first.sets], [5, 5, 5]);
      expect(statsA().weekly['Chest'], 15); // short of 25, and it stopped
    });
  });

  group('rows that are not budgeted', () {
    test('no-group exercise: a Burpee is checked against time only and never throws', () {
      final f = Fx();
      f.row('burpee', ['Full Body'], type: 'calisthenics', reps: '10-20', logging: 'bodyweight_reps');
      f.row('sq', ['Quads', 'Glutes']);
      expect(BudgetMuscleGroups.of(['Full Body']), isEmpty);
      final out = f.run(
        [f.day('hypertrophy', [f.ex('sq'), f.ex('burpee', logging: 'bodyweight_reps')])],
        minutes: 60,
        goal: 'lose_fat',
      );
      expect(out[0].exercisesA.map((e) => e.exerciseName), ['sq', 'burpee']);
      expect(out[0].exercisesA.last.sets, 3); // the day's desired, no group to cap it
    });

    test('not budgeted: a repeat pin and a timed plank keep their sets; a budgeted row is trimmed', () {
      final f = Fx();
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('pin', ['Chest']);
      f.row('b1', ['Chest']);
      f.row('b2', ['Lats']);
      f.row('b3', ['Quads']);
      final day = f.day('hypertrophy', [
        f.ex('pin', sets: 6, customOrigin: 'repeat_pin'),
        f.ex('plank', sets: 3, logging: 'timed', rest: 30),
        f.ex('b1'),
        f.ex('b2'),
        f.ex('b3'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(setsOf(out[0]), [('pin', 6), ('plank', 3), ('b1', 2)]);
    });

    test('guard: a day whose not-budgeted rows spend the budget still gets one lift at 2 sets', () {
      final f = Fx();
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('c1', ['Chest']);
      f.row('c2', ['Lats']);
      List<PlannedExercise> list() => [
            f.ex('plank', sets: 4, logging: 'timed', rest: 60),
            f.ex('plank', sets: 4, logging: 'timed', rest: 60),
            f.ex('c1'),
            f.ex('c2'),
          ];
      final days = [f.day('hypertrophy', list())];
      // Precondition: the two planks alone already overspend the 20-minute day,
      // so pass A admits nothing and only the guard can put a lift on it.
      final ledger = BudgetLedger(f.ctx(days, minutes: 20), 1);
      final plank = SessionBudget.exerciseSeconds(archetype: 'B', sets: 4, restSeconds: 60);
      ledger.add(0, const {}, 0, plank * 2);
      expect(ledger.secondsLeft(0), lessThan(0));

      final out = f.run(days, minutes: 20);
      expect(setsOf(out[0]), [('plank', 4), ('plank', 4), ('c1', 2)]);
      expect(statsA().timeForcedFirst, 1);
      expect(statsA().capForcedFirst, 0);
    });

    // Days 0 and 1 fill Chest to its weekly top of 16 (4 + 4 each); day 2's six
    // planks (6 x 444 s) overspend its 2220 s budget, so pass A admits nothing there.
    (List<PopulatedDay>, Fx) crowdedChestWeek(List<String> afterChest) {
      final f = Fx();
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('bi', ['Biceps'], type: 'isolation', reps: '10-15');
      for (var i = 1; i <= 9; i++) {
        f.row('c$i', ['Chest']);
      }
      final days = [
        f.day('strength', [for (final i in [1, 2, 3, 4]) f.ex('c$i')]),
        f.day('strength', [for (final i in [5, 6, 7, 8]) f.ex('c$i')]),
        f.day('strength', [
          for (var i = 0; i < 6; i++) f.ex('plank', sets: 4, logging: 'timed', rest: 60),
          f.ex('c9'),
          for (final n in afterChest) f.ex(n),
        ]),
      ];
      final ledger = BudgetLedger(f.ctx(days, minutes: 45), 3);
      ledger.add(2, const {}, 0, 6 * SessionBudget.exerciseSeconds(archetype: 'B', sets: 4, restSeconds: 60));
      expect(ledger.secondsLeft(2), lessThan(0), reason: 'fixture: day 2 must be time-starved');
      return (days, f);
    }

    test('guard with no weekly room anywhere: rank 0 is forced anyway and capForcedFirst counts it', () {
      final (days, f) = crowdedChestWeek(const []);
      final out = f.run(days, minutes: 45);
      expect(setsOf(out[0]), [('c1', 4), ('c2', 4)]);
      expect(setsOf(out[1]), [('c5', 4), ('c6', 4)]);
      expect(setsOf(out[2]).where((e) => e.$1 == 'c9'), [('c9', 2)]);
      expect(statsA().weekly['Chest'], 18); // past the top of 16: the one thing the guard may do
      expect(statsA().capForcedFirst, 1);
      expect(statsA().timeForcedFirst, 0);
      expect(statsA().forcedDays, [2]);
    });

    test('guard: when rank 0 has no weekly room the first exercise that does is the one forced', () {
      final (days, f) = crowdedChestWeek(const ['bi']);
      final out = f.run(days, minutes: 45);
      expect(setsOf(out[2]).where((e) => e.$1 == 'c9' || e.$1 == 'bi'), [('bi', 2)]);
      expect(statsA().weekly['Chest'], 16);
      expect(statsA().weekly['Biceps'], 2);
      expect(statsA().timeForcedFirst, 1);
      expect(statsA().capForcedFirst, 0);
    });

    test('not-budgeted rest: a timed row is timed at its OWN rest, not the strength day 150 s', () {
      final f = Fx();
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('sq', ['Quads']);
      final days = [
        f.day('strength', [
          f.ex('plank', sets: 3, logging: 'timed', rest: 30),
          f.ex('plank', sets: 3, logging: 'timed', rest: 30),
          f.ex('sq'),
        ]),
      ];
      final out = f.run(days, minutes: 30);
      expect(out[0].exercisesA.last.sets, 4);
      // 1440 s - 2 x 252 s (planks at 30 s rest) - 816 s (4 sets at 150 s) = 120 s.
      expect(statsA().firstLifts.single.secondsLeft, closeTo(120.0, 1e-6));
    });
  });

  group('B variant', () {
    test('a B list equal to A is copied, not re-allocated, so those days match exactly', () {
      final f = Fx();
      for (final (n, m) in [
        ('a1', 'Chest'), ('a2', 'Lats'), ('b1', 'Quads'), ('s1', 'Hamstrings'), ('s2', 'Glutes'),
      ]) {
        f.row(n, [m]);
      }
      final shared1 = [f.ex('s1'), f.ex('s2')];
      final days = [
        f.day('hypertrophy', [f.ex('a1'), f.ex('a2')], b: [f.ex('b1'), f.ex('a2')]),
        f.day('hypertrophy', shared1), // B is the SAME list as A
        f.day('hypertrophy', [f.ex('a1'), f.ex('s1')], b: [f.ex('b1'), f.ex('s2')]),
        f.day('hypertrophy', [f.ex('a2'), f.ex('s2')], b: [f.ex('a2'), f.ex('s2')]), // equal names
      ];
      final out = f.run(days, is6Day: false);
      expect(setsOf(out[1]), setsOf(out[1], b: true));
      expect(setsOf(out[3]), setsOf(out[3], b: true));
      expect(setsOf(out[0], b: true), [('b1', 5), ('a2', 5)]);
      expect(setsOf(out[2], b: true), [('b1', 5), ('s2', 3)]);
      expect(statsB().weekly['Glutes'], 13); // 5 + 5 copied from A, then 3
    });

    test('a copied day is never grown in B, even when its group is below the floor there', () {
      final f = Fx();
      for (final n in ['b1', 'b2', 'e1']) {
        f.row(n, ['Biceps'], type: 'isolation', reps: '10-15');
      }
      f.row('ch', ['Chest']);
      final shared = [f.ex('e1')];
      final days = [
        f.day('hypertrophy', [f.ex('b1'), f.ex('b2')], b: [f.ex('ch')]),
        f.day('hypertrophy', shared), // B is the SAME list as A
      ];
      final out = f.run(days, minutes: 90, is6Day: false);
      // A: the floor pass takes b1 to 5 and e1 to 4 (Biceps 5 + 3 + 4 = 12).
      expect(setsOf(out[0]), [('b1', 5), ('b2', 3)]);
      expect(setsOf(out[1]), [('e1', 4)]);
      // B: Biceps is only e1's 4, far below 12, but e1 is a copied day and stays put.
      expect(setsOf(out[0], b: true), [('ch', 5)]);
      expect(setsOf(out[1], b: true), [('e1', 4)]);
      expect(statsB().weekly['Biceps'], 4);
      // The label says WHY it stays short: a frozen copy day, not a cap or a top
      // (B-pass R1 P3-3). Nothing else in B credits Biceps and the day could take a set.
      expect(statsB().belowFloor['Biceps'], 'copy_day_limited');
      // In A the same group is not limited by a copy day: A has no copy days.
      expect(statsA().belowFloor['Biceps'], isNot('copy_day_limited'));
    });

    test('a 6-day plan allocates A only and gives B the same sets', () {
      final f = Fx();
      f.row('x', ['Chest']);
      f.row('y', ['Quads']);
      final days = [f.day('hypertrophy', [f.ex('x'), f.ex('y')])];
      final out = f.run(days, is6Day: true);
      expect(setsOf(out[0], b: true), setsOf(out[0]));
      expect(SessionSetAllocator.debugLastStats!.containsKey('B'), isFalse);
    });
  });

  group('floors', () {
    test('the floor pass gives each +1 to the first exercise in (rank, day) order, and stops AT the floor', () {
      // Biceps sits at rank 1 on day 0 and at rank 0 on days 1 and 2. Each curl starts
      // at 3 (total 9) and build_muscle beginner needs 10: the one extra set goes to
      // day 1's rank-0 curl, not to day 0's earlier-day rank-1 curl, and nothing more.
      final f = Fx();
      f.row('ch', ['Chest']);
      for (final n in ['b0', 'b1', 'b2']) {
        f.row(n, ['Biceps'], type: 'isolation', reps: '10-15');
      }
      final days = [
        f.day('hypertrophy', [f.ex('ch'), f.ex('b0')]),
        f.day('hypertrophy', [f.ex('b1')]),
        f.day('hypertrophy', [f.ex('b2')]),
      ];
      final out = f.run(days, minutes: 90, level: 'beginner');
      expect(setsOf(out[0]), [('ch', 5), ('b0', 3)]);
      expect(setsOf(out[1]), [('b1', 4)]);
      expect(setsOf(out[2]), [('b2', 3)]);
      expect(statsA().weekly['Biceps'], 10);
    });

    test('a floor of 12 is reached exactly: 5 + 4 + 3, never 13', () {
      final f = Fx();
      for (var i = 0; i < 3; i++) {
        f.row('e$i', ['Biceps'], type: 'isolation', reps: '10-15');
      }
      final days = [for (var i = 0; i < 3; i++) f.day('hypertrophy', [f.ex('e$i')])];
      final out = f.run(days, minutes: 90);
      expect([for (final d in out) d.exercisesA.first.sets], [5, 4, 3]);
      expect(statsA().weekly['Biceps'], 12);
    });
  });

  group('floor labels', () {
    test('cap_limited: every crediting exercise is at its own session cap', () {
      final f = Fx();
      f.row('c1', ['Chest']);
      f.row('c2', ['Chest']);
      f.run([f.day('strength', [f.ex('c1'), f.ex('c2')])], minutes: 90);
      expect(statsA().belowFloor['Chest'], 'cap_limited');
    });

    test('not_trained_by_split: no exercise in the week credits the group', () {
      final f = Fx();
      f.row('c1', ['Chest']);
      f.run([f.day('strength', [f.ex('c1')])], minutes: 90);
      expect(statsA().belowFloor['Calves'], 'not_trained_by_split');
    });

    test('co_group_limited: the group is below its floor only because a co-group is at its top', () {
      final f = Fx();
      f.row('squat', ['Quads', 'Glutes']);
      for (final n in ['ht1', 'ht2', 'ht3']) {
        f.row(n, ['Glutes']);
      }
      final days = [
        for (final n in ['squat', 'ht1', 'ht2', 'ht3']) f.day('strength', [f.ex(n)]),
      ];
      f.run(days, minutes: 90);
      expect(statsA().weekly['Glutes'], 16);
      expect(statsA().weekly['Quads'], 4);
      expect(statsA().belowFloor['Quads'], 'co_group_limited');
    });

    test('time_limited: a crediting exercise was removed for time alone', () {
      final f = Fx();
      f.row('a', ['Chest']);
      f.row('b', ['Chest']);
      f.row('c', ['Biceps'], type: 'isolation', reps: '10-15');
      f.run([f.day('hypertrophy', [f.ex('a'), f.ex('b'), f.ex('c')])], minutes: 30);
      expect(statsA().belowFloor['Biceps'], 'time_limited');
    });

    test('time_limited wins over cap_limited when one crediting exercise is removed for time '
        'and another sits at its cap', () {
      final f = Fx();
      for (final n in ['t1', 't2', 't3', 'x']) {
        f.row(n, ['Triceps']);
      }
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      // Day 0 fills its Triceps session cap (3 + 3 + 2 = 8) with time to spare, so
      // its three exercises are refused by the cap alone. Day 1's three planks spend
      // its time, so `x` is refused by time alone (and the guard puts it on at 2).
      final d1 = f.day('hypertrophy', [f.ex('t1'), f.ex('t2'), f.ex('t3')]);
      final d2 = f.day('hypertrophy', [
        for (var i = 0; i < 3; i++) f.ex('plank', sets: 4, logging: 'timed', rest: 60),
        f.ex('x'),
      ]);
      final out = f.run([d1, d2], minutes: 30);
      expect(setsOf(out[0]), [('t1', 3), ('t2', 3), ('t3', 2)]);
      expect(setsOf(out[1]).last, ('x', 2));
      expect(statsA().weekly['Triceps'], 10);
      expect(statsA().belowFloor['Triceps'], 'time_limited');
    });
  });

  group('contract', () {
    test('the input days are not mutated and the output keeps the exercise order', () {
      final f = Fx();
      for (final n in ['a', 'b', 'c']) {
        f.row(n, ['Chest']);
      }
      final a = [f.ex('a'), f.ex('b'), f.ex('c')];
      final days = [f.day('strength', a)];
      final before = a.map((e) => e.sets).toList();
      final out = f.run(days, minutes: 90);
      expect(a.map((e) => e.sets).toList(), before);
      expect(out[0].exercisesA.map((e) => e.exerciseName).toList(), ['a', 'b']);
    });

    test('an empty plan and an all-custom day do not crash', () {
      final f = Fx();
      expect(f.run(const [], minutes: 60), isEmpty);
      f.row('pin', ['Chest']);
      final out = f.run(
        [f.day('hypertrophy', [f.ex('pin', sets: 5, customOrigin: 'repeat_pin')])],
        minutes: 30,
      );
      expect(setsOf(out[0]), [('pin', 5)]);
      expect(statsA().timeForcedFirst, 0);
    });

    test('a day with no budgeted exercise is left as is (no forced lift)', () {
      final f = Fx();
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      final out = f.run(
        [f.day('hypertrophy', [f.ex('plank', sets: 3, logging: 'timed', rest: 30)])],
        minutes: 30,
      );
      expect(setsOf(out[0]), [('plank', 3)]);
      expect(statsA().timeForcedFirst, 0);
      expect(statsA().capForcedFirst, 0);
    });
  });

  group('invariants over the shipped library (seeded sweep)', () {
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();
    final byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
    final strengthRows = [
      for (final r in rows)
        if (const {'weight_reps', 'bodyweight_reps'}.contains(r['logging_type']) &&
            BudgetMuscleGroups.of([
              for (final m in (r['primary_muscles'] as List)) '$m',
            ]).isNotEmpty)
          r,
    ];

    test('220 random plans: every cap, top and time budget holds unless the guard fired', () {
      final rnd = Random(20261024);
      const intensities = ['strength', 'hypertrophy', 'endurance'];
      const goals = ['build_muscle', 'strength', 'lose_fat', 'general_fitness'];
      const levels = ['beginner', 'intermediate', 'advanced'];
      var guarded = 0;
      for (var plan = 0; plan < 220; plan++) {
        final nDays = 3 + rnd.nextInt(4);
        final is6 = nDays == 6;
        final minutes = const [30, 45, 60, 75, 90][rnd.nextInt(5)];
        final goal = goals[rnd.nextInt(4)];
        final level = levels[rnd.nextInt(3)];
        final lighter = rnd.nextInt(6) == 0;
        final focus = rnd.nextBool()
            ? <String>{BudgetMuscleGroups.groups[rnd.nextInt(10)]}
            : <String>{};
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
          lighterPhase: lighter,
          focusGroups: focus,
          archetypeByName: {
            for (final e in byName.entries) e.key: SessionBudget.archetypeOfRow(e.value),
          },
        );
        final out = SessionSetAllocator.allocate(
            days: days, ctx: ctx, rowsByName: byName, is6Day: is6);
        expect(out.length, nDays);

        for (final variant in is6 ? ['A'] : ['A', 'B']) {
          final stats = SessionSetAllocator.debugLastStats![variant]!;
          final forced = stats.timeForcedFirst + stats.capForcedFirst;
          if (forced > 0) guarded++;
          final ledger = BudgetLedger(ctx, nDays);
          for (var d = 0; d < nDays; d++) {
            final src = variant == 'A' ? days[d].exercisesA : days[d].exercisesB;
            final got = variant == 'A' ? out[d].exercisesA : out[d].exercisesB;
            // Order preserved; only removals.
            final srcNames = src.map((e) => e.exerciseName).toList();
            var cursor = 0;
            for (final e in got) {
              cursor = srcNames.indexOf(e.exerciseName, cursor);
              expect(cursor, greaterThanOrEqualTo(0), reason: 'plan $plan day $d order');
              cursor++;
            }
            for (final e in got) {
              expect(e.sets, inInclusiveRange(2, SessionBudget.maxSetsPerExercise),
                  reason: 'plan $plan day $d ${e.exerciseName}');
              ledger.add(
                d,
                BudgetMuscleGroups.of(e.primaryMuscles ??
                    [for (final m in (byName[e.exerciseName.toLowerCase()]!['primary_muscles']
                        as List)) '$m']),
                e.sets,
                SessionBudget.exerciseSeconds(
                  archetype: ctx.archetypeByName[e.exerciseName.toLowerCase()]!,
                  sets: e.sets,
                  restSeconds: SessionBudget.restFor(days[d].intensity),
                ),
              );
            }
          }
          if (forced == 0) {
            for (var d = 0; d < nDays; d++) {
              expect(ledger.secondsLeft(d), greaterThanOrEqualTo(-1e-6),
                  reason: 'plan $plan $variant day $d time');
            }
          }
          for (final g in BudgetMuscleGroups.groups) {
            if (forced == 0) {
              expect(ledger.week(g), lessThanOrEqualTo(ledger.weeklyTop(g)),
                  reason: 'plan $plan $variant $g weekly');
            }
            for (var d = 0; d < nDays; d++) {
              if (forced == 0) {
                expect(ledger.session(d, g), lessThanOrEqualTo(ledger.cap(g)),
                    reason: 'plan $plan $variant $g day $d session');
              }
            }
          }
        }
      }
      // `guarded` is reported, not asserted: random picks seldom empty a whole day,
      // and the guard itself is pinned by the crafted 'guard' test above.
      // ignore: avoid_print
      print('seeded sweep: $guarded variant(s) needed the empty-day guard');
    });

    test('deterministic: the same input gives the same output', () {
      final f = Fx();
      for (final n in ['a', 'b', 'c', 'd']) {
        f.row(n, ['Chest']);
      }
      List<PopulatedDay> mk() => [
            f.day('strength', [for (final n in ['a', 'b', 'c', 'd']) f.ex(n)]),
          ];
      final one = f.run(mk(), minutes: 45);
      final two = f.run(mk(), minutes: 45);
      expect(setsOf(one[0]), setsOf(two[0]));
    });
  });

  group('B-pass fixes (docs/reviews/session-set-budget-bpass.md)', () {
    test('R2 P3-8: the muscles an exercise CARRIES win over its row', () {
      final f = Fx();
      f.row('x', ['Chest']);
      final carried = f.ex('x').copyWith(primaryMuscles: ['Lats']);
      f.run([f.day('hypertrophy', [carried])], minutes: 90);
      expect(statsA().weekly['Back'], greaterThan(0));
      expect(statsA().weekly.containsKey('Chest'), isFalse);
    });

    test('R2 P3-8: a primary_muscles value that is not a list reads as no muscle, it does not throw', () {
      final f = Fx();
      final e = f.ex('x'); // built before the row exists, so it carries no muscles
      f.rows['x'] = {
        'name': 'x',
        'primary_muscles': 'Chest',
        'exercise_type': ['compound'],
        'rep_range': '8-12',
        'logging_type': 'weight_reps',
      };
      final out = f.run([f.day('hypertrophy', [e])], minutes: 90);
      expect(setsOf(out[0]), [('x', 3)]); // sized by time only: the day's desired sets
      expect(statsA().weekly, isEmpty);
    });

    test('R1 P3-2: a row the context does not know is NOT budgeted, however many rows the caller passes', () {
      // SessionBudget.isBudgeted (ctx.archetypeByName) is the one rule: a name that is in
      // rowsByName but not in the context keeps its 9 sets, as apply and titration see it.
      final f = Fx();
      f.row('a', ['Chest']);
      final days = [f.day('strength', [f.ex('a'), f.ex('ghost', sets: 9)])];
      final out = SessionSetAllocator.allocate(
        days: days,
        ctx: f.ctx(days, minutes: 90),
        rowsByName: {
          ...f.rows,
          'ghost': {
            'name': 'ghost',
            'primary_muscles': ['Lats'],
            'exercise_type': ['compound'],
            'rep_range': '8-12',
            'logging_type': 'weight_reps',
          },
        },
        is6Day: true,
      );
      expect(out[0].exercisesA.firstWhere((e) => e.exerciseName == 'ghost').sets, 9);
      expect(statsA().weekly.containsKey('Back'), isFalse);
    });

    test('R1 P3-7: two A/B lists whose names only JOIN alike are not the same day', () {
      // ['x, y', 'z'] and ['x', 'y, z'] both print as "[x, y, z]". B must be allocated
      // on its own: its 6-set timed row leaves 270 s, so 'y, z' gets the guard's 2 sets,
      // not the 4 that A's first exercise got.
      final f = Fx();
      f.row('x, y', ['Chest']);
      f.row('z', ['Lats']);
      f.row('x', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('y, z', ['Hamstrings']);
      final days = [
        f.day(
          'strength',
          [f.ex('x, y'), f.ex('z')],
          b: [f.ex('x', sets: 6, logging: 'timed', rest: 141), f.ex('y, z')],
        ),
      ];
      final out = f.run(days, minutes: 30, is6Day: false);
      expect(setsOf(out[0]), [('x, y', 4), ('z', 3)]);
      expect(setsOf(out[0], b: true), [('x', 6), ('y, z', 2)]);
      expect(statsB().timeForcedFirst, 1);
      expect(statsA().firstLifts.single.groups, {'Chest'});
    });

    test('R3 P2-1: a cardio row prescribed in minutes spends those minutes, so the lift shrinks', () {
      // 60 minutes = 3000 s. A 20-40 min treadmill row costs 1.2 x (30 + 1800) = 2196 s,
      // leaving 804 s: the bench gets 3 sets (594 s) and cannot grow (the 4th costs 816 s).
      // The same row prescribed "30s" costs 84 s and leaves the bench its 4, then the floor
      // pass grows it to 5.
      Map<String, int> benchSets(String reps) {
        final f = Fx();
        f.row('bench', ['Chest']);
        f.row('run', ['Core'], type: 'cardio', reps: '20-30', logging: 'cardio');
        final run = f.ex('run', sets: 1, logging: 'cardio', rest: 60).copyWith(reps: reps);
        final out = f.run([f.day('strength', [run, f.ex('bench')])], minutes: 60);
        return {for (final (n, s) in setsOf(out[0])) n: s};
      }

      expect(benchSets('20-40 min')['bench'], 3);
      expect(benchSets('30s')['bench'], 5);
    });

    test('R1 P2-2: a lead lift that does not fit is dropped while a cheaper lift stays; the stat says so', () {
      // The policy: the lead lift is protected from the WEEK (reservation) and from an
      // EMPTY day (guard), not from the day's clock. When 2 sets of it cost more than the
      // time left and a 2-set isolation costs less, the isolation is kept and the day's
      // firstLifts entry reads sets 0. The gate counts these days in the report.
      final f = Fx();
      f.row('cl', ['Chest']);
      f.row('bi', ['Biceps'], type: 'isolation', reps: '10-15');
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      final days = [
        f.day('hypertrophy', [
          f.ex('plank', sets: 6, logging: 'timed', rest: 141),
          f.ex('cl'),
          f.ex('bi'),
        ]),
      ];
      final out = f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner');
      expect(setsOf(out[0]).where((e) => e.$1 != 'plank'), [('bi', 2)]);
      final lead = statsA().firstLifts.single;
      expect(lead.sets, 0);
      expect(lead.groups, {'Chest'});
      expect(statsA().timeForcedFirst, 0);
    });
  });
}
