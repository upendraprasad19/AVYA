import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

void main() {
  group('RankGate new fields', () {
    test('completionRateMinimum + completionRateWindowWeeks are nullable', () {
      const g = RankGate();
      expect(g.completionRateMinimum, isNull);
      expect(g.completionRateWindowWeeks, isNull);
    });

    test('officer gate carries completion-rate values', () {
      const g = RankGate(
        minWeeksSinceSignup: 104,
        completionRateMinimum: 0.80,
        completionRateWindowWeeks: 26,
      );
      expect(g.completionRateMinimum, 0.80);
      expect(g.completionRateWindowWeeks, 26);
      expect(g.streakAtLeast, isNull);
    });

    test('sailor gate without completion-rate fields stays unaffected', () {
      const g = RankGate(streakAtLeast: 14, minWeeksSinceSignup: 4);
      expect(g.streakAtLeast, 14);
      expect(g.completionRateMinimum, isNull);
      expect(g.completionRateWindowWeeks, isNull);
    });
  });
}
