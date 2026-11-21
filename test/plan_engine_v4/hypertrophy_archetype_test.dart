// Hypertrophy archetype tests for Plan Engine V4.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 (tech-debt
// audit B5 / T7 split). Test bodies are byte-identical to V3.
//
// Scope: tests that exercise the "hypertrophy" intensity profile (the
// default for `populatedDay()` and the V4 archetype for phase 1 / 5 / 9).
// Covers volume wave defaults, suggested starting weights and apply()
// structural invariants. The cycle multiplier and the body-focus +1 were deleted
// with the unbudgeted body (flip 2026-11-02); the focus now lives in the allocator.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';

import '_helpers.dart';
import '../helpers/session_budget_fixtures.dart';

void main() {
  group('PeriodizationEngine', () {
    group('Volume wave (4-week) — hypertrophy intensity', () {
      test('deload week has fewer sets than baseline', () {
        final populated = [populatedDay()];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );

        final baselineSets = weeks[0].workoutDays[0].exercises[0].sets;
        final deloadSets = weeks[3].workoutDays[0].exercises[0].sets;
        expect(deloadSets, lessThan(baselineSets),
            reason: 'Deload week should have fewer sets than baseline');
      });

      test('week characters: baseline, overreach, peak, deload', () {
        final populated = [populatedDay()];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );
        expect(weeks[0].weekCharacter, 'baseline');
        expect(weeks[1].weekCharacter, 'overreach');
        expect(weeks[2].weekCharacter, 'peak');
        expect(weeks[3].weekCharacter, 'deload');
      });
    });

    group('Suggested starting weights', () {
      test('previousWeights stamps suggestedWeight and weightCue', () {
        final populated = [
          populatedDay(exercisesA: [
            exercise(name: 'Bench Press'),
          ]),
        ];

        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 2,
          is6Day: false,
          previousWeights: {'Bench Press': 62.5},
          budget: testBudget(),
        );

        final ex = weeks[0].workoutDays[0].exercises[0];
        expect(ex.suggestedWeight, 62.5);
        expect(ex.weightCue, contains('62.5'));
        expect(ex.weightCue, contains('from last phase'));
      });

      test('exercises without previousWeights get normal weightCue', () {
        final populated = [
          populatedDay(exercisesA: [
            exercise(name: 'Cable Fly'),
          ]),
        ];

        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 2,
          is6Day: false,
          previousWeights: {'Bench Press': 62.5}, // no Cable Fly,
          budget: testBudget(),
        );

        final ex = weeks[0].workoutDays[0].exercises[0];
        expect(ex.suggestedWeight, isNull);
      });
    });

    group('apply produces correct structure', () {
      test('produces 4 WeekPlans', () {
        final populated = [populatedDay(), populatedDay(name: 'Pull')];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );
        expect(weeks.length, 4);
      });

      test('each WeekPlan has correct weekInPhase (1-4)', () {
        final populated = [populatedDay()];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );
        for (int i = 0; i < 4; i++) {
          expect(weeks[i].weekInPhase, i + 1);
        }
      });

      test('weekNumber is global (phase-aware)', () {
        final populated = [populatedDay()];

        final phase1Weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );
        expect(phase1Weeks[0].weekNumber, 1);
        expect(phase1Weeks[3].weekNumber, 4);

        final phase3Weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 3,
          is6Day: false,
          budget: testBudget(),
        );
        expect(phase3Weeks[0].weekNumber, 9);
        expect(phase3Weeks[3].weekNumber, 12);
      });

      test('each WeekPlan preserves day count from populated input', () {
        final populated = [
          populatedDay(name: 'Push'),
          populatedDay(name: 'Pull'),
          populatedDay(name: 'Legs'),
        ];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );
        for (final week in weeks) {
          expect(week.workoutDays.length, 3);
        }
      });

      test('A/B alternation in non-6-day: weeks 2,4 use variant B', () {
        final exA = exercise(name: 'Bench Press A', variant: 'A');
        final exB = exercise(name: 'Bench Press B', variant: 'B');
        final populated = [
          PopulatedDay(
            name: 'Push', focus: 'Chest', dayType: 'push', intensity: 'hypertrophy',
            exercisesA: [exA],
            exercisesB: [exB],
          ),
        ];

        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          budget: testBudget(),
        );

        // Week 1 (idx 0) → A, Week 2 (idx 1) → B, Week 3 (idx 2) → A, Week 4 (idx 3) → B
        expect(weeks[0].workoutDays[0].exercises[0].exerciseName, 'Bench Press A');
        expect(weeks[1].workoutDays[0].exercises[0].exerciseName, 'Bench Press B');
        expect(weeks[2].workoutDays[0].exercises[0].exerciseName, 'Bench Press A');
        expect(weeks[3].workoutDays[0].exercises[0].exerciseName, 'Bench Press B');
      });
    });
  });
}
