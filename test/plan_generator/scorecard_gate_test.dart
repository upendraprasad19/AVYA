// Batch 0 · D4 — Hard-invariant + no-regression gate (flutter test).
//
// This is the regression test the `feature`-tier harness requires. It has two
// kinds of assertion:
//
//  HARD (must always be exactly 0 — the engine's real guarantees today):
//    • no missing/(none) picks anywhere in the full matrix
//    • full_gym personas (top tier) have 0 equipment-tier violations
//
//  NO-REGRESSION (≤ the frozen baseline — the engine's known CURRENT gaps,
//  recorded honestly, NOT silently passed; the owning batches drive them down):
//    • unsafe plans (universal-pool bypasses the injury filter) — Batch 1 fixes
//    • equipment over-tier picks (attempt-4 drops equipment) — Batch 5 fixes
//    • target-fidelity fallbacks (shallow bodyweight pool) — Batch 5/3.4
//    • mean overall score must not drop
//
// Run: `flutter test test/plan_generator/scorecard_gate_test.dart`
// Regenerate the baseline after an intended engine change:
//   `dart run test/plan_generator/generate_baseline.dart` (review the diff).

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'generator_matrix.dart';
import 'plan_scorecard.dart';

void main() {
  final plans = generateAll();
  final scores = scoreAll(plans);

  // ---- current aggregate ----
  var missing = 0;
  var totalFallback = 0;
  var unsafe = 0;
  var equipViolators = 0;
  var fullGymEquipViolations = 0;
  var overallSum = 0.0;
  for (final plan in plans) {
    final sc = scores[plan.persona]!;
    overallSum += sc.overall;
    if (!sc.isSafe) unsafe++;
    final equipViol = sc.violations.where((v) => v.startsWith('EQUIPMENT')).toList();
    if (equipViol.isNotEmpty) equipViolators++;
    if (plan.persona.equipment == 'full_gym') {
      fullGymEquipViolations += equipViol.length;
    }
    for (final ex in plan.allExercises) {
      if (ex.isMissing) missing++;
      if (ex.isFallback) totalFallback++;
    }
  }
  final meanOverall = overallSum / plans.length;

  // ---- frozen baseline ----
  final baselineFile = File('test/plan_generator/baseline/baseline_scorecard.json');
  final decoded = json.decode(baselineFile.readAsStringSync()) as Map;
  final baseline = decoded['aggregate'] as Map;
  final bUnsafe = baseline['unsafe_plan_count'] as int;
  final bEquip = baseline['equipment_violation_plan_count'] as int;
  final bFallback = baseline['total_fallback_picks'] as int;
  final bMeanScores = baseline['mean_scores'] as Map;
  final bOverall = double.parse('${bMeanScores['overall']}');

  group('Batch 0 · HARD invariants (must be exactly 0)', () {
    test('baseline golden file exists (run generate_baseline.dart first)', () {
      expect(baselineFile.existsSync(), isTrue,
          reason: 'Freeze the baseline before gating against it.');
    });

    test('no missing/(none) picks anywhere in the ${plans.length}-persona matrix', () {
      expect(missing, 0,
          reason: 'Every slot must resolve to a real exercise; a (none) pick is a hard failure.');
    });

    test('full_gym personas have 0 equipment-tier violations', () {
      expect(fullGymEquipViolations, 0,
          reason: 'The top equipment tier can never be handed an exercise above it.');
    });

    test('EVERY tier has 0 equipment violations (⑦ OI-89)', () {
      // PROMOTED from a <=201 no-regression ceiling to a hard 0 on 2026-08-28.
      // The baseline froze 201 violating plans with the standing note "Batch 5
      // must drive this down"; OI-89 is that work and the measured result is 0
      // at all four tiers. A soft ceiling that has been met is no longer a
      // ceiling -- it is a licence to give 200 of them back.
      expect(equipViolators, 0,
          reason: 'A user must never be prescribed an exercise they cannot '
              'perform. This is the whole of OI-89 and it is not a budget.');
    });
  });

  group('Batch 0 · NO-REGRESSION vs frozen baseline', () {
    test('unsafe plans ≤ baseline ($bUnsafe) [Batch 1 must drive this to 0]', () {
      expect(unsafe, lessThanOrEqualTo(bUnsafe),
          reason: 'A new contraindicated-exercise plan is a regression. '
              'Baseline=$bUnsafe (universal-pool bypasses the injury filter — Batch 1 fixes).');
    });

    test('equipment over-tier plans ≤ baseline ($bEquip)', () {
      // Kept as a no-regression floor beneath the hard 0 above: if a later batch
      // relaxes the hard gate, this still catches a slide back toward 201.
      expect(equipViolators, lessThanOrEqualTo(bEquip),
          reason: 'More over-tier picks is a regression. Baseline=$bEquip.');
    });

    test('total fallback picks ≤ baseline ($bFallback)', () {
      // ⚠ RE-BASELINED 2026-08-28 (OI-89), 1184 -> 2719, and the reason must
      // travel with the number or the next reader sees only a loosened gate.
      //
      // The old 1184 was frozen against a library that LIED about what its
      // exercises need: the generator satisfied attempt 1/2 with exercises the
      // user could not physically do, which scores as high target fidelity and
      // is worthless. With the equipment data corrected and the capability floor
      // ON, those picks are refused and the cascade relaxes instead -- so
      // fidelity drops and the fallback count rises. That is the trade, stated
      // plainly: 201 equipment-violating plans -> 0, at the cost of more generic
      // but PERFORMABLE picks.
      //
      // This is not "re-freezing a risen number and calling it the floor". The
      // evidence that it is a real improvement is the hard 0 gate above, which
      // did not exist before and which no amount of fallback tolerance can
      // satisfy. If this number rises again with equipment violations still at
      // 0, THAT is a genuine quality regression and this gate is what catches it.
      expect(totalFallback, lessThanOrEqualTo(bFallback),
          reason: 'More target-fidelity fallbacks is a regression. '
              'Baseline=$bFallback.');
    });

    // ⚠ meanOverall was ALSO re-baselined 2026-08-28, 87.00 -> 86.35, for the
    // same reason and with the same justification as total_fallback_picks above:
    // the composite includes a target-fidelity term, and fidelity measured
    // against undoable exercises was never real.
    test('mean overall score does not regress (baseline ${bOverall.toStringAsFixed(1)})', () {
      expect(meanOverall, greaterThanOrEqualTo(bOverall - 0.05),
          reason: 'Overall plan quality must not drop. '
              'current=${meanOverall.toStringAsFixed(2)} baseline=${bOverall.toStringAsFixed(2)}');
    });
  });
}
