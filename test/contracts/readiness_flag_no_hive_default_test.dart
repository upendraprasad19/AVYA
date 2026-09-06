// Covers the CATCH-BLOCK half of both flag getters — the half with no other
// coverage, because every other readiness/deload test opens a config box in
// setUp. Deliberately does NOT initialise Hive: HiveService.getBox throws
// StateError when uninitialised, which is what makes the catch branch run.
//
// Precedent for a no-Hive context in this suite:
// test/plan_generator/generator_matrix.dart ("PlanEngineFlags reads Hive and
// this harness runs without it").
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  test('readinessEnabled defaults TRUE when Hive is unavailable', () {
    expect(PlanEngineFlags.readinessEnabled, isTrue);
  });

  test('triggeredDeloadEnabled defaults TRUE when Hive is unavailable', () {
    expect(PlanEngineFlags.triggeredDeloadEnabled, isTrue);
  });

  // Added with the 2026-09-05 phase-arc flip. The flip inverts BOTH halves of
  // the getter — the key (`enable_` → `disable_`) and the catch-block default
  // (`false` → `true`). Flipping only the key would leave a no-Hive context
  // rendering nothing while a Hive context renders the strip, which is the
  // fallback silently contradicting the flag.
  test('phaseArcEnabled defaults TRUE when Hive is unavailable', () {
    expect(PlanEngineFlags.phaseArcEnabled, isTrue);
  });

  // Flipped 2026-09-06 by Unit B (OI-53 flag 4), on the same rule as the
  // phase-arc case above: the flip inverts BOTH halves of the getter, the key
  // (`enable_` → `disable_`) and the catch-block default (`false` → `true`).
  //
  // This test EARNED its keep. The Unit B flip changed the key and its Hive-
  // present sibling in `phase_arc_reader_behavioral_test.dart` and missed this
  // one; the pin caught it at review, before the push. A getter has two halves
  // and they live in two files → change one, grep for the other.
  test('deloadReasonLineEnabled defaults TRUE when Hive is unavailable', () {
    expect(PlanEngineFlags.deloadReasonLineEnabled, isTrue);
  });
}
