// Endurance archetype tests for Plan Engine V4.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 (tech-debt
// audit B5 / T7 split). Test bodies are byte-identical to V3.
//
// Scope: tests that exercise the "endurance" DUP intensity profile
// (V3 name; corresponds in V4 to the metabolic-archetype set-floor + 2-set
// base regime). These tests pin the 4-set-minimum behavior for
// intermediate+ on a 2-set base profile, and the explicit deload-week
// bypass of that floor.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';

import '_helpers.dart';

void main() {
  group('PeriodizationEngine', () {
    group('4-set minimum for intermediate+', () {
      test('intermediate non-deload weeks enforce 4-set minimum', () {
        final populated = [
          populatedDay(intensity: 'endurance'), // endurance base = 2 sets
        ];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          effectiveExp: 'intermediate',
        );

        // Weeks 0-2 (non-deload) should have >= 4 sets
        for (int w = 0; w < 3; w++) {
          for (final ex in weeks[w].workoutDays[0].exercises) {
            expect(ex.sets, greaterThanOrEqualTo(4),
                reason: 'Week ${w + 1} intermediate should have >= 4 sets, got ${ex.sets}');
          }
        }
      });

      test('beginner does NOT get 4-set minimum', () {
        final populated = [
          populatedDay(intensity: 'endurance'), // endurance base = 2 sets
        ];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 1,
          is6Day: false,
          effectiveExp: 'beginner',
        );

        // Beginner baseline with endurance profile should have base 2 sets
        final baselineSets = weeks[0].workoutDays[0].exercises[0].sets;
        expect(baselineSets, lessThan(4),
            reason: 'Beginner should not get 4-set minimum');
      });

      test('deload week skips 4-set minimum even for intermediate', () {
        final populated = [populatedDay(intensity: 'endurance')];
        final weeks = PeriodizationEngine.apply(
          populated: populated,
          phase: 4, // deload archetype
          is6Day: false,
          effectiveExp: 'intermediate',
        );

        // Week 4 (deload) should reduce to < 4 sets
        final deloadSets = weeks[3].workoutDays[0].exercises[0].sets;
        expect(deloadSets, lessThan(4),
            reason: 'Deload week should not enforce 4-set minimum');
      });
    });
  });
}
