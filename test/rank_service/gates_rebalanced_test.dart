import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('kRankGates rebalanced numbers (spec §10.2)', () {
    test('all 11 rank codes present', () {
      const expected = {
        'SD2', 'SD1', 'LS', 'PO', 'CPO', 'MCPO',
        'SubLt', 'Lt', 'LtCdr', 'Cdr', 'Capt',
      };
      expect(kRankGates.keys.toSet(), expected);
    });

    test('SD1 strict 7-streak gate', () {
      final g = kRankGates['SD1']!;
      expect(g.streakAtLeast, 7);
      expect(g.minWeeksSinceSignup, 1);
    });

    test('sailor track streak gates relaxed', () {
      expect(kRankGates['LS']!.streakAtLeast, 14);
      expect(kRankGates['PO']!.streakAtLeast, 30);
      expect(kRankGates['CPO']!.streakAtLeast, 50);
    });

    test('MCPO transition: completion-rate + maxGapDays, no streak', () {
      final g = kRankGates['MCPO']!;
      expect(g.streakAtLeast, isNull);
      expect(g.completionRateMinimum, 0.80);
      expect(g.completionRateWindowWeeks, 12);
      expect(g.maxGapDays, 14);
    });

    test('officer ranks have completion-rate gates, no streak', () {
      for (final code in ['SubLt', 'Lt', 'LtCdr', 'Cdr', 'Capt']) {
        final g = kRankGates[code]!;
        expect(g.streakAtLeast, isNull, reason: '$code should not require streak');
        expect(g.completionRateMinimum, isNotNull,
            reason: '$code should require completionRateMinimum');
        expect(g.completionRateWindowWeeks, isNotNull,
            reason: '$code should set completionRateWindowWeeks');
      }
    });

    test('Lt gate at W130 with 26-week 80% window', () {
      final g = kRankGates['Lt']!;
      expect(g.minWeeksSinceSignup, 130);
      expect(g.completionRateMinimum, 0.80);
      expect(g.completionRateWindowWeeks, 26);
    });

    test('Capt has the strictest completion bar', () {
      final g = kRankGates['Capt']!;
      expect(g.completionRateMinimum, 0.85);
      expect(g.completionRateWindowWeeks, 104);
      expect(g.minWeeksSinceSignup, 260);
    });
  });
}
