// 83e031: ONE personal-records card on Home and Train (plan
// docs/plans/pr-card-unify.md). Train renders Home's `PrSnapshot` with
// `seeAll: PrSeeAll.button`; its own key-lift grid (a second PR reader, the
// recurrence of cb1ab1) and its hand-copied list sheet are gone.
//
// Also the OI-389 T16b port (was test/features/train/stats_grid_cardio_pr_test.dart):
// a duration-only cardio PR reads in its own unit, never "1800 km".
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

ExercisePR _pr(String name, double best, int day,
        {String type = 'weight_reps', String? unit}) =>
    ExercisePR(
      exerciseName: name,
      loggingType: type,
      bestValue: best,
      date: DateTime(2026, 11, day),
      unit: unit,
    );

ExercisePrSeries _two(double a, double b) => ExercisePrSeries([
      PrSeriesPoint(date: '2026-10-01', value: a, reps: 5),
      PrSeriesPoint(date: '2026-11-01', value: b, reps: 5),
    ]);

/// Six PRs on six days, newest first, as `loadAllExercisePRs` returns them:
/// the cut at four and the order are observable.
final _six = [
  _pr('Deadlift', 120, 20),
  _pr('Barbell Back Squat', 90, 18),
  _pr('Barbell Bench Press', 60, 15),
  _pr('Overhead Press', 40, 12),
  _pr('Barbell Row', 70, 9),
  _pr('Leg Press', 150, 5),
];

final _series = <String, ExercisePrSeries>{
  for (final p in _six) exercisePrNameKey(p.exerciseName): _two(p.bestValue - 5, p.bestValue),
};

Future<void> _pump(WidgetTester tester, Widget card,
    {List<ExercisePR>? prs, Map<String, ExercisePrSeries>? series}) async {
  // Wider than a phone: under the test font (Ahem, every glyph a full em
  // square) the unchanged WardButton label overflows its row at 316 dp; it is
  // the same button, at the same width, that Train already showed.
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      allExercisePRsProvider.overrideWith(() => _FakePrs(prs ?? _six)),
      exercisePrSeriesProvider.overrideWithValue(series ?? _series),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: card,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The tile names in render order.
List<String> _tileNames(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null &&
            _six.any((p) => p.exerciseName.toUpperCase() == t.data))
          t.data!,
    ];

void main() {
  const train = PrSnapshot(seeAll: PrSeeAll.button);
  const home = PrSnapshot();

  testWidgets('Home and Train show the same four tiles, newest PR first',
      (tester) async {
    await _pump(tester, home);
    final homeNames = _tileNames(tester);
    await _pump(tester, train);
    final trainNames = _tileNames(tester);
    expect(homeNames, [
      'DEADLIFT',
      'BARBELL BACK SQUAT',
      'BARBELL BENCH PRESS',
      'OVERHEAD PRESS',
    ]);
    expect(trainNames, homeNames);
    expect(find.byType(WardSpark), findsNWidgets(4));
    expect(find.textContaining('First logged'), findsNothing);
    expect(find.textContaining('this month'), findsNothing);
  });

  testWidgets('Train: the VIEW ALL button, never the SEE ALL link',
      (tester) async {
    await _pump(tester, train);
    expect(find.byKey(const Key('pr_view_all_button')), findsOneWidget);
    expect(find.text('VIEW ALL EXERCISE PRS'), findsOneWidget);
    expect(find.textContaining('SEE ALL'), findsNothing);
  });

  testWidgets('Home: the SEE ALL link past four, never the button',
      (tester) async {
    await _pump(tester, home);
    expect(find.text('SEE ALL 6 →'), findsOneWidget);
    expect(find.byKey(const Key('pr_view_all_button')), findsNothing);
  });

  testWidgets("Train's button opens Home's sheet: sparks on every row, a row opens the trend sheet",
      (tester) async {
    await _pump(tester, train);
    await tester.tap(find.byKey(const Key('pr_view_all_button')));
    await tester.pumpAndSettle();
    expect(find.text('ALL EXERCISE PRS'), findsOneWidget);
    expect(find.text('6 EXERCISES'), findsOneWidget);
    // Four tile sparks behind the sheet + one per visible list row.
    expect(find.byType(WardSpark), findsAtLeastNWidgets(5));
    await tester.tap(find.text('Leg Press'));
    await tester.pumpAndSettle();
    expect(find.byType(PrTrendSheet), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('pr_trend_value'))).data,
        '150 kg');
  });

  testWidgets('Train with no PR: the line, no button (founder D6)',
      (tester) async {
    await _pump(tester, train, prs: const [], series: const {});
    expect(find.text('Log workouts to see your PRs here'), findsOneWidget);
    expect(find.byKey(const Key('pr_view_all_button')), findsNothing);
  });

  testWidgets('Train with one PR still shows the button', (tester) async {
    await _pump(tester, train, prs: [_six.first]);
    expect(find.byKey(const Key('pr_view_all_button')), findsOneWidget);
  });

  testWidgets('OI-389 T16b port: a 1800 s cardio PR reads 30 MIN, a 40 m carry 40 M',
      (tester) async {
    await _pump(tester, train, prs: [
      _pr('Running (Treadmill)', 1800, 20, type: 'cardio', unit: 'sec'),
      _pr('Farmers Carry', 0.04, 19, type: 'distance', unit: 'km'),
    ], series: const {});
    expect(find.text('30'), findsOneWidget);
    expect(find.text('MIN'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.textContaining('1800'), findsNothing);
    expect(find.text('KM'), findsNothing);
  });
}
