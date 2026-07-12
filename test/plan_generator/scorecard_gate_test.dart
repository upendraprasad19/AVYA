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
  });

  group('Batch 0 · NO-REGRESSION vs frozen baseline', () {
    test('unsafe plans ≤ baseline ($bUnsafe) [Batch 1 must drive this to 0]', () {
      expect(unsafe, lessThanOrEqualTo(bUnsafe),
          reason: 'A new contraindicated-exercise plan is a regression. '
              'Baseline=$bUnsafe (universal-pool bypasses the injury filter — Batch 1 fixes).');
    });

    test('equipment over-tier plans ≤ baseline ($bEquip) [Batch 5 must drive this down]', () {
      expect(equipViolators, lessThanOrEqualTo(bEquip),
          reason: 'More over-tier picks is a regression. '
              'Baseline=$bEquip (attempt-4 drops equipment — Batch 5 fixes).');
    });

    test('total fallback picks ≤ baseline ($bFallback) [Batch 5/W3.4 must drive this down]', () {
      expect(totalFallback, lessThanOrEqualTo(bFallback),
          reason: 'More target-fidelity fallbacks is a regression. '
              'Baseline=$bFallback (shallow bodyweight pool).');
    });

    test('mean overall score does not regress (baseline ${bOverall.toStringAsFixed(1)})', () {
      expect(meanOverall, greaterThanOrEqualTo(bOverall - 0.05),
          reason: 'Overall plan quality must not drop. '
              'current=${meanOverall.toStringAsFixed(2)} baseline=${bOverall.toStringAsFixed(2)}');
    });
  });
}
