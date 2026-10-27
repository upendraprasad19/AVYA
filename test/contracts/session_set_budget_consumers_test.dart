// B2 Task 4 (docs/plans/2026-10-22-session-set-budget.md): the stages after the
// allocator take an optional SessionBudgetContext. `null` is today's path
// verbatim; a context makes each stage honour the same ledger the allocator used.
//
// Crafted fixtures with literals worked out by hand (small enough to check), plus
// a seeded property check that the allocator's output fed through `apply` never
// breaks a group top, a session cap or the day's time budget in any of the 4 weeks.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/warmup_cooldown.dart';

import '../helpers/session_budget_fixtures.dart';

List<int> setsIn(List<WeekPlan> weeks, int week, int day) =>
    [for (final e in weeks[week].workoutDays[day].exercises) e.sets];

WeekPlan weekOf(List<List<PlannedExercise>> days, {String character = 'baseline'}) => WeekPlan(
      weekNumber: 1,
      weekInPhase: 1,
      overloadNotes: '',
      weekCharacter: character,
      workoutDays: [
        for (var i = 0; i < days.length; i++)
          WorkoutDay(dayNumber: i + 1, name: 'D', focus: 'F', exercises: days[i]),
      ],
    );

List<List<int>> grid(WeekPlan w) => [
      for (final d in w.workoutDays) [for (final e in d.exercises) e.sets],
    ];

List<List<int>> workingGrid(WeekPlan w) => [
      for (final d in w.workoutDays) [for (final e in d.exercises) e.workingSets ?? -1],
    ];

void main() {
  group('PeriodizationEngine.apply with a budget', () {
    (Fx, List<PopulatedDay>) chestDay() {
      final f = Fx();
      f.row('bench', ['Chest']);
      f.row('fly', ['Chest'], type: 'isolation', reps: '10-15');
      return (f, [f.day('hypertrophy', [f.ex('bench'), f.ex('fly')])]);
    }

    test('base sets are used as allocated: no cycle multiplier at phase 9, no 4-set minimum', () {
      final (f, days) = chestDay();
      final ctx = f.ctx(days, minutes: 90);
      for (final phase in [1, 9]) {
        final on = PeriodizationEngine.apply(
          populated: days,
          phase: phase,
          is6Day: true,
          effectiveExp: 'intermediate',
          budget: ctx,
        );
        expect(setsIn(on, 0, 0), [3, 3], reason: 'phase $phase');
      }
      // The same plan without a budget: round(3 x 1.2) = 4, and 4 is the minimum.
      final off = PeriodizationEngine.apply(
          populated: days, phase: 9, is6Day: true, effectiveExp: 'intermediate');
      expect(setsIn(off, 0, 0), [4, 4]);
      final off1 = PeriodizationEngine.apply(
          populated: days, phase: 1, is6Day: true, effectiveExp: 'intermediate');
      expect(setsIn(off1, 0, 0), [4, 4]);
    });

    test('the four weeks of a 6-day plan: allocated, +1 where it fits, allocated, floor(0.6 x)', () {
      final f = Fx();
      f.row('c1', ['Chest']);
      f.row('c2', ['Chest']);
      f.row('bi', ['Biceps'], type: 'isolation', reps: '10-15');
      // Chest is at its session cap (4 + 4 = 8), Biceps has room.
      final days = [
        f.day('strength', [f.ex('c1', sets: 4), f.ex('c2', sets: 4), f.ex('bi', sets: 3)]),
      ];
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(days, minutes: 90),
      );
      expect(setsIn(weeks, 0, 0), [4, 4, 3]);
      expect(setsIn(weeks, 1, 0), [4, 4, 4]); // the cap refuses both chest lifts
      expect(setsIn(weeks, 2, 0), [4, 4, 3]);
      expect(setsIn(weeks, 3, 0), [2, 2, 1]); // floor(0.6 x 4) = 2, floor(0.6 x 3) = 1
    });

    test('week-2 cue: an exercise that gained no set keeps week 1\'s cue and note', () {
      final f = Fx();
      f.row('c1', ['Chest']);
      f.row('c2', ['Chest']);
      f.row('bi', ['Biceps'], type: 'isolation', reps: '10-15');
      final mixed = [f.day('strength', [f.ex('c1', sets: 4), f.ex('c2', sets: 4), f.ex('bi', sets: 3)])];
      final w = PeriodizationEngine.apply(
        populated: mixed,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(mixed, minutes: 90),
      );
      final wk1 = w[0].workoutDays[0].exercises;
      final wk2 = w[1].workoutDays[0].exercises;
      expect(wk2[0].weightCue, wk1[0].weightCue); // refused: week 1's cue
      expect(wk2[1].weightCue, wk1[1].weightCue);
      expect(wk2[2].weightCue, isNot(wk1[2].weightCue)); // gained: the overreach cue
      expect(w[1].overloadNotes, isNot(w[0].overloadNotes)); // somebody gained

      final none = [f.day('strength', [f.ex('c1', sets: 4), f.ex('c2', sets: 4)])];
      final n = PeriodizationEngine.apply(
        populated: none,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(none, minutes: 90),
      );
      expect(setsIn(n, 1, 0), [4, 4]);
      expect(n[1].overloadNotes, n[0].overloadNotes); // nobody gained: week 1's note
    });

    test('week 4 and the stash, for a 4-day plan (variant B) and a 6-day plan (variant A)', () {
      final f = Fx();
      for (final (n, m) in [('a1', 'Chest'), ('a2', 'Lats'), ('b1', 'Quads'), ('b2', 'Hamstrings')]) {
        f.row(n, [m]);
      }
      final days = [
        f.day('hypertrophy', [f.ex('a1', sets: 4), f.ex('a2', sets: 2)],
            b: [f.ex('b1', sets: 3), f.ex('b2', sets: 5)]),
      ];
      final ctx = f.ctx(days, minutes: 90);
      final four = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: false,
        effectiveExp: 'intermediate',
        stashWorkingBase: true,
        budget: ctx,
      );
      expect(setsIn(four, 0, 0), [4, 2]);
      expect(setsIn(four, 1, 0), [4, 5]); // B: b1 gains, b2 is already at 5
      expect(setsIn(four, 2, 0), [4, 2]);
      expect(setsIn(four, 3, 0), [1, 3]); // floor(0.6 x 3) = 1, floor(0.6 x 5) = 3
      // The stash is each exercise's OWN allocated baseline, not a neighbour's.
      expect([for (final e in four[3].workoutDays[0].exercises) e.workingSets], [3, 5]);

      final six = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        stashWorkingBase: true,
        budget: ctx,
      );
      expect(setsIn(six, 3, 0), [2, 1]); // A: floor(2.4) = 2, floor(1.2) = 1
      expect([for (final e in six[3].workoutDays[0].exercises) e.workingSets], [4, 2]);
    });

    test('week 4 keeps a one-set exercise at one (floor(0.6 x 1) would be 0)', () {
      final (f, _) = chestDay();
      final days = [f.day('hypertrophy', [f.ex('bench', sets: 1), f.ex('fly', sets: 2)])];
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(days, minutes: 90),
      );
      expect(setsIn(weeks, 3, 0), [1, 1]); // 1 stays 1; floor(0.6 x 2) = 1
    });

    test('the physique bring-up +1 is absent with a budget', () {
      final (f, days) = chestDay();
      final on = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        bodyFocus: const ['chest'],
        budget: f.ctx(days, minutes: 90),
      );
      expect(setsIn(on, 0, 0), [3, 3]);
      final off = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        bodyFocus: const ['chest'],
      );
      expect(setsIn(off, 0, 0), [5, 5]); // max(4, 3) + 1
    });

    test('Ruling 8: a timed row gets its week-2 +1 only while the day\'s time allows', () {
      final f = Fx();
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      PlannedExercise plank() => f.ex('plank', sets: 3, logging: 'timed', rest: 30);
      // 30 minutes: 1440 s. One plank is 252 s; six are 1512 s, already over.
      // Day 2 holds five planks: 1260 s at their OWN rest of 30 s (room for two more
      // sets, 84 s each), but 1800 s if they were timed at the day's rest of 75 s.
      final days = [
        f.day('hypertrophy', [plank()]),
        f.day('hypertrophy', [for (var i = 0; i < 6; i++) plank()]),
        f.day('hypertrophy', [for (var i = 0; i < 5; i++) plank()]),
      ];
      final budget = (30 - SessionBudget.warmCoolMinutes(30)) * 60;
      expect(6 * SessionBudget.exerciseSeconds(archetype: 'B', sets: 3, restSeconds: 30),
          greaterThan(budget));
      expect(5 * SessionBudget.exerciseSeconds(archetype: 'B', sets: 3, restSeconds: 30),
          lessThan(budget));
      expect(5 * SessionBudget.exerciseSeconds(archetype: 'B', sets: 3, restSeconds: 75),
          greaterThan(budget));
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(days, minutes: 30),
      );
      expect(setsIn(weeks, 0, 0), [3]);
      expect(setsIn(weeks, 1, 0), [4]); // day 0 has the time
      expect(setsIn(weeks, 1, 1), [3, 3, 3, 3, 3, 3]); // day 1 does not
      // Day 2: 1260 s + 84 + 84 = 1428 fits, a third +1 (1512) does not.
      expect(setsIn(weeks, 1, 2), [4, 4, 3, 3, 3]);
    });

    test('week 2 never takes a budgeted exercise past 5 sets', () {
      final f = Fx();
      f.row('a', ['Chest']);
      f.row('b', ['Biceps'], type: 'isolation', reps: '10-15');
      final days = [f.day('hypertrophy', [f.ex('a', sets: 5), f.ex('b', sets: 3)])];
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(days, minutes: 90),
      );
      expect(setsIn(weeks, 1, 0), [5, 4]);
    });

    test('week 2 visits the exercises rank-major across the days, not day by day', () {
      // general_fitness intermediate: Chest top 12. Baseline 3 + 3 + 4 = 10 leaves
      // room for exactly two sets. Rank-major gives them to the two rank-0 lifts
      // (day 0's c1, day 1's c3); a day-major order would give both to day 0.
      final f = Fx();
      for (final n in ['c1', 'c2', 'c3']) {
        f.row(n, ['Chest']);
      }
      final days = [
        f.day('hypertrophy', [f.ex('c1', sets: 3), f.ex('c2', sets: 3)]),
        f.day('hypertrophy', [f.ex('c3', sets: 4)]),
      ];
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        effectiveExp: 'intermediate',
        budget: f.ctx(days, minutes: 90, goal: 'general_fitness'),
      );
      expect(setsIn(weeks, 1, 0), [4, 3]);
      expect(setsIn(weeks, 1, 1), [5]);
    });

    test('a null budget is today\'s V4 wave: the 4-week grids are pinned to recorded literals (B-pass R2 P3-2)', () {
      // The old version of this test compared apply(...) with apply(..., budget: null),
      // the same call twice. These are the OFF engine's own sets x reps @ rest for the
      // chest day, recorded from the engine with the budget stage absent; the
      // generator golden pins generateV4 as a whole and this pins apply's own branch.
      final (_, days) = chestDay();
      String grids(int phase, String exp, bool is6) {
        final weeks = PeriodizationEngine.apply(
            populated: days, phase: phase, is6Day: is6, effectiveExp: exp);
        return [
          for (final w in weeks)
            [for (final e in w.workoutDays[0].exercises) '${e.sets}x${e.reps}@${e.restSeconds}']
                .join(','),
        ].join(' | ');
      }

      expect(grids(5, 'advanced', false),
          '4x10@75,4x13@75 | 4x10@75,4x13@75 | 4x8@75,4x11@75 | 1x8@75,1x10@75');
      expect(grids(1, 'intermediate', true),
          '4x10@75,4x13@75 | 4x10@75,4x13@75 | 4x8@75,4x11@75 | 1x8@75,1x10@75');
      expect(grids(9, 'intermediate', true),
          '4x10@75,4x13@75 | 5x10@75,5x13@75 | 4x8@75,4x11@75 | 2x8@75,2x10@75');
      // An explicit null is the omitted argument.
      final a = PeriodizationEngine.apply(
          populated: days, phase: 5, is6Day: false, effectiveExp: 'advanced');
      final b = PeriodizationEngine.apply(
          populated: days, phase: 5, is6Day: false, effectiveExp: 'advanced', budget: null);
      expect(jsonEncode([for (final w in a) [for (final d in w.workoutDays) d.toMap()]]),
          jsonEncode([for (final w in b) [for (final d in w.workoutDays) d.toMap()]]));
    });

    group('seeded property: the allocator\'s output through apply stays inside the budget', () {
      final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
      final strengthRows = [
        for (final r in rows)
          if (const {'weight_reps', 'bodyweight_reps'}.contains(r['logging_type']) &&
              BudgetMuscleGroups.of([for (final m in (r['primary_muscles'] as List)) '$m'])
                  .isNotEmpty)
            r,
      ];
      final byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};

      test('60 random plans, 4 weeks each', () {
        final rnd = Random(20261025);
        const intensities = ['strength', 'hypertrophy', 'endurance'];
        const goals = ['build_muscle', 'strength', 'lose_fat', 'general_fitness'];
        const levels = ['beginner', 'intermediate', 'advanced'];
        var checked = 0;
        for (var plan = 0; plan < 60; plan++) {
          final nDays = 3 + rnd.nextInt(4);
          final is6 = nDays == 6;
          final minutes = const [30, 45, 60, 75, 90][rnd.nextInt(5)];
          final goal = goals[rnd.nextInt(4)];
          final level = levels[rnd.nextInt(3)];
          final lighter = rnd.nextInt(6) == 0;
          final focus = rnd.nextBool()
              ? <String>{BudgetMuscleGroups.groups[rnd.nextInt(10)]}
              : <String>{};

          List<PlannedExercise> pick() {
            final n = 3 + rnd.nextInt(6);
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
                  repRange: byName[name.toLowerCase()]!['rep_range'] as String?,
                  primaryMuscles: [
                    for (final m in (byName[name.toLowerCase()]!['primary_muscles'] as List))
                      '$m',
                  ],
                ),
            ];
          }

          final days = <PopulatedDay>[];
          for (var d = 0; d < nDays; d++) {
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
          final stats = SessionSetAllocator.debugLastStats!;
          if (stats.values.any((s) => s.timeForcedFirst + s.capForcedFirst > 0)) continue;

          final weeks = PeriodizationEngine.apply(
            populated: out,
            phase: lighter ? 4 : 1,
            is6Day: is6,
            effectiveExp: level,
            budget: ctx,
          );
          checked++;
          for (var w = 0; w < 4; w++) {
            final ledger = BudgetLedger(ctx, nDays);
            for (var d = 0; d < nDays; d++) {
              for (final e in weeks[w].workoutDays[d].exercises) {
                ledger.add(
                  d,
                  BudgetMuscleGroups.of(e.primaryMuscles ?? const []),
                  e.sets,
                  SessionBudget.exerciseSeconds(
                    archetype: ctx.archetypeByName[e.exerciseName.toLowerCase()]!,
                    sets: e.sets,
                    restSeconds: e.restSeconds,
                  ),
                );
              }
              expect(ledger.secondsLeft(d), greaterThanOrEqualTo(-1e-6),
                  reason: 'plan $plan week $w day $d time');
            }
            for (final g in BudgetMuscleGroups.groups) {
              expect(ledger.week(g), lessThanOrEqualTo(ledger.weeklyTop(g)),
                  reason: 'plan $plan week $w $g weekly');
              for (var d = 0; d < nDays; d++) {
                expect(ledger.session(d, g), lessThanOrEqualTo(ledger.cap(g)),
                    reason: 'plan $plan week $w day $d $g session');
              }
            }
          }
        }
        expect(checked, greaterThan(40), reason: 'the guard must not skip most plans');
      });
    });
  });

  group('VolumeTitration.applyToWeeks with a budget (Ruling 10)', () {
    /// A week of [lists] and the context for it (hypertrophy days, 90 minutes).
    (WeekPlan, SessionBudgetContext) setup(Fx f, List<List<PlannedExercise>> lists,
        {String character = 'baseline'}) {
      final days = [for (final l in lists) f.day('hypertrophy', l)];
      return (weekOf(lists, character: character), f.ctx(days, minutes: 90));
    }

    Fx chestRows() {
      final f = Fx();
      for (final n in ['c1', 'c2', 'c3', 'c4']) {
        f.row(n, ['Chest']);
      }
      return f;
    }

    test('never pushes a group past its weekly top: 16 stays 16 (the unbudgeted clamp is 20)', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 4), f.ex('c2', sets: 4)],
        [f.ex('c3', sets: 4), f.ex('c4', sets: 4)],
      ]);
      final on = VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx);
      expect(grid(on.single), [[4, 4], [4, 4]]);
      final off = VolumeTitration.applyToWeeks([week], {'Chest': 1});
      expect(grid(off.single), [[5, 4], [4, 4]]);
    });

    test('never pushes a group past a session cap: the bump rolls to the day with room', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 4), f.ex('c2', sets: 4)], // day 0 already holds 8 Chest sets
        [f.ex('c3', sets: 3), f.ex('c4', sets: 3)],
      ]);
      final on = VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx);
      expect(grid(on.single), [[4, 4], [4, 3]]);
      final off = VolumeTitration.applyToWeeks([week], {'Chest': 1});
      expect(grid(off.single), [[5, 4], [3, 3]]);
    });

    test('a plateau +1 with every candidate at its cap changes nothing', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 4), f.ex('c2', sets: 4)],
      ]);
      final on = VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx);
      expect(grid(on.single), [[4, 4]]);
    });

    test('the trim stops at the band bottom (12), not at 8', () {
      final f = chestRows();
      List<List<PlannedExercise>> lists(int third) => [
            [f.ex('c1', sets: 4), f.ex('c2', sets: 4)],
            [f.ex('c3', sets: third)],
          ];
      final (atBottom, ctx) = setup(f, lists(4)); // 12
      expect(grid(VolumeTitration.applyToWeeks([atBottom], {'Chest': -1}, budget: ctx).single),
          [[4, 4], [4]]);
      expect(grid(VolumeTitration.applyToWeeks([atBottom], {'Chest': -1}).single),
          [[3, 4], [4]]);
      final (above, ctx2) = setup(f, lists(5)); // 13
      expect(grid(VolumeTitration.applyToWeeks([above], {'Chest': -1}, budget: ctx2).single),
          [[3, 4], [5]]);
    });

    test('a trim may not take a co-group the exercise also credits below its band bottom', () {
      // Quads 13 (above the bottom of 12), Glutes exactly 12. The squat credits both,
      // so trimming it would leave Glutes at 11: the trim rolls to the leg press.
      final f = Fx();
      f.row('sq', ['Quads', 'Glutes']);
      for (final n in ['lp', 'lp2']) {
        f.row(n, ['Quads']);
      }
      for (final n in ['ht', 'ht2']) {
        f.row(n, ['Glutes']);
      }
      final (week, ctx) = setup(f, [
        [f.ex('sq', sets: 4)],
        [f.ex('lp', sets: 5), f.ex('lp2', sets: 4)],
        [f.ex('ht', sets: 4), f.ex('ht2', sets: 4)],
      ]);
      final on = VolumeTitration.applyToWeeks([week], {'Quads': -1}, budget: ctx);
      expect(grid(on.single), [[4], [4, 4], [4, 4]]);
      final off = VolumeTitration.applyToWeeks([week], {'Quads': -1});
      expect(grid(off.single), [[3], [5, 4], [4, 4]]);
    });

    test('a deload week with no stash is left alone', () {
      final f = chestRows();
      final (week, ctx) = setup(
        f,
        [
          [f.ex('c1', sets: 2), f.ex('c2', sets: 2)],
        ],
        character: 'deload',
      );
      final out = VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx).single;
      expect(workingGrid(out), [[-1, -1]]);
      expect(grid(out), [[2, 2]]);
    });

    test('a +1 skips an exercise already at 5 sets and rolls to the next', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 5), f.ex('c2', sets: 2)], // 7 of the 8-set session cap
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx).single),
          [[5, 3]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}).single), [[6, 2]]);
    });

    test('a trim skips an exercise already at 1 set and rolls to the next', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 1), f.ex('c2', sets: 5)],
        [f.ex('c3', sets: 5), f.ex('c4', sets: 5)], // 16 in all, 4 above the bottom
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': -1}, budget: ctx).single),
          [[1, 4], [5, 5]]);
    });

    test('one exercise is adjusted at most once a week, even when two groups ask', () {
      // The squat credits Quads and Glutes. Glutes (asked first, sorted order) takes
      // it; Quads then has no un-adjusted candidate left, so nothing else moves.
      final f = Fx();
      f.row('sq', ['Quads', 'Glutes']);
      f.row('ht', ['Glutes']);
      final (week, ctx) = setup(f, [
        [f.ex('sq', sets: 3)],
        [f.ex('ht', sets: 3)],
      ]);
      final on = VolumeTitration.applyToWeeks([week], {'Glutes': 1, 'Quads': 1}, budget: ctx);
      expect(grid(on.single), [[4], [3]]);
    });

    test('an exercise with no library row is not budgeted even when it has no custom stamp', () {
      final f = chestRows();
      const ghost = PlannedExercise(
        exerciseId: 'ghost',
        exerciseName: 'ghost',
        loggingType: 'weight_reps',
        sets: 3,
        reps: '10',
        restSeconds: 75,
        primaryMuscles: ['Chest'],
      );
      final (week, ctx) = setup(f, [
        [ghost, f.ex('c2', sets: 3)],
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx).single),
          [[3, 4]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}).single), [[4, 3]]);
    });

    test('Lateral Delts count as Shoulders under a budget, and not without one', () {
      final f = Fx();
      f.row('lr', ['Lateral Delts'], type: 'isolation', reps: '12-15');
      final (week, ctx) = setup(f, [
        [f.ex('lr', sets: 3)],
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Shoulders': 1}, budget: ctx).single),
          [[4]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Shoulders': 1}).single), [[3]]);
    });

    test('a Forearms delta is skipped under a budget', () {
      final f = Fx();
      f.row('wc', ['Forearms'], type: 'isolation', reps: '12-15');
      final (week, ctx) = setup(f, [
        [f.ex('wc', sets: 3)],
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Forearms': 1}, budget: ctx).single),
          [[3]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Forearms': 1}).single), [[4]]);
    });

    test('only budgeted rows are candidates: a repeat-pinned custom is left alone', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 3, customOrigin: 'repeat_pin'), f.ex('c2', sets: 3)],
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx).single),
          [[3, 4]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}).single), [[4, 3]]);
    });

    test('the deload week is checked against its stashed workingSets', () {
      final f = chestRows();
      PlannedExercise deload(String n, int working) =>
          f.ex(n, sets: 2).copyWith(workingSets: working);
      final (full, ctx) = setup(
        f,
        [
          [deload('c1', 4), deload('c2', 4)],
          [deload('c3', 4), deload('c4', 4)], // 16 working sets: at the top
        ],
        character: 'deload',
      );
      final refused = VolumeTitration.applyToWeeks([full], {'Chest': 1}, budget: ctx).single;
      expect(workingGrid(refused), [[4, 4], [4, 4]]);
      expect(grid(refused), [[2, 2], [2, 2]]);

      final (room, ctx2) = setup(
        f,
        [
          [deload('c1', 4), deload('c2', 4)],
          [deload('c3', 4), deload('c4', 2)], // 14: room, but day 0 holds 8 (its cap)
        ],
        character: 'deload',
      );
      final bumped = VolumeTitration.applyToWeeks([room], {'Chest': 1}, budget: ctx2).single;
      expect(workingGrid(bumped), [[4, 4], [5, 2]]);
      expect(grid(bumped), [[2, 2], [2, 2]]);
    });

    // ── B-pass R2 P3-1 / P3-3: fixtures that isolate each clause ─────────────

    Fx sixChestRows() {
      final f = chestRows();
      for (final n in ['c5', 'c6']) {
        f.row(n, ['Chest']);
      }
      return f;
    }

    test('the WEEKLY top alone refuses a +1: Chest 6 + 6 + 4 = 16, every day under its session cap', () {
      // No day holds 8 (the session cap), so the weekly top of 16 is the only clause
      // that can say no. The unbudgeted clamp is 20, so without a budget it bumps.
      final f = sixChestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 3), f.ex('c2', sets: 3)],
        [f.ex('c3', sets: 3), f.ex('c4', sets: 3)],
        [f.ex('c5', sets: 2), f.ex('c6', sets: 2)],
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: ctx).single),
          [[3, 3], [3, 3], [2, 2]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}).single),
          [[4, 3], [3, 3], [2, 2]]);
      // One set under the top, the same fixture bumps: the top really is the clause.
      final (room, ctx2) = setup(f, [
        [f.ex('c1', sets: 3), f.ex('c2', sets: 3)],
        [f.ex('c3', sets: 3), f.ex('c4', sets: 3)],
        [f.ex('c5', sets: 2), f.ex('c6', sets: 1)],
      ]);
      expect(grid(VolumeTitration.applyToWeeks([room], {'Chest': 1}, budget: ctx2).single),
          [[4, 3], [3, 3], [2, 1]]);
    });

    test('the DAY\'S TIME alone refuses a +1 (a group with room everywhere)', () {
      // 30 minutes = 1440 s. The bench costs 414 s at 3 sets and 546 s at 4; the 5-set
      // timed hold costs 924 s, leaving 102 s: not the 132 s the 4th set needs. Chest
      // has 3 of its 16 weekly and 3 of its 8 per session, so only the clock refuses.
      final f = Fx();
      f.row('bench', ['Chest']);
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      List<List<PlannedExercise>> lists() => [
            [f.ex('bench', sets: 3), f.ex('plank', sets: 5, logging: 'timed', rest: 135)],
          ];
      final days = [f.day('hypertrophy', lists().single)];
      final week = weekOf(lists());
      final tight = f.ctx(days, minutes: 30);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: tight).single),
          [[3, 5]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}).single), [[4, 5]]);
      // The same week on a 90-minute day has the time: the clock was the clause.
      final roomy = f.ctx(days, minutes: 90);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 1}, budget: roomy).single),
          [[4, 5]]);
    });

    test('a trim on the DELOAD week takes a stashed working set, never a shown one, and stops at the bottom', () {
      final f = chestRows();
      PlannedExercise deload(String n, int working) =>
          f.ex(n, sets: 2).copyWith(workingSets: working);
      final (above, ctx) = setup(
        f,
        [
          [deload('c1', 4), deload('c2', 4)],
          [deload('c3', 5)], // 13 working sets: one above the band bottom of 12
        ],
        character: 'deload',
      );
      final trimmed = VolumeTitration.applyToWeeks([above], {'Chest': -1}, budget: ctx).single;
      expect(workingGrid(trimmed), [[3, 4], [5]]);
      expect(grid(trimmed), [[2, 2], [2]]); // the visible deload sets do not move
      final (atBottom, ctx2) = setup(
        f,
        [
          [deload('c1', 4), deload('c2', 4)],
          [deload('c3', 4)], // 12: exactly the bottom
        ],
        character: 'deload',
      );
      final held = VolumeTitration.applyToWeeks([atBottom], {'Chest': -1}, budget: ctx2).single;
      expect(workingGrid(held), [[4, 4], [4]]);
    });

    test('a delta of 0 changes nothing, with or without a budget', () {
      final f = chestRows();
      final (week, ctx) = setup(f, [
        [f.ex('c1', sets: 4), f.ex('c2', sets: 4)],
        [f.ex('c3', sets: 5)], // 13 sets: a trim WOULD be allowed here
      ]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 0}, budget: ctx).single),
          [[4, 4], [5]]);
      expect(grid(VolumeTitration.applyToWeeks([week], {'Chest': 0}).single), [[4, 4], [5]]);
    });

    test('a zero delta does not use up an exercise another group wants (B-pass R2 P3-1)', () {
      // X credits Chest and Triceps. Chest asks for nothing; Triceps asks for +1 and X is
      // its first candidate. Were the zero treated as a trim, X would count as adjusted
      // and the Triceps +1 would land on the next exercise instead.
      final f = Fx()
        ..row('x', ['Chest', 'Triceps'])
        ..row('b', ['Triceps'])
        ..row('c1', ['Chest'])
        ..row('c2', ['Chest'])
        ..row('c3', ['Chest'])
        ..row('d', ['Triceps'])
        ..row('e', ['Triceps']);
      final (week, ctx) = setup(f, [
        [f.ex('x', sets: 3), f.ex('b', sets: 4)],
        [f.ex('c1', sets: 4), f.ex('c2', sets: 4)],
        [f.ex('c3', sets: 3), f.ex('d', sets: 5), f.ex('e', sets: 1)],
      ]); // Chest 14, Triceps 13: both above the band bottom of 12
      final out = VolumeTitration.applyToWeeks([week], {'Chest': 0, 'Triceps': 1}, budget: ctx);
      expect(grid(out.single), [
        [4, 4],
        [4, 4],
        [3, 5, 1],
      ]);
    });

    test('a delta of +2 or -3 moves ONE exercise by ONE set (B-pass R2 P3-1)', () {
      final f = chestRows();
      final (up, ctxUp) = setup(f, [
        [f.ex('c1', sets: 3), f.ex('c2', sets: 3)],
        [f.ex('c3', sets: 3), f.ex('c4', sets: 3)],
      ]); // 12: room to grow
      expect(grid(VolumeTitration.applyToWeeks([up], {'Chest': 2}, budget: ctxUp).single),
          [[4, 3], [3, 3]]);
      final (down, ctxDown) = setup(f, [
        [f.ex('c1', sets: 4), f.ex('c2', sets: 4)],
        [f.ex('c3', sets: 5)],
      ]); // 13: one set above the bottom
      expect(grid(VolumeTitration.applyToWeeks([down], {'Chest': -3}, budget: ctxDown).single),
          [[3, 4], [5]]);
    });
  });

  group('WarmupCooldownSelector.attach with a budget (Ruling 3)', () {
    test('the cardio lead-in and the cool-down walk scale with minutes; nothing else moves', () {
      final f = Fx();
      f.row('bench', ['Chest']);
      final lists = [
        [f.ex('bench')],
      ];
      final days = [f.day('hypertrophy', lists.single)];
      final week = weekOf(lists);
      final off = WarmupCooldownSelector.attach([week], 'intermediate', const ['dumbbells'])
          .single
          .workoutDays
          .single;
      expect(off.warmup.first.reps, '300s');
      expect(off.cooldown.first.reps, '300s');
      // 50 min is off the 15-minute grid: 6 + 20 x 2/15 = 8.667, so 140 s (a floor
      // would give 139). Outside 30..90 minutes the length clamps at 6 and 14.
      for (final (minutes, seconds) in [
        (20, 60), (30, 60), (45, 120), (50, 140), (60, 180), (75, 240), (90, 300), (120, 300),
      ]) {
        final on = WarmupCooldownSelector.attach(
          [week],
          'intermediate',
          const ['dumbbells'],
          budget: f.ctx(days, minutes: minutes),
        ).single.workoutDays.single;
        expect(on.warmup.first.reps, '${seconds}s', reason: 'lead-in at $minutes min');
        expect(on.cooldown.first.reps, '${seconds}s', reason: 'walk at $minutes min');
        expect([for (final e in on.warmup.skip(1)) e.toMap()],
            [for (final e in off.warmup.skip(1)) e.toMap()]);
        expect([for (final e in on.cooldown.skip(1)) e.toMap()],
            [for (final e in off.cooldown.skip(1)) e.toMap()]);
        expect(on.warmup.first.exerciseName, off.warmup.first.exerciseName);
        expect(on.cooldown.first.exerciseName, off.cooldown.first.exerciseName);
      }
    });
  });

  group('VolumeFilter.filterDays keepAllSlots', () {
    test('returns every split slot, where the default keeps targetCount', () {
      final slots = [
        for (var i = 0; i < 10; i++)
          MuscleSlot(
            targetMuscle: 'Chest',
            movementPattern: 'horizontal_push',
            exerciseType: 'compound',
            priority: 1 + i % 3,
          ),
      ];
      final days = [
        for (var d = 0; d < 5; d++)
          MuscleSlotDay(
            name: 'D$d',
            focus: 'F',
            dayType: 'push',
            intensity: 'hypertrophy',
            slotsA: slots,
            slotsB: slots.take(9).toList(),
          ),
      ];
      // intermediate, 5 days: targetCount = 6.
      final trimmed = VolumeFilter.filterDays(days, experience: 'intermediate', weekCharacter: 'baseline');
      expect(trimmed.first.slotsA.length, 6);
      expect(trimmed.first.slotsB!.length, 6);
      final all = VolumeFilter.filterDays(days,
          experience: 'intermediate', weekCharacter: 'baseline', keepAllSlots: true);
      expect(all.first.slotsA.length, 10);
      expect(all.first.slotsB!.length, 9);
      expect(all.length, 5);
      // The deload rule is not a count: it still keeps priority-1 slots only.
      final deload = VolumeFilter.filterDays(days,
          experience: 'intermediate', weekCharacter: 'deload', keepAllSlots: true);
      expect(deload.first.slotsA.length, slots.where((s) => s.priority == 1).length);
      expect(deload.first.slotsA.every((s) => s.priority == 1), isTrue);
    });
  });
}
