// OI-454: `SessionBudgetContext.quadPrimaryCreditsGlutes` reaches all three consumers that build a
// `BudgetLedger` credit set: the allocator, `PeriodizationEngine.apply` (week 2) and
// `VolumeTitration.applyToWeeks`. Pure Dart over crafted rows (no Hive): each test differs ONLY in the
// flag, so a consumer that stops passing it reddens exactly one test.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

import '../helpers/session_budget_fixtures.dart';

SessionBudgetContext ctxFor(Fx f, {required bool credits, int minutes = 90}) => SessionBudgetContext(
      minutes: minutes,
      planGoal: 'build_muscle',
      level: 'intermediate', // weekly band 12 to 16, session cap 8
      lighterPhase: false,
      focusGroups: const {},
      quadPrimaryCreditsGlutes: credits,
      archetypeByName: {for (final e in f.rows.entries) e.key: SessionBudget.archetypeOfRow(e.value)},
    );

List<List<int>> setsGrid(Iterable<List<PlannedExercise>> days) => [
      for (final d in days) [for (final e in d) e.sets],
    ];

void main() {
  /// Six days, each a glute isolation row and a squat that lists Quads then Glutes.
  (Fx, List<PopulatedDay>) sixDays() {
    final f = Fx();
    for (var i = 0; i < 6; i++) {
      f.row('g$i', ['Glutes'], type: 'isolation', reps: '10-15');
      f.row('sq$i', ['Quads', 'Glutes']);
    }
    return (
      f,
      [for (var i = 0; i < 6; i++) f.day('hypertrophy', [f.ex('g$i', sets: 3), f.ex('sq$i', sets: 3)])],
    );
  }

  test('allocator: with the rule the squats are not refused for Glutes; without it they are', () {
    // Unit 2B: the day floor is off here, so the two runs differ ONLY in the credit flag; the floor's own effect on
    // this fixture is pinned in the next test.
    final (f, days) = sixDays();
    final off = SessionSetAllocator.allocate(
        days: days, ctx: ctxFor(f, credits: true), rowsByName: f.rows, is6Day: true, dayFloor: false);
    final offStats = SessionSetAllocator.debugLastStats!['A']!;
    final on = SessionSetAllocator.allocate(
        days: days, ctx: ctxFor(f, credits: false), rowsByName: f.rows, is6Day: true, dayFloor: false);
    final onStats = SessionSetAllocator.debugLastStats!['A']!;

    expect(setsGrid(off.map((d) => d.exercisesA)), [[2, 2], [2, 2], [2], [2], [2], [2]]);
    expect(offStats.weekly, {'Quads': 4, 'Glutes': 16}, reason: 'Glutes at its top refuses the squats');
    expect(setsGrid(on.map((d) => d.exercisesA)), [[3, 3], [3, 3], [3, 3], [3, 3], [2, 2], [2, 2]]);
    expect(onStats.weekly, {'Quads': 16, 'Glutes': 16}, reason: 'the squats credit Quads only');
  });

  test('allocator with the Unit 2B day floor (d32): the full-credit days handed two slots are floored to two', () {
    // Full credit: days 2-5 keep only their glute row (Glutes at its top), each reach 2, so the floor seats the squat
    // at 2 past the Glutes top: Glutes 16 + 4 x 2 = 24, Quads 4 + 8 = 12. Under the rule nothing is thin.
    final (f, days) = sixDays();
    final off = SessionSetAllocator.allocate(
        days: days, ctx: ctxFor(f, credits: true), rowsByName: f.rows, is6Day: true, dayFloor: true);
    final offStats = SessionSetAllocator.debugLastStats!['A']!;
    expect(setsGrid(off.map((d) => d.exercisesA)), [[2, 2], [2, 2], [2, 2], [2, 2], [2, 2], [2, 2]]);
    expect(offStats.weekly, {'Quads': 12, 'Glutes': 24});
    expect([for (final d in [2, 3, 4, 5]) offStats.floorSeats[d]!.single.overTop], [
      for (var i = 0; i < 4; i++) ['Glutes'],
    ]);
    final on = SessionSetAllocator.allocate(
        days: days, ctx: ctxFor(f, credits: false), rowsByName: f.rows, is6Day: true, dayFloor: true);
    expect(setsGrid(on.map((d) => d.exercisesA)), [[3, 3], [3, 3], [3, 3], [3, 3], [2, 2], [2, 2]]);
    expect(SessionSetAllocator.debugLastStats!['A']!.floorSeats, isEmpty);
  });

  test('allocator: a quad-first row that also lists Hamstrings (Trap Bar Deadlift) keeps its Glutes credit under the rule', () {
    final f = Fx();
    f.row('tb', ['Quads', 'Glutes', 'Lower Back', 'Hamstrings']);
    f.row('sq', ['Quads', 'Glutes']);
    int glutesOf(String name) {
      final days = [f.day('hypertrophy', [f.ex(name, sets: 3)])];
      final out = SessionSetAllocator.allocate(
          days: days, ctx: ctxFor(f, credits: false), rowsByName: f.rows, is6Day: true);
      final stats = SessionSetAllocator.debugLastStats!['A']!;
      expect(out.single.exercisesA.single.sets, greaterThanOrEqualTo(2), reason: name);
      return stats.weekly['Glutes'] ?? 0;
    }

    expect(glutesOf('sq'), 0, reason: 'a squat does not credit Glutes under the rule');
    expect(glutesOf('tb'), greaterThanOrEqualTo(2), reason: 'the hip hinge keeps its Glutes credit');
  });

  test('PeriodizationEngine.apply week 2: the same allocation gains sets only under the rule', () {
    final (f, days) = sixDays();
    // The allocation the OLD credit produced (Quads starved), then the week-2 gains priced both ways.
    // The day floor off (Unit 2B): this test reads week 2 over the pre-2B allocation, which leaves days 2-5 thin.
    final allocated = SessionSetAllocator.allocate(
        days: days, ctx: ctxFor(f, credits: true), rowsByName: f.rows, is6Day: true, dayFloor: false);
    List<List<int>> week2(bool credits) => [
          for (final d in PeriodizationEngine.apply(
                  populated: allocated, phase: 1, is6Day: true, budget: ctxFor(f, credits: credits))[1]
              .workoutDays)
            [for (final e in d.exercises) e.sets],
        ];
    expect(week2(true), [[2, 2], [2, 2], [2], [2], [2], [2]], reason: 'full credit: Glutes at top, no gain');
    expect(week2(false), [[3, 3], [3, 3], [3], [3], [2], [2]], reason: 'under the rule the squats gain');
  });

  test('VolumeTitration +1 for Quads: the squat is a candidate only under the rule', () {
    final f = Fx();
    f.row('sq', ['Quads', 'Glutes']);
    f.row('lp', ['Quads']);
    for (final n in ['g1', 'g2', 'g3', 'g4']) {
      f.row(n, ['Glutes'], type: 'isolation', reps: '10-15');
    }
    // Glutes 14 of a 16 top (g 4+4+3+3), the squat holds 3 (so full credit makes it 17), Quads 6.
    final lists = [
      [f.ex('sq', sets: 3), f.ex('g1', sets: 4)],
      [f.ex('lp', sets: 3), f.ex('g2', sets: 4)],
      [f.ex('g3', sets: 3)],
      [f.ex('g4', sets: 3)],
    ];
    WeekPlan week() => WeekPlan(
          weekNumber: 1,
          weekInPhase: 1,
          overloadNotes: '',
          weekCharacter: 'baseline',
          workoutDays: [
            for (var i = 0; i < lists.length; i++)
              WorkoutDay(dayNumber: i + 1, name: 'D', focus: 'F', exercises: lists[i]),
          ],
        );
    List<List<int>> titrate(bool credits) => setsGrid(VolumeTitration.applyToWeeks(
            [week()], {'Quads': 1}, budget: ctxFor(f, credits: credits))
        .single
        .workoutDays
        .map((d) => d.exercises));
    expect(titrate(true), [[3, 4], [4, 4], [3], [3]], reason: 'full credit: the squat would break the Glutes top, the leg press takes it');
    expect(titrate(false), [[4, 4], [3, 4], [3], [3]], reason: 'under the rule the squat (first candidate) takes the set');
  });
}
