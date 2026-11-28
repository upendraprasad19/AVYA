// Nutrition History: calories, macros, fibre, water and weight since the
// first day, built only from Hive (plan docs/plans/nutrition-history.md).
// Opened from INSIGHTS & TRENDS on the Nutrition tab. Free for every user.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/nutrition_history_provider.dart';
import '../repositories/nutrition_repository.dart';
import '../services/nutrition_history.dart';
import '../widgets/history/history_common.dart';
import '../widgets/history/history_day_sheet.dart';
import '../widgets/history/history_heatmap.dart';
import '../widgets/history/history_more.dart';
import '../widgets/history/history_sections.dart';
import '../widgets/history/history_trend_chart.dart';

/// Range chips: label -> days back (null = everything).
const List<(String, int?)> kHistoryRanges = [
  ('1W', 7),
  ('1M', 30),
  ('3M', 91),
  ('6M', 182),
  ('1Y', 365),
  ('All', null),
];

/// The last [span] days of [days] (all of them when null or longer).
List<JudgedDay> historyRange(List<JudgedDay> days, int? span) =>
    (span == null || days.length <= span)
        ? days
        : days.sublist(days.length - span);

class NutritionHistoryScreen extends ConsumerStatefulWidget {
  const NutritionHistoryScreen({super.key});

  @override
  ConsumerState<NutritionHistoryScreen> createState() =>
      _NutritionHistoryScreenState();
}

class _NutritionHistoryScreenState
    extends ConsumerState<NutritionHistoryScreen> {
  int _range = 1; // 1M
  NutritionMetric _metric = NutritionMetric.calories;

  @override
  void initState() {
    super.initState();
    // Plan T4: never open on a stale target history. The repository call is
    // idempotent; the provider is rebuilt only when it wrote.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (NutritionRepository.instance.reconcileTargetHistory()) {
        ref.invalidate(nutritionHistoryProvider);
      }
    });
  }

  void _openDay(NutritionHistoryData data, String dayKey) {
    for (final j in data.days) {
      if (j.date == dayKey) {
        showHistoryDaySheet(context,
            day: j, waterTargetMl: data.waterTargetMl);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(nutritionHistoryProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        leading: IconButton(
          key: const Key('history_back'),
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/nutrition'),
        ),
        title: Text(
          'Nutrition history',
          style: AppTypography.body.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: data.isEmpty ? const _EmptyHistory() : _content(data),
      ),
    );
  }

  Widget _content(NutritionHistoryData data) {
    final shown = historyRange(data.days, kHistoryRanges[_range].$2);
    final series = buildTrendSeries(shown, _metric, data.todayKey,
        waterTargetMl: data.waterTargetMl);
    final avg = averageOf(shown, _metric, data.todayKey);
    final first = data.firstTargetDay;
    final showsAssumed = data.hasTargets &&
        first != null &&
        shown.isNotEmpty &&
        shown.first.date.compareTo(first) < 0;
    final assumedLine = showsAssumed
        ? 'Days before ${historyDayLabel(first)} use your earliest recorded '
            'target.'
        : null;
    const gap = SizedBox(height: 12);

    return ListView(
      key: const Key('history_list'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        HistoryJourneyHeader(data: data),
        gap,
        HistorySection(
          key: const Key('history_trend'),
          title: 'TREND',
          note: _metric == NutritionMetric.water
              ? "Water is compared with today's water target."
              : assumedLine,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < kHistoryRanges.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: HistoryChip(
                          key: Key('history_range_${kHistoryRanges[i].$1}'),
                          label: kHistoryRanges[i].$1,
                          selected: i == _range,
                          onTap: () => setState(() => _range = i),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final m in NutritionMetric.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: HistoryChip(
                          key: Key('history_metric_${m.name}'),
                          label: metricLabel(m),
                          selected: m == _metric,
                          onTap: () => setState(() => _metric = m),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                avg.avg == null
                    ? 'No full days in this range yet'
                    : 'Average ${metricText(avg.avg!, _metric)} · '
                        '${avg.n} ${avg.n == 1 ? 'day' : 'days'}',
                key: const Key('history_trend_average'),
                style: AppTypography.titleS
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              HistoryTrendChart(
                series: series,
                metric: _metric,
                onDayTap: (day) => _openDay(data, day),
              ),
              if (!series.weekly) ...[
                const SizedBox(height: 6),
                Text('Tap a bar to see that day.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textMute)),
              ],
            ],
          ),
        ),
        gap,
        HistorySection(
          key: const Key('history_consistency'),
          title: 'CONSISTENCY',
          note: data.hasTargets
              ? 'On target = calories within 10% and protein at 90% or more. '
                  'Tap a day to open it.'
              : 'Tap a day to open it.',
          child: HistoryHeatmap(
            days: data.days,
            hasTargets: data.hasTargets,
            onDayTap: (day) => _openDay(data, day),
          ),
        ),
        ..._spaced([
          HistoryInsights(lines: data.insights),
          HistoryHitRates(
            days: shown,
            todayKey: data.todayKey,
            waterTargetMl: data.waterTargetMl,
          ),
          HistoryProteinByMeal(days: shown),
          HistoryWeekdayProtein(days: shown, todayKey: data.todayKey),
          HistoryOnTargetCompare(days: shown),
          HistoryMacroSplit(days: shown),
          HistoryWeightOverlay(
            days: shown,
            weights: data.weights,
            todayKey: data.todayKey,
          ),
          HistoryPatterns(days: shown, trainingDays: data.trainingDays),
          HistoryTopFoods(foods: data.foods),
          HistoryMonthlyReport(
            days: data.days,
            weights: data.weights,
            todayKey: data.todayKey,
          ),
        ]),
      ],
    );
  }

  /// Each section with a gap above it. A hidden section renders nothing, so
  /// its gap is the only trace; kept small on purpose.
  List<Widget> _spaced(List<Widget> sections) => [
        for (final s in sections)
          Padding(padding: const EdgeInsets.only(top: 12), child: s),
      ];
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: WardCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NO HISTORY YET',
                style: AppTypography.mono
                    .copyWith(color: AppColors.accent, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(
              'Log a meal to start your history. Every day you log shows up '
              'here: calories, protein, carbs, fat, fibre and water.',
              key: const Key('history_empty'),
              style: AppTypography.bodyM.copyWith(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
