// Unit 1B-F, Task 1 (docs/plans/2026-11-10-generator-1bf-flip.md, Ruling 5): OI-489's "Done when" on the real
// engine and the real library. At 30 minutes the allocator used to spend the day's library timed rows first, so a
// later compound that would give the week its first Chest (or Hamstrings) credit was dropped for time alone. With
// Ruling 5 a timed hold ranked after it gives way. Each key is `goal|days|level|tier|minutes|phase`.
//
// Mutated per rule 21: on main's allocator (no eviction) every expectation below is red; with guard (e) reverted to
// prototype H2 (`!bringsMajor` dropped) only the focus pin is red.
//
// Ruling 5c (found in Task 2 by session_set_budget_gate_test once every goal ran on the core-list pool): the empty-day
// guard's forced lead may take a later hold's time. `lose_fat` / `general_fitness|4|advanced|bodyweight|30|1`: the Upper
// Pull day held four holds and Sliding Lat Pull in 32.6 minutes (main's allocator gives the same day); with 5c,
// Single Arm Isometric Lat Pull gives way and the day is 29.6 minutes. Mutated: the guard's call removed, red.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';

import '../helpers/injury_floor_sweep_lib.dart';

/// Sets credited to [group] in each week of [phase] (weeks 1-4), by each exercise's own primary muscles.
List<int> weeklySets(Phase phase, String group) => [
      for (final w in phase.weekPlans)
        w.workoutDays
            .expand((d) => d.exercises)
            .where((e) => BudgetMuscleGroups.creditedOf([for (final m in e.primaryMuscles ?? const []) '$m'],
                    quadPrimaryCreditsGlutes: true)
                .contains(group))
            .fold(0, (a, e) => a + e.sets),
    ];

Phase gen(String goal, int phase, {List<String> focus = const [], int days = 3}) => PlanGenerator.instance.generateV4(
      goal: goal,
      equipment: 'bodyweight',
      daysPerWeek: days,
      phase: phase,
      experienceLevel: 'advanced',
      injuries: const [],
      bodyFocus: focus,
      sessionDuration: 30,
      previousWeights: const {},
    );

void main() {
  SweepHarness.install();

  for (final phase in const [2, 3]) {
    test('build_muscle|3|advanced|bodyweight|30|$phase holds Chest sets in weeks 2 and 4', () {
      final chest = weeklySets(gen('build_muscle', phase), 'Chest');
      expect(chest[1], greaterThan(0), reason: 'week 2: $chest');
      expect(chest[3], greaterThan(0), reason: 'week 4: $chest');
    });
  }

  for (final goal in const ['lose_fat', 'general_fitness']) {
    test('$goal|3|advanced|bodyweight|30|1 holds Hamstrings sets in weeks 1-4', () {
      final ham = weeklySets(gen(goal, 1), 'Hamstrings');
      for (var w = 0; w < 4; w++) {
        expect(ham[w], greaterThan(0), reason: 'week ${w + 1}: $ham');
      }
    });
  }

  test('focus pin: build_muscle|3|advanced|bodyweight|30|2 with body focus Core holds Chest sets in weeks 2 and 4', () {
    final chest = weeklySets(gen('build_muscle', 2, focus: const ['core']), 'Chest');
    expect(chest[1], greaterThan(0), reason: 'week 2: $chest');
    expect(chest[3], greaterThan(0), reason: 'week 4: $chest');
  });

  for (final goal in const ['lose_fat', 'general_fitness']) {
    test('Ruling 5c: $goal|4|advanced|bodyweight|30|1 keeps every day of weeks 1-4 inside 30 + 2 minutes', () {
      final rowsById = {
        for (final r in (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
            .cast<Map<String, dynamic>>())
          r['id'] as String: r,
      };
      final p = gen(goal, 1, days: 4);
      for (final w in p.weekPlans) {
        for (final d in w.workoutDays) {
          final minutes = SessionBudget.estimateDaySecondsFromPlanDay(d.toMap(), rowsById) / 60;
          expect(minutes, lessThanOrEqualTo(32), reason: 'week ${w.weekNumber} ${d.name}: ${minutes.toStringAsFixed(1)}');
        }
      }
    });
  }
}
