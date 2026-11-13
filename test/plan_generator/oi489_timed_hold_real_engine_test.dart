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
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

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
    test('Ruling 5c: $goal|4|advanced|bodyweight|30|1 keeps every day of weeks 1-4 inside 30 + 2 minutes (a count-forced day: + 5)', () {
      final rowsById = {
        for (final r in (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
            .cast<Map<String, dynamic>>())
          r['id'] as String: r,
      };
      SessionSetAllocator.debugLastStats = null;
      final p = gen(goal, 1, days: 4);
      final stats = SessionSetAllocator.debugLastStats!;
      final forced = <String>[];
      final over = <String, double>{};
      for (final w in p.weekPlans) {
        for (var i = 0; i < w.workoutDays.length; i++) {
          final d = w.workoutDays[i];
          final minutes = SessionBudget.estimateDaySecondsFromPlanDay(d.toMap(), rowsById) / 60;
          // Unit 2A (2026-11-13): a day the count floor force-seated (pass A2, `countForced` of the variant the week
          // reads: B in weeks 2 and 4) may be up to `maxForcedOverSeconds` over, the accepted overrun (founder d26 /
          // d28): Lower Body is 32.9 minutes in weeks 1-3 (both goals) since its lead is seated at 3 (pinned below).
          // Every other day keeps 30 + 2.
          final variant = w.weekInPhase.isEven ? 'B' : 'A';
          final isForced = stats[variant]!.countForced.containsKey(i);
          if (isForced) forced.add('week ${w.weekInPhase} ${d.name}');
          if (minutes > 32) over['week ${w.weekInPhase} ${d.name}'] = (minutes * 10).roundToDouble() / 10;
          final limit = 32 + (isForced ? SessionBudget.maxForcedOverSeconds / 60 : 0);
          expect(minutes, lessThanOrEqualTo(limit), reason: 'week ${w.weekNumber} ${d.name}: ${minutes.toStringAsFixed(1)}');
        }
      }
      // The Ruling 5c day itself (Upper Pull) is never excused.
      expect(forced.where((f) => f.contains('Pull')), isEmpty, reason: 'forced: $forced');
      // The excuse is used by exactly these days, at exactly these minutes (B review, seat 2 finding 3).
      expect(over, <String, double>{'week 1 Lower Body': 32.9, 'week 2 Lower Body': 32.9, 'week 3 Lower Body': 32.9},
          reason: goal);
    });
  }
}
