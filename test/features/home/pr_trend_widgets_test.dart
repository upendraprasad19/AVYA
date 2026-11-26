// Home PR tiles, the see-all list and the trend sheet (plan
// docs/plans/pr-strength-charts.md, 5.4). The providers are overridden: the
// Hive -> series chain is pinned by
// test/contracts/exercise_pr_series_writer_to_reader_test.dart.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/home/providers/pr_series_provider.dart';
import 'package:icanbefitter/features/home/widgets/pr_snapshot.dart';
import 'package:icanbefitter/features/home/widgets/pr_trend_sheet.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/exercise_pr_series.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class _FakePrs extends AllExercisePRsNotifier {
  _FakePrs(this._prs);
  final List<ExercisePR> _prs;
  @override
  List<ExercisePR> build() => _prs;
}

ExercisePR _pr(String name, String type, double best, {String? unit, int day = 12}) =>
    ExercisePR(
      exerciseName: name,
      loggingType: type,
      bestValue: best,
      date: DateTime(2026, 11, day),
      unit: unit,
    );

ExercisePrSeries _s(List<(String, double, int?)> pts) => ExercisePrSeries([
      for (final (d, v, r) in pts) PrSeriesPoint(date: d, value: v, reps: r),
    ]);

final _bench = _pr('Barbell Bench Press', 'weight_reps', 82.5);
final _benchSeries = _s([
  ('2026-08-12', 60, 8),
  ('2026-09-20', 75, 5),
  ('2026-11-12', 82.5, 8),
]);
final _plank = _pr('Tuck Planche', 'timed', 15);
final _plankSeries = _s([('2026-11-12', 15, null)]);

Future<void> _pump(
  WidgetTester tester, {
  required List<ExercisePR> prs,
  required Map<String, ExercisePrSeries> series,
  double width = 360,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      allExercisePRsProvider.overrideWith(() => _FakePrs(prs)),
      exercisePrSeriesProvider.overrideWithValue(series),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: const Scaffold(
          body: Padding(
            // Home mounts the card inside AppSpacing.screenPadding (22).
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: PrSnapshot(),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('Home PR tiles', () {
    testWidgets('W1: a sparkline only with two or more logged days, at 360 dp',
        (tester) async {
      await _pump(tester, prs: [
        _bench,
        _plank,
      ], series: {
        'barbell bench press': _benchSeries,
        'tuck planche': _plankSeries,
      });
      expect(tester.takeException(), isNull);
      expect(find.byType(WardSpark), findsOneWidget,
          reason: 'three days of bench history; one day of planche');
      expect(tester.widget<WardSpark>(find.byType(WardSpark)).data, [60, 75, 82.5]);
      // The 19-character name keeps one full-width line beside no sparkline.
      final name = tester.getSize(find.text('BARBELL BENCH PRESS'));
      expect(name.width, greaterThan(100));
    });

    testWidgets('W1: no sparkline at a large text size, and nothing overflows',
        (tester) async {
      await _pump(tester,
          prs: [_bench],
          series: {'barbell bench press': _benchSeries},
          textScale: 1.4);
      expect(tester.takeException(), isNull);
      expect(find.byType(WardSpark), findsNothing);
    });

    testWidgets('W1: no sparkline on a tile narrower than the minimum',
        (tester) async {
      await _pump(tester,
          prs: [_bench, _plank],
          series: {'barbell bench press': _benchSeries},
          width: 320);
      expect(tester.takeException(), isNull);
      expect(find.byType(WardSpark), findsNothing);
    });

    testWidgets('W2: tapping a tile opens the trend sheet of that exercise',
        (tester) async {
      await _pump(tester,
          prs: [_bench, _plank],
          series: {'barbell bench press': _benchSeries, 'tuck planche': _plankSeries});
      await tester.tap(find.text('BARBELL BENCH PRESS'));
      await tester.pumpAndSettle();
      expect(find.byType(PrTrendSheet), findsOneWidget);
      expect(find.byKey(const Key('pr_trend_value')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const Key('pr_trend_value'))).data, '82.5 kg');
      expect(tester.widget<Text>(find.byKey(const Key('pr_trend_journey'))).data,
          'First log 12 Aug: 60 kg · now 82.5 kg');
      // Every range draws without an exception (1W holds one day + its carry).
      for (final r in const ['1W', '1M', '3M', '6M', '1Y', 'All']) {
        await tester.tap(find.byKey(Key('pr_trend_range_$r')));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'range $r');
      }
    });

    testWidgets('W2: every see-all row has its sparkline and opens the sheet',
        (tester) async {
      final prs = [
        _bench,
        _plank,
        _pr('Squat', 'weight_reps', 100),
        _pr('Push Up', 'bodyweight_reps', 30),
        _pr('Deadlift', 'weight_reps', 120),
      ];
      await _pump(tester, prs: prs, series: {
        'barbell bench press': _benchSeries,
        'deadlift': _s([('2026-10-01', 100, 5), ('2026-11-12', 120, 3)]),
      });
      await tester.tap(find.textContaining('SEE ALL 5'));
      await tester.pumpAndSettle();
      expect(find.text('ALL EXERCISE PRS'), findsOneWidget);
      // One tile spark (bench is in the top four) + two list sparks.
      expect(find.byType(WardSpark), findsNWidgets(3));

      await tester.tap(find.text('Deadlift'));
      await tester.pumpAndSettle();
      expect(find.byType(PrTrendSheet), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const Key('pr_trend_value'))).data, '120 kg');
    });

    testWidgets('W3: a one-day exercise opens a sheet with no chart', (tester) async {
      await _pump(tester, prs: [_plank], series: {'tuck planche': _plankSeries});
      await tester.tap(find.text('TUCK PLANCHE'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.byKey(const Key('pr_trend_journey'))).data,
          'Log it again to see your trend');
      expect(find.byKey(const Key('pr_trend_range_1M')), findsNothing);
    });

    testWidgets('W3: an exercise with no series at all still opens', (tester) async {
      await _pump(tester, prs: [_plank], series: const {});
      await tester.tap(find.text('TUCK PLANCHE'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PrTrendSheet), findsOneWidget);
    });
  });

  group('trend sheet helpers', () {
    test('prSparkValues: empty under two days', () {
      expect(prSparkValues(_plankSeries), isEmpty);
      expect(prSparkValues(ExercisePrSeries.empty), isEmpty);
      expect(prSparkValues(_benchSeries), [60, 75, 82.5]);
    });

    // Founder observation 2026-11-26: a PR only rises or holds. 40 kg in Jan,
    // 35 kg in Feb (PR still 40), 42.5 kg in Mar.
    final dip = _s([
      ('2026-01-10', 40, 5),
      ('2026-02-10', 35, 8),
      ('2026-03-10', 42.5, 3),
    ]);

    test('prRunningBest: the PR as of each day never dips', () {
      expect(prRunningBest(dip.points), [40, 40, 42.5]);
      expect(prRunningBest(const []), isEmpty);
    });

    test('prSparkValues: the tile spark is the running PR, not the day lifted', () {
      expect(prSparkValues(dip), [40, 40, 42.5]);
    });

    test('prJourneyLine: "now" is the standing PR after a lighter last day', () {
      final down = _s([('2026-01-10', 40, 5), ('2026-02-10', 35, 8)]);
      expect(prJourneyLine(down, _pr('Bench', 'weight_reps', 40)),
          'First log 10 Jan: 40 kg · now 40 kg');
    });

    testWidgets('the sheet draws a PR step line and the lifted line, with a legend',
        (tester) async {
      final pr = _pr('Bench', 'weight_reps', 42.5);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PrTrendSheet(pr: pr, series: dip))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final bars = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      expect(bars, hasLength(2));
      expect(bars[0].isStepLineChart, isTrue);
      expect(bars[0].spots.take(3).map((s) => s.y), [40, 40, 42.5]);
      expect(bars[1].isStepLineChart, isFalse);
      expect(bars[1].spots.map((s) => s.y), [40, 35, 42.5]);
      expect(find.byKey(const Key('pr_trend_legend')), findsOneWidget);
    });

    testWidgets('the PR step rises ON the new PR day (forward, not middle)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42.5), series: dip))));
      final bars = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      expect(bars[0].lineChartStepData.stepDirection,
          LineChartStepData.stepDirectionForward);
    });

    testWidgets('the PR step is carried on to today; the lifted line stops at the last log',
        (tester) async {
      // 2020 is before any "today" this test runs on.
      final past = _s([('2020-01-10', 40, 5), ('2020-02-10', 35, 8)]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 40), series: past))));
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final pr = data.lineBarsData[0].spots;
      final lifted = data.lineBarsData[1].spots;
      expect(lifted, hasLength(2));
      expect(pr, hasLength(3));
      expect(pr.last.y, 40);
      expect(pr.last.x, greaterThan(lifted.last.x));
      expect(data.maxX, pr.last.x);
    });

    testWidgets('the tooltip is on the lifted line only and names the standing PR',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42.5), series: dip))));
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final bars = data.lineBarsData;
      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(bars[0], 0, bars[0].spots[1]),
        LineBarSpot(bars[1], 1, bars[1].spots[1]),
      ]);
      expect(items, hasLength(2));
      expect(items[0], isNull);
      expect(items[1]!.text, '35 kg x 8 · 10 Feb\nPR 40 kg');
    });

    test('wardSparkVertices: step off is the plain line; step on rises at the next point', () {
      const size = Size(30, 12);
      final plain = wardSparkVertices(const [40, 40, 42.5], size);
      expect(plain.map((o) => o.dx), [0, 15, 30]);
      final stepped = wardSparkVertices(const [40, 40, 42.5], size, step: true);
      // Flat 40 to x=30, then straight up to 42.5 at x=30.
      expect(stepped, [plain[0], plain[1], Offset(30, plain[1].dy), plain[2]]);
    });

    test('wardSparkVertices without step keeps the old path for every other caller', () {
      // Hand-computed from the pre-592da4 painter: x = i/(n-1)*w,
      // y = h - ((v-min)/span)*(h-2) - 1. A dipping series, no corners.
      expect(wardSparkVertices(const [3, 1, 2], const Size(20, 12)),
          const [Offset(0, 1), Offset(10, 11), Offset(20, 6)]);
    });

    testWidgets('every PR spark is drawn as a step', (tester) async {
      await _pump(tester,
          prs: [_bench, _pr('Deadlift', 'weight_reps', 120), _plank, _pr('Squat', 'weight_reps', 1), _pr('Row', 'weight_reps', 1)],
          series: {
            'barbell bench press': _benchSeries,
            'deadlift': _s([('2026-10-01', 100, 5), ('2026-11-12', 120, 3)]),
          });
      await tester.tap(find.textContaining('SEE ALL 5'));
      await tester.pumpAndSettle();
      final sparks = tester.widgetList<WardSpark>(find.byType(WardSpark)).toList();
      expect(sparks, isNotEmpty);
      expect(sparks.every((w) => w.step), isTrue);
    });

    test('wardSparkVertices: a corner before EVERY change, rises and falls', () {
      const size = Size(30, 12);
      final plain = wardSparkVertices(const [40, 42.5, 45, 41], size);
      final stepped = wardSparkVertices(const [40, 42.5, 45, 41], size, step: true);
      expect(stepped, [
        plain[0],
        Offset(plain[1].dx, plain[0].dy), plain[1],
        Offset(plain[2].dx, plain[1].dy), plain[2],
        Offset(plain[3].dx, plain[2].dy), plain[3],
      ]);
    });

    testWidgets('the spark painter draws the stepped vertices when step is on', (tester) async {
      Path strokeOf(WardSpark w) {
        final painter = (w.build(tester.element(find.byType(Scaffold))) as CustomPaint)
            .painter!;
        final canvas = _PathCanvas();
        painter.paint(canvas, Size(w.width, w.height));
        return canvas.paths.single;
      }
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      const data = [40.0, 40.0, 42.5];
      double len(Path p) => p.computeMetrics().fold(0.0, (a, m) => a + m.length);
      double poly(List<Offset> v) {
        var t = 0.0;
        for (var i = 1; i < v.length; i++) {
          t += (v[i] - v[i - 1]).distance;
        }
        return t;
      }
      const size = Size(64, 22);
      final stepped = strokeOf(const WardSpark(data: data, width: 64, height: 22, step: true));
      final plain = strokeOf(const WardSpark(data: data, width: 64, height: 22));
      expect(len(stepped), closeTo(poly(wardSparkVertices(data, size, step: true)), 0.01));
      expect(len(plain), closeTo(poly(wardSparkVertices(data, size)), 0.01));
      expect(len(stepped), greaterThan(len(plain)));

      final a = (const WardSpark(data: data, step: true)
              .build(tester.element(find.byType(Scaffold))) as CustomPaint)
          .painter!;
      final b = (const WardSpark(data: data)
              .build(tester.element(find.byType(Scaffold))) as CustomPaint)
          .painter!;
      expect(a.shouldRepaint(b), isTrue, reason: 'a step change repaints');
    });

    testWidgets('the PR dot sits on the PR bar at the PR day only, over a tint; legend labels',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42.5), series: dip))));
      final bars = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      final pr = bars[0];
      final shown = [for (final s in pr.spots) pr.dotData.checkToShowDot(s, pr)];
      expect(shown.take(3), [false, false, true]);
      expect(shown.skip(3), everyElement(isFalse));
      expect(pr.belowBarData.show, isTrue);
      expect(find.text('Personal record'), findsOneWidget);
      expect(find.text('Best set that day'), findsOneWidget);
    });

    test('the touch marker is on the lifted line only', () {
      final pr = LineChartBarData(spots: const [FlSpot(0, 1), FlSpot(1, 1)], isStepLineChart: true);
      final lifted = LineChartBarData(spots: const [FlSpot(0, 1), FlSpot(1, 1)]);
      expect(prTouchedIndicators(pr, [1]), [null]);
      expect(prTouchedIndicators(lifted, [1]).single, isNotNull);
    });

    testWidgets('day positions count calendar days across a DST change', (tester) async {
      // In America/New_York, 8 Mar 2026 is 23 hours long. Run under
      // TZ=America/New_York to exercise it; elsewhere it is a plain 2-day gap.
      final s = _s([('2026-03-07', 40, 5), ('2026-03-09', 42.5, 5)]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42.5), series: s))));
      final bars = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      expect(bars[1].spots.map((p) => p.x), [0, 2]);
    });

    testWidgets('the built chart puts no touch marker on the PR bar', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42.5), series: dip))));
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final bars = data.lineBarsData;
      expect(data.lineTouchData.getTouchedSpotIndicator(bars[0], [1]), [null]);
      expect(data.lineTouchData.getTouchedSpotIndicator(bars[1], [1]).single, isNotNull);
    });

    testWidgets('the PR step ends on the IST day, not the UTC one', (tester) async {
      // 20:00 UTC on 10 Mar is 01:30 on 11 Mar in India.
      setTestClockTo(DateTime.utc(2026, 3, 10, 20));
      addTearDown(resetTestClock);
      final s = _s([('2026-03-01', 40, 5), ('2026-03-05', 42.5, 5)]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42.5), series: s))));
      final pr = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData[0].spots;
      expect(pr.last.x, 10, reason: '1 Mar -> 11 Mar');
    });

    test('prTailX: to today on All, capped at the chip span, none when today is not later', () {
      expect(prTailX(todayX: 400, lastX: 30, window: null), 400);
      expect(prTailX(todayX: 400, lastX: 30, window: const Duration(days: 7)), 37);
      expect(prTailX(todayX: 33, lastX: 30, window: const Duration(days: 7)), 33);
      expect(prTailX(todayX: 30, lastX: 30, window: null), isNull);
      expect(prTailX(todayX: 10, lastX: 30, window: null), isNull);
    });

    test('prJourneyLine: "now" is the PR even when its own day has no series point', () {
      final s = _s([('2026-01-10', 40, 5), ('2026-02-10', 38, 8)]);
      expect(prJourneyLine(s, _pr('Bench', 'weight_reps', 42.5)),
          'First log 10 Jan: 40 kg · now 42.5 kg');
    });

    testWidgets('legend colours match the bars; lifted dots hide past 30 days', (tester) async {
      final long = _s([
        for (var d = 1; d <= 31; d++)
          ('2026-01-${d.toString().padLeft(2, '0')}', 40.0 + d % 3, 5),
      ]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 42), series: long))));
      final bars = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      final swatches = tester
          .widgetList<Container>(find.descendant(
              of: find.byKey(const Key('pr_trend_legend')), matching: find.byType(Container)))
          .map((c) => c.color)
          .toList();
      expect(swatches, [bars[0].color, bars[1].color]);
      final lifted = bars[1];
      expect(lifted.spots.where((p) => lifted.dotData.checkToShowDot(p, lifted)), isEmpty);
    });

    testWidgets('a PR set before the range still holds inside it', (tester) async {
      // 1W is anchored to the last log (10 Nov): it shows 20 Oct (carried) and
      // 10 Nov. The 50 kg PR from May is before both.
      final old = _s([
        ('2026-05-01', 50, 5),
        ('2026-10-20', 40, 5),
        ('2026-11-10', 45, 5),
      ]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PrTrendSheet(pr: _pr('Bench', 'weight_reps', 50), series: old))));
      await tester.tap(find.byKey(const Key('pr_trend_range_1W')));
      await tester.pump();
      final bars = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;
      expect(bars[1].spots.map((s) => s.y), [40, 45]);
      expect(bars[0].spots.take(2).map((s) => s.y), [50, 50]);
      // The axis makes room for the PR line, not only the lifted values.
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.maxY, greaterThanOrEqualTo(50));
      expect(data.minY, lessThanOrEqualTo(40));
      // 1W: the carried tail is at most a week past the last log, however old.
      expect(bars[0].spots.last.x - bars[1].spots.last.x, lessThanOrEqualTo(7));
    });

    test('W4: a range keeps its days plus ONE carried-forward day', () {
      final s = _s([
        ('2026-05-01', 50, 5),
        ('2026-07-01', 55, 5),
        ('2026-10-20', 60, 5),
        ('2026-11-10', 62.5, 5),
      ]);
      expect([for (final p in prWindowPoints(s, const Duration(days: 30))) p.date],
          ['2026-07-01', '2026-10-20', '2026-11-10']);
      expect(prWindowPoints(s, null).length, 4);
      expect(prWindowPoints(s, const Duration(days: 30)).first.reps, 5,
          reason: 'the windowed points are the series points, reps included');
    });

    test('W5: the marker is the FIRST day at the PR, when it is in range', () {
      final pr = _pr('Bench Press', 'weight_reps', 80);
      final s = _s([
        ('2026-05-01', 70, 5),
        ('2026-06-01', 80, 3),
        ('2026-09-01', 72, 6),
        ('2026-11-01', 80, 4),
        ('2026-11-10', 75, 5),
      ]);
      expect(prMarkerIndex(prWindowPoints(s, null), s, pr), 1);
      expect(prMarkerIndex(prWindowPoints(s, const Duration(days: 30)), s, pr), isNull,
          reason: 'the first PR day (June) is outside the last 30 days and is not '
              'the carried-forward day (September is)');
      expect(prMarkerIndex(prWindowPoints(s, null), s, _pr('Bench Press', 'weight_reps', 90)),
          isNull,
          reason: 'the series never reaches the PR (its row has no day)');
    });

    test('prPointLabel and prJourneyLine in every unit', () {
      const kgPt = PrSeriesPoint(date: '2026-11-12', value: 82.5, reps: 8);
      const noReps = PrSeriesPoint(date: '2026-11-12', value: 100);
      expect(prPointLabel(kgPt, _bench), '82.5 kg x 8 · 12 Nov');
      expect(prPointLabel(noReps, _bench), '100 kg · 12 Nov');
      expect(
          prPointLabel(const PrSeriesPoint(date: '2026-11-12', value: 15),
              _pr('Push Up', 'bodyweight_reps', 15)),
          '15 reps · 12 Nov');
      expect(prPointLabel(const PrSeriesPoint(date: '2026-11-12', value: 45), _plank),
          '45s · 12 Nov');
      expect(
          prPointLabel(const PrSeriesPoint(date: '2026-11-12', value: 5.2),
              _pr('Run', 'cardio', 5.2, unit: 'km')),
          '5.2 km · 12 Nov');
      expect(
          prJourneyLine(_s([('2026-08-12', 8, null), ('2026-11-12', 15, null)]), _plank),
          'First log 12 Aug: 8s · now 15s');
      expect(prJourneyLine(_plankSeries, _plank), 'Log it again to see your trend');
      expect(prJourneyLine(ExercisePrSeries.empty, _plank), 'Log it again to see your trend');
    });
  });
}

/// Records the paths a painter draws.
class _PathCanvas extends Fake implements Canvas {
  final paths = <Path>[];
  @override
  void drawPath(Path path, Paint paint) => paths.add(path);
}
