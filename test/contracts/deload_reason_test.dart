// Batch 10 (W3.1) — the pure deload-decision "why" string (deload_reason.dart).
// Truth-table: precedence is STRUCTURAL-before-EVIDENCE, the copy matches the
// ACTUAL outcome (liftedAny), and each evidence branch is had-data-gated so a
// no-data keep never reads as "fatigue". Pure (no Hive).

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/utils/deload_reason.dart';

String r({
  required bool shouldLift,
  required bool liftedAny,
  bool notDeloadPhase = true,
  bool notBackstop = true,
  bool hasDeloadOnRecord = true,
  bool readinessGood = true,
  bool readinessHadData = true,
  bool e1rmNoFatigue = true,
  bool e1rmHasEvidence = true,
}) =>
    deloadDecisionReason(
      shouldLift: shouldLift,
      liftedAny: liftedAny,
      notDeloadPhase: notDeloadPhase,
      notBackstop: notBackstop,
      hasDeloadOnRecord: hasDeloadOnRecord,
      readinessGood: readinessGood,
      readinessHadData: readinessHadData,
      e1rmNoFatigue: e1rmNoFatigue,
      e1rmHasEvidence: e1rmHasEvidence,
    );

void main() {
  group('deloadDecisionReason — lift outcomes (matches the actual mutation)', () {
    test('shouldLift + liftedAny → working-week copy', () {
      expect(r(shouldLift: true, liftedAny: true), contains('Working week'));
    });
    test('shouldLift but NOTHING lifted → positive "already logged", NOT working', () {
      final s = r(shouldLift: true, liftedAny: false);
      expect(s, contains('Recovery week logged'));
      expect(s, isNot(contains('Working week'))); // must match the deload node shown
    });
  });

  group('deloadDecisionReason — keep, STRUCTURAL before EVIDENCE', () {
    test('scheduled deload phase wins even if readiness ALSO bad', () {
      final s = r(
          shouldLift: false,
          liftedAny: false,
          notDeloadPhase: false, // structural
          readinessGood: false, // evidence — must NOT win
          readinessHadData: true);
      expect(s, contains('Scheduled recovery week'));
      expect(s, isNot(contains('fatigue')));
    });
    test('backstop wins over evidence', () {
      final s = r(
          shouldLift: false,
          liftedAny: false,
          notBackstop: false, // structural
          e1rmNoFatigue: false,
          e1rmHasEvidence: true);
      expect(s, contains('two blocks'));
      expect(s, isNot(contains('dipped')));
    });
  });

  group('deloadDecisionReason — evidence keeps (had-data gated)', () {
    test('fatigue keep requires readinessHadData', () {
      expect(
          r(shouldLift: false, liftedAny: false, readinessGood: false, readinessHadData: true),
          contains('flagged fatigue'));
    });
    test('e1RM dip keep requires e1rmHasEvidence', () {
      expect(
          r(shouldLift: false, liftedAny: false, e1rmNoFatigue: false, e1rmHasEvidence: true),
          contains('dipped'));
    });
    test('NO evidence at all → insufficient-data copy, NOT fatigue/dip', () {
      final s = r(
          shouldLift: false,
          liftedAny: false,
          readinessGood: false,
          readinessHadData: false, // no readiness data
          e1rmNoFatigue: false,
          e1rmHasEvidence: false); // no compound evidence
      expect(s, contains('not enough recent data'));
      expect(s, isNot(contains('fatigue')));
      expect(s, isNot(contains('dipped')));
    });
  });

  group('deloadDecisionReason — brand: non-shaming', () {
    test('never surfaces failure / % / "you missed"', () {
      final all = [
        r(shouldLift: true, liftedAny: true),
        r(shouldLift: true, liftedAny: false),
        r(shouldLift: false, liftedAny: false, notDeloadPhase: false),
        r(shouldLift: false, liftedAny: false, notBackstop: false),
        r(shouldLift: false, liftedAny: false, notBackstop: false, hasDeloadOnRecord: false),
        r(shouldLift: false, liftedAny: false, readinessGood: false),
        r(shouldLift: false, liftedAny: false, e1rmNoFatigue: false),
        r(shouldLift: false, liftedAny: false, readinessGood: false, readinessHadData: false, e1rmNoFatigue: false, e1rmHasEvidence: false),
      ];
      for (final s in all) {
        final lower = s.toLowerCase();
        expect(lower.contains('failed'), isFalse, reason: s);
        expect(lower.contains('you missed'), isFalse, reason: s);
        expect(lower.contains('%'), isFalse, reason: s);
        expect(s.trim(), isNotEmpty);
      }
    });
  });
  // Plan-review round 2, at the FLIP commit — the moment this copy first reaches a
  // user. `notBackstop` is false in THREE distinct worlds (no deload ever
  // recorded / overdue / future marker), which is the correct polarity for the
  // DECISION and wrong as an EXPLANATION. `last_actual_deload_phase` is written
  // by nothing but the evaluator and is LOCAL-ONLY, so a user's FIRST ever
  // week-4 eval reads null — and was told they were "two blocks in" during
  // block ONE. Every generated phase 1/2/3 hits it: archetypeForPhase(1) is
  // 'hypertrophy', so notDeloadPhase is true and the structural branch above is
  // skipped.
  group('backstop copy must not claim history the app does not have', () {
    test('NO deload on record → never says "two blocks"', () {
      final s = r(
          shouldLift: false,
          liftedAny: false,
          notBackstop: false,
          hasDeloadOnRecord: false);
      expect(s, isNot(contains('two blocks')),
          reason: 'a first-block user has no two blocks to be in');
      expect(s, contains('no recovery block on record'));
    });

    test('deload ON record (overdue) → keeps the two-blocks copy', () {
      final s = r(
          shouldLift: false,
          liftedAny: false,
          notBackstop: false,
          hasDeloadOnRecord: true);
      expect(s, contains('two blocks'));
    });

    test('the two branches are DIFFERENT strings (guards a collapsed ternary)',
        () {
      final absent = r(
          shouldLift: false,
          liftedAny: false,
          notBackstop: false,
          hasDeloadOnRecord: false);
      final present = r(
          shouldLift: false,
          liftedAny: false,
          notBackstop: false,
          hasDeloadOnRecord: true);
      expect(absent, isNot(equals(present)));
    });

    test('hasDeloadOnRecord is INERT unless the backstop branch is reached', () {
      // It must not leak into any other branch's copy.
      for (final notDeloadPhase in [true, false]) {
        for (final shouldLift in [true, false]) {
          if (!shouldLift && !notDeloadPhase) continue; // structural branch owns it
          expect(
              r(
                  shouldLift: shouldLift,
                  liftedAny: shouldLift,
                  notDeloadPhase: notDeloadPhase,
                  hasDeloadOnRecord: false),
              equals(r(
                  shouldLift: shouldLift,
                  liftedAny: shouldLift,
                  notDeloadPhase: notDeloadPhase,
                  hasDeloadOnRecord: true)));
        }
      }
    });
  });
}
