// Mixed-archetype tests for Plan Engine V4.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 (tech-debt
// audit B5 / T7 split). Test bodies are byte-identical to V3.
//
// Scope: tests that span the full archetype cycle (hypertrophy → strength
// → metabolic → deload) — i.e. `archetypeForPhase` mapping assertions
// across all 12 phases. Pinned here because no single archetype owns the
// cycling contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';

void main() {
  group('PeriodizationEngine', () {
    group('archetypeForPhase', () {
      test('cycles: 1=hypertrophy, 2=strength, 3=metabolic, 4=deload', () {
        expect(PeriodizationEngine.archetypeForPhase(1), 'hypertrophy');
        expect(PeriodizationEngine.archetypeForPhase(2), 'strength');
        expect(PeriodizationEngine.archetypeForPhase(3), 'metabolic');
        expect(PeriodizationEngine.archetypeForPhase(4), 'deload');
      });

      test('phase 5 repeats: hypertrophy', () {
        expect(PeriodizationEngine.archetypeForPhase(5), 'hypertrophy');
      });

      test('phase 6 = strength, 7 = metabolic, 8 = deload', () {
        expect(PeriodizationEngine.archetypeForPhase(6), 'strength');
        expect(PeriodizationEngine.archetypeForPhase(7), 'metabolic');
        expect(PeriodizationEngine.archetypeForPhase(8), 'deload');
      });

      test('phase 9 = hypertrophy again (3rd cycle)', () {
        expect(PeriodizationEngine.archetypeForPhase(9), 'hypertrophy');
      });

      test('phase 12 = deload (end of 3rd cycle)', () {
        expect(PeriodizationEngine.archetypeForPhase(12), 'deload');
      });
    });
  });
}
