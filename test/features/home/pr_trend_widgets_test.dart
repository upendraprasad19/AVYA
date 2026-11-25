// Home PR tiles, the see-all list and the trend sheet (plan
// docs/plans/pr-strength-charts.md, 5.4). The providers are overridden: the
// Hive -> series chain is pinned by
// test/contracts/exercise_pr_series_writer_to_reader_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
