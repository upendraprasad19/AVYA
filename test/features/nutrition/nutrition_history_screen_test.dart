// The Nutrition History screen and its entry row (plan
// docs/plans/nutrition-history.md 7.2). The data is built by the pure
// `buildNutritionHistoryData`; the Hive -> series chain is pinned by
// test/contracts/nutrition_history_writer_to_reader_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show WeightEntryData;
import 'package:icanbefitter/features/nutrition/providers/nutrition_history_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/screens/nutrition_history_screen.dart';
import 'package:icanbefitter/features/nutrition/services/nutrition_history.dart';
import 'package:icanbefitter/features/nutrition/widgets/history/history_day_sheet.dart';
import 'package:icanbefitter/features/nutrition/widgets/history/history_heatmap.dart';
import 'package:icanbefitter/features/nutrition/widgets/history/history_sections.dart';
import 'package:icanbefitter/features/nutrition/widgets/history/history_trend_chart.dart';
import 'package:icanbefitter/features/nutrition/widgets/insights_section.dart';
import 'package:icanbefitter/features/nutrition/widgets/weekly_chart_card.dart';

const _today = '2026-11-25';

String _key(int daysAgo) => dayKeyOf(
    parseDayKey(_today)!.subtract(Duration(days: daysAgo)));

/// [n] days ending today; every day logged with three meals unless [skip].
NutritionHistoryData _data(
  int n, {
  bool targets = true,
  bool Function(int daysAgo)? skip,
  double kcalPerMeal = 650,
}) {
  final rows = <Object?>[
    for (var ago = n - 1; ago >= 0; ago--)
      if (!(skip?.call(ago) ?? false))
        for (final slot in const ['breakfast', 'lunch', 'dinner'])
          {
            'date': _key(ago),
            'meal_type': slot,
            'total_calories': kcalPerMeal,
            'total_protein': 35.0,
            'total_carbs': 70.0,
            'total_fat': 20.0,
            'total_fiber': 8.0,
            'items': [
              {'name': slot == 'lunch' ? 'Dal Rice' : 'Paneer Bhurji',
               'protein': 35, 'calories': kcalPerMeal},
            ],
          },
  ];
  return buildNutritionHistoryData(
    inputs: (
      rows: rows,
      waterByDay: {for (var ago = n - 1; ago >= 1; ago--) _key(ago): 2600},
      trainingDays: {for (var ago = n - 1; ago >= 0; ago -= 2) _key(ago)},
      onboardingDay: n == 0 ? null : _key(n - 1),
      targets: targets
          ? [
              TargetEntry(
                  from: _key(n > 20 ? 20 : 0), calories: 2000, protein: 100,
                  carbs: 250, fat: 60, strategy: 'balanced', atMs: 1),
            ]
          : const [],
    ),
    todayKey: _today,
    waterTargetMl: 2500,
    weights: [
      for (var ago = n - 1; ago >= 0; ago -= 7)
        WeightEntryData(date: _key(ago), weight: 80 + ago * 0.02),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  NutritionHistoryData data, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [nutritionHistoryProvider.overrideWithValue(data)],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 2400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: const NutritionHistoryScreen(),
      ),
    ),
  ));
  await tester.pump();
}

class _FakeWeekly extends WeeklyNutritionNotifier {
  @override
  WeeklyNutritionData build() => const WeeklyNutritionData();
}

void main() {
  testWidgets('no logs: one empty card and nothing else', (tester) async {
    await _pump(tester, _data(0));
    expect(find.byKey(const Key('history_empty')), findsOneWidget);
    expect(find.byKey(const Key('history_trend')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    for (final n in [1, 10, 400]) {
      testWidgets('$n days at text scale $scale: no overflow', (tester) async {
        await _pump(tester, _data(n), textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('history_since')), findsOneWidget);
        expect(find.byKey(const Key('history_trend')), findsOneWidget);
        expect(find.byKey(const Key('history_heatmap')), findsOneWidget);
      });
    }
  }

  testWidgets('header counts from the first day; today is in progress',
      (tester) async {
    final data = _data(10, skip: (ago) => ago == 3);
    await _pump(tester, data);
    expect(find.text('TRACKING SINCE ${_dayLabelUpper(_key(9))}'), findsOneWidget);
    expect(find.descendant(
        of: find.byKey(const Key('history_day_n')), matching: find.text('10')),
        findsOneWidget);
    expect(find.descendant(
        of: find.byKey(const Key('history_days_logged')),
        matching: find.text('9')), findsOneWidget);
    // 8 full days of 1,950 kcal; today and the skipped day are not counted.
    expect(find.text('Average 1,950 kcal · 8 days'), findsOneWidget);
  });

  testWidgets('range and metric chips switch the chart', (tester) async {
    await _pump(tester, _data(400));
    expect(find.text('Average 1,950 kcal · 29 days'), findsOneWidget,
        reason: '1M = 30 days, today excluded');
    await tester.ensureVisible(find.byKey(const Key('history_range_All')));
    await tester.tap(find.byKey(const Key('history_range_All')));
    await tester.pump();
    expect(find.text('Average 1,950 kcal · 399 days'), findsOneWidget);
    expect(find.text('Weekly average'), findsOneWidget,
        reason: 'a long range shows weekly bars');
    await tester.ensureVisible(find.byKey(const Key('history_metric_protein')));
    await tester.tap(find.byKey(const Key('history_metric_protein')));
    await tester.pump();
    expect(find.text('Average 105 g · 399 days'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('history_metric_water')));
    await tester.tap(find.byKey(const Key('history_metric_water')));
    await tester.pump();
    expect(find.text("Water is compared with today's water target."),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('days before the first recorded target are labelled',
      (tester) async {
    await _pump(tester, _data(60));
    await tester.tap(find.byKey(const Key('history_range_3M')));
    await tester.pump();
    expect(
        find.text('Days before ${_dayLabel(_key(20))} use your earliest '
            'recorded target.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('history_range_1W')));
    await tester.pump();
    expect(find.textContaining('use your earliest recorded target'),
        findsNothing, reason: 'every shown day has its own target');
  });

  testWidgets('no target known: target-based sections hide, the rest shows',
      (tester) async {
    await _pump(tester, _data(30, targets: false));
    expect(find.byKey(const Key('history_hit_calories')), findsNothing);
    expect(find.byKey(const Key('history_hit_protein')), findsNothing);
    expect(find.byKey(const Key('history_hit_water')), findsOneWidget);
    expect(find.text('On target'), findsNothing);
    expect(find.text('Logged'), findsOneWidget);
    expect(find.byKey(const Key('history_macro_split')), findsOneWidget);
    expect(find.byKey(const Key('history_top_foods')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sections below their minimum sample are absent', (tester) async {
    await _pump(tester, _data(2));
    // One full day (yesterday); today is in progress.
    expect(find.byKey(const Key('history_patterns')), findsNothing);
    expect(find.byKey(const Key('history_weight_overlay')), findsNothing);
    expect(find.byKey(const Key('history_insights')), findsNothing);
    expect(find.byKey(const Key('history_macro_split')), findsOneWidget);
    expect(find.byKey(const Key('history_hit_calories')), findsOneWidget);
  });

  testWidgets('a full account shows every section', (tester) async {
    await _pump(tester, _data(120, skip: (ago) => ago > 60 && ago % 2 == 0));
    for (final key in const [
      'history_trend', 'history_consistency', 'history_hit_rates',
      'history_macro_split', 'history_weight_overlay', 'history_patterns',
      'history_top_foods', 'history_insights',
    ]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 300,
          scrollable: find.descendant(
              of: find.byKey(const Key('history_list')),
              matching: find.byType(Scrollable)).first);
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('history_pattern_weekend')), findsOneWidget);
    expect(find.byKey(const Key('history_pattern_training')), findsOneWidget);
    expect(find.byKey(const Key('history_pattern_slots')), findsOneWidget);
    expect(find.text('Dal Rice'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a bar and a heatmap cell opens that day', (tester) async {
    final data = _data(7);
    await _pump(tester, data);
    await tester.tap(find.byKey(const Key('history_range_1W')));
    await tester.pump();

    // The first of 7 bars is 6 days ago.
    final chart = tester.getRect(find.byKey(const Key('history_trend_chart')));
    await tester.tapAt(Offset(chart.left + chart.width / 14, chart.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryDaySheet), findsOneWidget);
    expect(tester.widget<HistoryDaySheet>(find.byType(HistoryDaySheet)).day.date,
        _key(6));
    expect(find.text('1,950 of 2,000 kcal'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryDaySheet), findsNothing);

    // Heatmap: 2026-11-25 is a Wednesday (row 2); the 7 days start on
    // Thursday 19 Nov (column 0, row 3) and today is column 1, row 2.
    expect(heatmapIndexAt(data.days, 0, 3), 0);
    expect(heatmapIndexAt(data.days, 1, 2), 6);
    expect(heatmapIndexAt(data.days, 0, 2), isNull);
    expect(heatmapIndexAt(data.days, 1, 3), isNull);
    final heat = tester.getRect(find.byKey(const Key('history_heatmap')));
    const step = kHeatCell + kHeatGap;
    await tester.tapAt(heat.topLeft + const Offset(step * 1 + 5, step * 2 + 5));
    await tester.pumpAndSettle();
    expect(tester.widget<HistoryDaySheet>(find.byType(HistoryDaySheet)).day.date,
        _today);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('the heatmap has a text twin and a Low protein legend entry '
      '(B-pass F8)', (tester) async {
    final data = _data(10);
    expect(heatmapSummary(data.days),
        'Consistency, 10 days: 1 in progress, 9 on target');
    await _pump(tester, data);
    expect(find.bySemanticsLabel(heatmapSummary(data.days)), findsOneWidget);
    expect(find.text('Low protein'), findsOneWidget);
  });

  testWidgets('the day sheet lists the meals and marks an assumed target',
      (tester) async {
    final day = _data(60).days.first;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoryDaySheet(day: day, waterTargetMl: 2500, meals: const [
          {
            'meal_type': 'Lunch', 'total_calories': 650,
            'items': [{'name': 'Dal Rice'}],
          },
          {'meal_type': 'snack', 'total_calories': 120, 'items': []},
        ]),
      ),
    ));
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.text('SNACKS'), findsOneWidget);
    expect(find.text('Dal Rice'), findsOneWidget);
    expect(find.textContaining('earliest recorded target is used'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trend series: daily up to 92 days, weekly above', (tester) async {
    final d92 = _data(92).days, d93 = _data(93).days;
    expect(buildTrendSeries(d92, NutritionMetric.calories, _today,
            waterTargetMl: 0).weekly, isFalse);
    final weekly = buildTrendSeries(d93, NutritionMetric.calories, _today,
        waterTargetMl: 0);
    expect(weekly.weekly, isTrue);
    expect(weekly.bars.every((b) => !b.counted || b.value == 1950), isTrue);
    final water = buildTrendSeries(d92, NutritionMetric.water, _today,
        waterTargetMl: 2500);
    expect(water.bars.first.target, 2500);
    expect(water.bars.last.counted, isFalse, reason: 'today');
    expect(proteinThisMonth(d92, _today), 25 * 105.0,
        reason: '1..25 Nov, 105 g a day');
  });

  testWidgets('the Insights card: history row always visible, weekly cards on '
      'expand, the row opens the screen and back returns', (tester) async {
    // Wide surface: the pre-existing WeeklyChartCard footer needs more room
    // under the test font than under DM Sans.
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: '/nutrition', routes: [
      GoRoute(
        path: '/nutrition',
        builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: NutritionInsightsSection())),
        routes: [
          GoRoute(
              path: 'history',
              builder: (_, __) => const NutritionHistoryScreen()),
        ],
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        weeklyNutritionProvider.overrideWith(_FakeWeekly.new),
        nutritionHistoryProvider.overrideWithValue(_data(10)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();

    expect(find.text('INSIGHTS & TRENDS'), findsOneWidget);
    expect(find.text('SEE FULL HISTORY'), findsOneWidget);
    expect(find.byType(WeeklyChartCard), findsNothing);
    await tester.tap(find.byKey(const Key('insights_header')));
    await tester.pump();
    expect(find.byType(WeeklyChartCard), findsNWidgets(2));
    expect(find.textContaining('THIS WEEK \u2014 CALORIES'), findsOneWidget);
    expect(find.textContaining('THIS WEEK \u2014 PROTEIN'), findsOneWidget);

    await tester.tap(find.byKey(const Key('see_full_history')));
    await tester.pumpAndSettle();
    expect(find.byType(NutritionHistoryScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('history_back')));
    await tester.pumpAndSettle();
    expect(find.byType(NutritionHistoryScreen), findsNothing);
    expect(find.text('SEE FULL HISTORY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _dayLabel(String key) {
  final d = parseDayKey(key)!;
  return '${d.day} ${_m[d.month - 1]}';
}

String _dayLabelUpper(String key) => _dayLabel(key).toUpperCase();
