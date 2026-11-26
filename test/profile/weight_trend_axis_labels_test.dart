// Weekly Report "Weight Trend" card: the axis labels must not be drawn on top of each other.
//
// Founder walk 2026-11-25 (A22, AAB +50, Upendra's real data): the date labels at the right end
// of the chart printed over each other ("13/11" and "25/11" interleaved), and the left axis printed
// "74" twice. The x labels sit every `round(n / 5)` points and the chart library adds one more label
// at the LAST point; with 27 weigh-ins the step is 5, so the label at point 25 and the forced one at
// point 26 are a single slot apart. The left axis forces a label at the (non-integer) minimum on top
// of the tick at the same whole number.
//
// BEHAVIOURAL: the REAL titles function the screen uses is pumped into a real `LineChart` and the
// rendered label rectangles are read back. No Hive, no provider scope.
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/screens/reports_screen.dart';

/// Upendra's real weigh-ins from the 3M window on 2026-11-25 (cloud `weight_logs`), the exact data
/// behind the screenshot: 27 points, the last one a +4 kg jump.
const _upendra = <List<Object>>[
  ['2026-08-29', 78.0],
  ['2026-09-14', 77.0],
  ['2026-09-15', 76.7],
  ['2026-09-16', 76.5],
  ['2026-09-17', 75.9],
  ['2026-09-18', 75.7],
  ['2026-09-19', 76.0],
  ['2026-09-21', 76.2],
  ['2026-09-23', 76.0],
  ['2026-09-24', 75.5],
  ['2026-09-25', 75.7],
  ['2026-09-26', 75.7],
  ['2026-09-28', 76.5],
  ['2026-09-29', 76.2],
  ['2026-09-30', 75.6],
  ['2026-10-01', 75.6],
  ['2026-10-06', 75.3],
  ['2026-10-07', 75.5],
  ['2026-10-09', 75.2],
  ['2026-10-16', 74.8],
  ['2026-10-22', 75.5],
  ['2026-10-25', 75.5],
  ['2026-11-02', 75.0],
  ['2026-11-03', 74.6],
  ['2026-11-04', 74.5],
  ['2026-11-13', 75.0],
  ['2026-11-25', 79.0],
];

List<Map<String, dynamic>> _entries(int n) => [
      for (final e in _upendra.take(n)) {'date': e[0], 'weight_kg': e[1]},
    ];

/// Pumps the chart the way the screen builds it (index x, the screen's y range for this data).
Future<void> _pump(WidgetTester tester, List<Map<String, dynamic>> entries) async {
  final spots = [
    for (var i = 0; i < entries.length; i++)
      FlSpot(i.toDouble(), (entries[i]['weight_kg'] as num).toDouble()),
  ];
  final ys = spots.map((s) => s.y);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 340,
          height: 180,
          child: LineChart(LineChartData(
            minY: ys.reduce((a, b) => a < b ? a : b) - 1,
            maxY: ys.reduce((a, b) => a > b ? a : b) + 1,
            titlesData: weightTrendTitlesData(entries),
            lineBarsData: [LineChartBarData(spots: spots)],
          )),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

final _dateLabel = RegExp(r'^\d{1,2}/\d{1,2}$');

/// The rendered x labels (`d/m`), left to right.
List<String> _xLabels(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where(_dateLabel.hasMatch)
    .toList();

/// The rendered y labels (whole numbers).
List<String> _yLabels(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => RegExp(r'^\d+$').hasMatch(s))
    .toList();

void main() {
  testWidgets('27 weigh-ins: no two date labels overlap, and the newest date is shown',
      (tester) async {
    await _pump(tester, _entries(27));

    final labels = _xLabels(tester);
    expect(labels, contains('25/11'), reason: 'the newest weigh-in date must be labelled');
    expect(labels, contains('29/8'), reason: 'the first date must be labelled');

    final rects = [for (final l in labels) tester.getRect(find.text(l))];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse,
            reason: '${labels[i]} and ${labels[j]} are drawn on top of each other '
                '(${rects[i]} vs ${rects[j]})');
      }
    }
  });

  testWidgets('27 weigh-ins: the in-between dates the chart always had are still shown',
      (tester) async {
    await _pump(tester, _entries(27));

    // Points 5, 10, 15, 20 (every 5th) are far from the last point: they stay.
    expect(_xLabels(tester), containsAll(['18/9', '25/9', '1/10', '22/10']));
  });

  testWidgets('mirror: when the last point lands on a step, every label is still drawn',
      (tester) async {
    // 26 weigh-ins: step 5, last point 25 = a multiple, so nothing is forced and nothing is dropped.
    await _pump(tester, _entries(26));

    expect(_xLabels(tester), ['29/8', '18/9', '25/9', '1/10', '22/10', '13/11']);
  });

  testWidgets('27 weigh-ins: the left axis never prints the same number twice', (tester) async {
    await _pump(tester, _entries(27));

    final labels = _yLabels(tester);
    expect(labels, isNotEmpty);
    expect(labels.toSet().length, labels.length, reason: 'left labels were $labels');
    // The real ticks stay (the minimum's forced label is the only one dropped).
    expect(labels, containsAll(['74', '76', '78', '80']));
  });

  testWidgets('a narrow weight range (ticks under 1 kg apart) still prints distinct left labels',
      (tester) async {
    // Range 0.2 kg + the chart's 1 kg padding each side = 2.2 kg: the library picks 0.5 kg ticks.
    final narrow = [
      {'date': '2026-11-01', 'weight_kg': 75.0},
      {'date': '2026-11-02', 'weight_kg': 75.1},
      {'date': '2026-11-03', 'weight_kg': 75.2},
    ];
    await _pump(tester, narrow);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => RegExp(r'^\d+(\.\d)?$').hasMatch(s))
        .toList();
    expect(labels, isNotEmpty);
    expect(labels.toSet().length, labels.length, reason: 'left labels were $labels');
  });

  testWidgets('every count from 2 to 27 weigh-ins: no two date labels overlap',
      (tester) async {
    // The half-step rule left 10, 12 and 19 overlapping.
    for (var n = 2; n <= _upendra.length; n++) {
      await _pump(tester, _entries(n));
      final labels = _xLabels(tester);
      expect(labels.last, '${int.parse((_upendra[n - 1][0] as String).substring(8))}/'
          '${int.parse((_upendra[n - 1][0] as String).substring(5, 7))}',
          reason: 'n=$n: the newest weigh-in is labelled');
      final rects = [for (final l in labels) tester.getRect(find.text(l))];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i - 1].overlaps(rects[i]), isFalse,
            reason: 'n=$n: ${labels[i - 1]} and ${labels[i]} overlap '
                '(${rects[i - 1]} vs ${rects[i]})');
      }
    }
  });

  test('2 to 90 weigh-ins: drawn date labels are never closer than one full step', () {
    for (var n = 2; n <= 90; n++) {
      final last = n - 1;
      final interval = (n / 5).clamp(1, 100).roundToDouble();
      // The chart library offers every multiple of the step, plus the last point.
      final offered = <int>{for (var i = 0; i <= last; i += interval.toInt()) i, last}
          .toList()
        ..sort();
      final drawn = [
        for (final i in offered)
          if (weightTrendKeepsDateLabel(i, last, interval)) i
      ];
      expect(drawn.first, 0, reason: 'n=$n');
      expect(drawn.last, last, reason: 'n=$n');
      for (var i = 1; i < drawn.length; i++) {
        expect(drawn[i] - drawn[i - 1], greaterThanOrEqualTo(interval.toInt()),
            reason: 'n=$n: labels at ${drawn[i - 1]} and ${drawn[i]}, step $interval');
      }
    }
  });

  testWidgets('a 72 to 78 kg range keeps both ends: the axis is not one number',
      (tester) async {
    await _pump(tester, [
      {'date': '2026-11-01', 'weight_kg': 72.0},
      {'date': '2026-11-02', 'weight_kg': 75.0},
      {'date': '2026-11-03', 'weight_kg': 78.0},
    ]);
    expect(_yLabels(tester), containsAll(['71', '75', '79']));
  });

  test('weight label rule: ends are dropped only beside a drawn tick', () {
    // A tick is always drawn.
    expect(weightTrendKeepsWeightLabel(74, 74, 76.2, 0.5), isTrue);
    // The founder's chart: forced minimum 73.5 beside tick 74 ("74" twice).
    expect(weightTrendKeepsWeightLabel(73.5, 73.5, 80, 2), isFalse);
    // Exactly half a step away still prints the same rounded text.
    expect(weightTrendKeepsWeightLabel(73.5, 73.5, 80, 1), isFalse);
    // Forced ends far from every drawn tick stay.
    expect(weightTrendKeepsWeightLabel(71, 71, 79, 5), isTrue);
    expect(weightTrendKeepsWeightLabel(79, 71, 79, 5), isTrue);
    // A neighbour tick OUTSIDE the axis is not drawn, so it cannot crowd the end:
    // 70 is 0.9 away from 70.9 but is below the minimum; 72 is 1.1 away.
    expect(weightTrendKeepsWeightLabel(70.9, 70.9, 79, 2), isTrue);
    // The forced maximum beside the tick below it.
    expect(weightTrendKeepsWeightLabel(76.2, 74, 76.2, 0.5), isFalse);
  });

  test('wiring (source pin): the Weight Trend chart uses these titles', () {
    final src = File('lib/features/profile/screens/reports_screen.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(src.contains('titlesData: weightTrendTitlesData(entries),'), isTrue);
  });
}
