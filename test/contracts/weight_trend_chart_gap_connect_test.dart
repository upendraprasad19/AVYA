import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/weight_trend_chart.dart';

/// Behavioral test for the lone-dot fix (diagnose e1c6a9): `weightTrendWindow`
/// must carry the last pre-window point into the series so a weigh-in after a
/// multi-day gap draws a CONNECTING LINE, not an isolated dot.
void main() {
  group('weightTrendWindow carry-forward', () {
    test('a lone in-window weigh-in after a gap carries the prior point in '
        '→ >=2 points (a connecting line)', () {
      final entries = [
        const WeightTrendPoint(date: '2026-05-03', weight: 77.0),
        const WeightTrendPoint(date: '2026-05-21', weight: 77.5),
        const WeightTrendPoint(date: '2026-06-02', weight: 79.7),
      ];
      // 7-day window anchored at the latest (06-02): only 06-02 is in-window.
      final shown = weightTrendWindow(entries, const Duration(days: 7));
      expect(shown.length, greaterThanOrEqualTo(2),
          reason: 'post-gap weigh-in must connect to history, not lone-dot');
      expect(shown.first.date, '2026-05-21',
          reason: 'the last pre-window point is carried forward as the anchor');
      expect(shown.last.date, '2026-06-02');
      // Proportional spacing: the two points are ~12 days apart (not adjacent).
      final gapDays = DateTime.parse(shown.last.date)
          .difference(DateTime.parse(shown.first.date))
          .inDays;
      expect(gapDays, 12);
    });

    test('null window returns all points, sorted ascending', () {
      final shown = weightTrendWindow([
        const WeightTrendPoint(date: '2026-06-02', weight: 79.7),
        const WeightTrendPoint(date: '2026-05-03', weight: 77.0),
      ], null);
      expect(shown.map((e) => e.date).toList(), ['2026-05-03', '2026-06-02']);
    });

    test('single-ever weigh-in returns one point (nothing to connect to)', () {
      final shown = weightTrendWindow(
          [const WeightTrendPoint(date: '2026-06-02', weight: 79.7)],
          const Duration(days: 7));
      expect(shown.length, 1);
    });

    test('drops unparseable dates', () {
      final shown = weightTrendWindow([
        const WeightTrendPoint(date: 'not-a-date', weight: 50),
        const WeightTrendPoint(date: '2026-06-02', weight: 79.7),
      ], null);
      expect(shown.length, 1);
      expect(shown.first.date, '2026-06-02');
    });
  });
}
