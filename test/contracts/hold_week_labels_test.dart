// BEHAVIORAL TEST — hold_week_identity, the LABEL layer (FOB-1 / OI-60)
//
// Concept:  hold_week_identity
// Reader:   lib/core/utils/hold_week_labels.dart — the five pure formatters the
//           hold-aware surfaces render through.
//
// WHY THIS FILE EXISTS. The B-pass on this batch proved the surface coverage
// could not fail. `hold_week_identity_behavioral_test.dart`'s wiring group
// asserts `body.contains('stats.isHolding')` against raw source text; the
// reviewer INVERTED the ternary in profile_content.dart — a real defect showing
// "Holding · Hnull" to every non-holding user and "Week 4" to every holder —
// and all 16 tests still passed. A source grep cannot see a logic inversion.
//
// So every case below asserts the EXACT rendered string on BOTH arms. An
// inversion, a swapped branch, a dropped "H" prefix or a changed separator
// reddens something here. These are pure functions over plain ints, so this
// file needs no Hive, no providers and no clock seam — it is the cheap half of
// the coverage, and hold_week_identity_behavioral_test.dart remains the half
// that proves the IDENTITY feeding them is correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/hold_week_labels.dart';

void main() {
  group('homeWeekSegment', () {
    test('not holding → the plain week counter', () {
      expect(homeWeekSegment(holdOrdinal: null, weekInPhase: 1), 'WK 1');
      expect(homeWeekSegment(holdOrdinal: null, weekInPhase: 4), 'WK 4');
    });

    test('holding → Hn, and the week counter is GONE', () {
      final label = homeWeekSegment(holdOrdinal: 1, weekInPhase: null);
      expect(label, 'HOLDING · H1');
      expect(label.contains('WK'), isFalse,
          reason: 'the whole point of FOB-1: a hold suppresses the week number');
    });

    test('every ordinal keeps its own identity — never a projected 4 + n', () {
      for (var n = 1; n <= 5; n++) {
        final label = homeWeekSegment(holdOrdinal: n, weekInPhase: null);
        expect(label, 'HOLDING · H$n');
        expect(label.contains('${4 + n}'), isFalse,
            reason: 'a 4 + ordinal projection is the one thing FOB-1 forbids');
      }
    });
  });

  group('profileWeekSegment', () {
    test('not holding → sentence-case week', () {
      expect(profileWeekSegment(holdOrdinal: null, weekInPhase: 4), 'Week 4');
    });

    test('holding → sentence-case hold identity', () {
      expect(profileWeekSegment(holdOrdinal: 2, weekInPhase: 4), 'Holding · H2');
    });

    test('holding wins even though weekInPhase is still 4 (the clamp)', () {
      // The exact live shape: UserStatsData.currentWeek stays clamped at 4
      // during a hold because the phase's four weeks ARE elapsed. The label
      // must key on the ordinal, not on that number.
      expect(profileWeekSegment(holdOrdinal: 1, weekInPhase: 4),
          isNot(contains('Week 4')));
    });
  });

  group('journeyWeekLabel', () {
    test('not holding → WEEK n OF 4', () {
      expect(journeyWeekLabel(holdOrdinal: null, weekInPhase: 3),
          'WEEK 3 OF 4');
    });

    test('holding → HOLDING · Hn, no "OF 4"', () {
      final label = journeyWeekLabel(holdOrdinal: 3, weekInPhase: 4);
      expect(label, 'HOLDING · H3');
      expect(label.contains('OF 4'), isFalse,
          reason: 'a hold week is not the 4th week of anything');
    });
  });

  group('journeyPhaseOneMilestone', () {
    test('not holding → the countdown', () {
      expect(journeyPhaseOneMilestone(holdOrdinal: null, weekInPhase: 1),
          '3 weeks to complete Phase 1');
      expect(journeyPhaseOneMilestone(holdOrdinal: null, weekInPhase: 4),
          '0 weeks to complete Phase 1');
    });

    test('holding → states where the user actually is', () {
      // This line renders ONLY when current_phase == 1 — exactly the free-tier
      // holder — so pre-fix it read a flat "0 weeks to complete Phase 1" on the
      // surface a holder sees most.
      expect(journeyPhaseOneMilestone(holdOrdinal: 2, weekInPhase: 4),
          'Phase 1 complete · holding at H2');
    });

    test('the holding arm never emits the dead "0 weeks" copy', () {
      for (var n = 1; n <= 4; n++) {
        expect(journeyPhaseOneMilestone(holdOrdinal: n, weekInPhase: 4),
            isNot(contains('0 weeks')));
      }
    });
  });

  group('roadmapWeekLabel', () {
    test('not holding → WK n / 12 plus the percentage', () {
      expect(
          roadmapWeekLabel(
              holdOrdinal: null, programWeek: 4, completePct: 33),
          'WK 4 / 12  —  33% complete');
    });

    test('holding suppresses the counter but KEEPS the percentage', () {
      // Only the counter lies to a holder. Four of twelve program weeks
      // genuinely are done, so branching the percentage would make it wrong.
      expect(
          roadmapWeekLabel(holdOrdinal: 1, programWeek: 4, completePct: 33),
          'HOLDING · H1  —  33% complete');
    });

    test('the percentage passes through unchanged on BOTH arms', () {
      for (final pct in [0, 33, 67, 100]) {
        expect(
            roadmapWeekLabel(
                holdOrdinal: null, programWeek: 8, completePct: pct),
            contains('$pct% complete'));
        expect(
            roadmapWeekLabel(holdOrdinal: 2, programWeek: 8, completePct: pct),
            contains('$pct% complete'));
      }
    });
  });

  group('cross-cutting — no formatter may print "null"', () {
    // The inversion the B-pass used produced "Holding · Hnull" for every
    // non-holding user. Any future branch swap reddens here even if someone
    // updates the paired string assertion to match their new behaviour.
    test('non-holding arm with a real week never interpolates a null', () {
      expect(homeWeekSegment(holdOrdinal: null, weekInPhase: 4),
          isNot(contains('null')));
      expect(profileWeekSegment(holdOrdinal: null, weekInPhase: 4),
          isNot(contains('null')));
      expect(journeyWeekLabel(holdOrdinal: null, weekInPhase: 4),
          isNot(contains('null')));
      expect(journeyPhaseOneMilestone(holdOrdinal: null, weekInPhase: 4),
          isNot(contains('null')));
      expect(
          roadmapWeekLabel(
              holdOrdinal: null, programWeek: 4, completePct: 33),
          isNot(contains('null')));
    });

    test('holding arm never interpolates a null', () {
      expect(homeWeekSegment(holdOrdinal: 1, weekInPhase: null),
          isNot(contains('null')));
      expect(profileWeekSegment(holdOrdinal: 1, weekInPhase: 4),
          isNot(contains('null')));
      expect(journeyWeekLabel(holdOrdinal: 1, weekInPhase: 4),
          isNot(contains('null')));
      expect(journeyPhaseOneMilestone(holdOrdinal: 1, weekInPhase: 4),
          isNot(contains('null')));
      expect(
          roadmapWeekLabel(holdOrdinal: 1, programWeek: 4, completePct: 33),
          isNot(contains('null')));
    });
  });
}
