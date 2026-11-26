// Behavioral contract: rank progression is STRICTLY SEQUENTIAL (no skipping).
//
// Diagnose b9f4d2 / ADR-0011 (2026-05-31). Pre-fix both engines picked the
// highest INDEPENDENTLY-qualifying rung, so an officer-track completion-rate
// qualifier could leap-frog the deployment-gated PO/CPO rungs. The fix walks the
// ladder contiguously and stops at the first failed gate. These tests pin that
// contract via the `_qualifiedRankCode` test seam (no Supabase round-trip).
//
// Gates (rank_ladder_data.dart): SD1 streak>=7/wk>=1 · LS streak>=14/wk>=4 ·
// PO streak>=30/wk>=12/deploy>=2 · CPO streak>=50/wk>=26/deploy>=3 ·
// MCPO wk>=52/comp>=0.80/gap<=14 · SubLt wk>=104/comp>=0.80 ·
// Lt wk>=130/comp>=0.80 · LtCdr wk>=156 · ...

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  final rank = RankService.instance;

  group('Sequential (no-skip) rank progression — b9f4d2 / ADR-0011', () {
    test('officer gate met but sailor streak NOT met → blocked at SD2 (no leap-frog)', () {
      // Lt's own gate (wk>=130, comp>=0.80) would qualify INDEPENDENTLY, but the
      // walk fails at SD1 (streak>=7) and stops there. Pre-fix this returned Lt.
      final code = rank.testQualifiedRankCode(
        streak: 0,
        weeksSinceSignup: 130,
        deploymentsComplete: 5,
        completionRateOverride: 0.95,
      );
      expect(code, 'SD2');
    });

    test('deployments < 2 blocks PO → capped at LS despite long tenure + completion', () {
      final code = rank.testQualifiedRankCode(
        streak: 60,
        weeksSinceSignup: 130,
        deploymentsComplete: 1,
        completionRateOverride: 0.95,
      );
      expect(code, 'LS');
    });

    test('deployments=2 reaches PO but CPO needs 3 → capped at PO', () {
      final code = rank.testQualifiedRankCode(
        streak: 60,
        weeksSinceSignup: 130,
        deploymentsComplete: 2,
        completionRateOverride: 0.95,
      );
      expect(code, 'PO');
    });

    test('MCPO >14-day gap blocks the officer track → capped at CPO', () {
      final code = rank.testQualifiedRankCode(
        streak: 60,
        weeksSinceSignup: 130,
        deploymentsComplete: 3,
        longestGapDays: 20, // > MCPO maxGapDays(14)
        completionRateOverride: 0.95,
      );
      expect(code, 'CPO');
    });

    test('full sailor track + 130-week tenure + completion → reaches Lt sequentially', () {
      final code = rank.testQualifiedRankCode(
        streak: 60, // >= CPO's 50
        weeksSinceSignup: 130, // == Lt gate, < LtCdr's 156
        deploymentsComplete: 3, // >= CPO's 3
        longestGapDays: 0,
        completionRateOverride: 0.95,
      );
      expect(code, 'Lt');
    });

    test('fresh phase-1 user (no streak / no tenure) stays SD2', () {
      expect(rank.testQualifiedRankCode(), 'SD2');
    });
  });
}
