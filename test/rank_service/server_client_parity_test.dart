import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

/// Hand-mirror of supabase/functions/_shared/rank_engine.ts kRankGates,
/// kept in sync with G-8. If TS file changes and this map drifts,
/// G-12 test will fail and force re-sync.
const Map<String, Map<String, num>> _serverGates = {
  'SD2': {},
  'SD1':   {'streakAtLeast': 7,  'minWeeksSinceSignup': 1},
  'LS':    {'streakAtLeast': 14, 'minWeeksSinceSignup': 4},
  'PO':    {'streakAtLeast': 30, 'minWeeksSinceSignup': 12, 'deploymentsCompleteAtLeast': 2},
  'CPO':   {'streakAtLeast': 50, 'minWeeksSinceSignup': 26, 'deploymentsCompleteAtLeast': 3},
  'MCPO':  {'minWeeksSinceSignup': 52,  'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 12,  'maxGapDays': 14},
  'SubLt': {'minWeeksSinceSignup': 104, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 26},
  'Lt':    {'minWeeksSinceSignup': 130, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 26},
  'LtCdr': {'minWeeksSinceSignup': 156, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 52},
  'Cdr':   {'minWeeksSinceSignup': 208, 'completionRateMinimum': 0.80, 'completionRateWindowWeeks': 52},
  'Capt':  {'minWeeksSinceSignup': 260, 'completionRateMinimum': 0.85, 'completionRateWindowWeeks': 104},
};

void main() {
  group('Server-client gate parity', () {
    test('every code in client kRankGates also in server mirror', () {
      for (final code in kRankGates.keys) {
        expect(_serverGates.containsKey(code), isTrue,
            reason: 'Server mirror missing rank: $code');
      }
    });

    test('every server code also in client kRankGates', () {
      for (final code in _serverGates.keys) {
        expect(kRankGates.containsKey(code), isTrue,
            reason: 'Client missing rank present on server: $code');
      }
    });

    test('numeric thresholds match', () {
      for (final code in kRankGates.keys) {
        final c = kRankGates[code]!;
        final s = _serverGates[code]!;
        expect(c.streakAtLeast, s['streakAtLeast'],
            reason: '$code streakAtLeast mismatch');
        expect(c.totalWorkoutsAtLeast, s['totalWorkoutsAtLeast'],
            reason: '$code totalWorkoutsAtLeast mismatch');
        expect(c.minWeeksSinceSignup, s['minWeeksSinceSignup'],
            reason: '$code minWeeksSinceSignup mismatch');
        expect(c.deploymentsCompleteAtLeast, s['deploymentsCompleteAtLeast'],
            reason: '$code deploymentsCompleteAtLeast mismatch');
        expect(c.maxGapDays, s['maxGapDays'],
            reason: '$code maxGapDays mismatch');
        expect(c.completionRateMinimum, s['completionRateMinimum'],
            reason: '$code completionRateMinimum mismatch');
        expect(c.completionRateWindowWeeks, s['completionRateWindowWeeks'],
            reason: '$code completionRateWindowWeeks mismatch');
      }
    });
  });
}
