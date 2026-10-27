// Strength archetype tests for Plan Engine V4.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 (tech-debt
// audit B5 / T7 split). Test bodies are byte-identical to V3 (only the
// private helper symbols were made public via `_helpers.dart`).
//
// Scope: tests that exercise the "strength" intensity profile (V3 DUP
// profile name; the V4 cycling archetype list is hypertrophy → strength
// → metabolic → deload) and the strength-goal advanced split.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';

import '_helpers.dart';

void main() {
  group('SplitResolver', () {
    group('Advanced routing — strength goal', () {
      test('advanced 4-day strength → squat/bench/deadlift/OHP days', () {
        final slots = SplitResolver.select(
          'strength', 4, experienceLevel: 'advanced',
        );
        expect(slots.length, 4);
        final names = slots.map((s) => s.name).toList();
        expect(names, contains('Squat Day'));
        expect(names, contains('Bench Day'));
        expect(names, contains('Deadlift Day'));
        expect(names, contains('OHP Day'));
      });
    });
  });

  group('PeriodizationEngine', () {
    group('Volume wave (4-week) — strength intensity', () {
      test('week 2 (overreach) has +1 set vs week 1 (baseline)', () {
        // Use strength intensity (base 4 sets) so the 4-set minimum does not
        // flatten both baseline and overreach to the same value.
        final populated = [populatedDay(intensity: 'strength')];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          effectiveExp: 'intermediate',
        );
        expect(weeks.length, 4);

        // Strength base = 4 sets; baseline = 4, overreach = 5
        final baselineSets = weeks[0].workoutDays[0].exercises[0].sets;
        final overreachSets = weeks[1].workoutDays[0].exercises[0].sets;
        expect(overreachSets, baselineSets + 1,
            reason: 'Overreach week should have +1 set vs baseline');
      });

      test('peak week has fewer reps than baseline for strength intensity', () {
        // Strength intensity has baseReps=5, peak subtracts 2 → 3
        final populated = [populatedDay(intensity: 'strength')];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
        );

        final baselineReps = weeks[0].workoutDays[0].exercises[0].reps;
        final peakReps = weeks[2].workoutDays[0].exercises[0].reps;
        expect(int.parse(peakReps), lessThan(int.parse(baselineReps)),
            reason: 'Peak week should have fewer reps for progressive loading');
      });
    });
  });
}
