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
}
