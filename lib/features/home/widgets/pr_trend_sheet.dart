import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/exercise_pr_series.dart';
import 'package:icanbefitter/shared/widgets/weight_trend_chart.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `12 Nov` from a `yyyy-MM-dd` day; the raw string when it does not parse.
String prDayLabel(String day) {
  final d = DateTime.tryParse(day);
  return d == null ? day : '${d.day} ${_months[d.month - 1]}';
}

/// [value] in [pr]'s unit, through the PR's own formatter (one formatter for
/// the tile, the list and the chart).
String prValueLabel(double value, ExercisePR pr) => ExercisePR(
      exerciseName: pr.exerciseName,
      loggingType: pr.loggingType,
      bestValue: value,
      date: pr.date,
      unit: pr.unit,
    ).formattedValue;

/// Tooltip text of one chart point: `82.5 kg x 8 · 12 Nov` (reps only when
/// known), `15 reps · 12 Nov`, `45s · 12 Nov`, `5.2 km · 12 Nov`.
String prPointLabel(PrSeriesPoint point, ExercisePR pr) {
  final value = prValueLabel(point.value, pr);
  final reps = point.reps == null ? '' : ' x ${point.reps}';
  return '$value$reps · ${prDayLabel(point.date)}';
}

/// The one-line summary under the chart, over the FULL series (never the
/// selected range). "now" is the record that stands, not the last day lifted.
String prJourneyLine(ExercisePrSeries series, ExercisePR pr) {
  final pts = series.points;
  if (pts.length < 2) return 'Log it again to see your trend';
  return 'First log ${prDayLabel(pts.first.date)}: '
      '${prValueLabel(pts.first.value, pr)} · '
      'now ${prValueLabel(prRunningBest(pts).last, pr)}';
}

/// A `yyyy-MM-dd` day as a UTC midnight: day differences never lose an hour
/// to a daylight-saving change.
DateTime _utcDay(String day) {
  final d = DateTime.parse(day);
  return DateTime.utc(d.year, d.month, d.day);
}

/// The personal record as of each of [points] (oldest first): the running
/// best. A PR only ever rises or holds, so this never dips, whatever a later
/// day lifted.
List<double> prRunningBest(List<PrSeriesPoint> points) {
  final out = <double>[];
  var best = double.negativeInfinity;
  for (final p in points) {
    if (p.value > best) best = p.value;
    out.add(best);
  }
  return out;
}

/// The points to draw for [window] (null = all): the shared trend window, so a
/// lone recent day still connects to the day before the range.
List<PrSeriesPoint> prWindowPoints(ExercisePrSeries series, Duration? window) {
  final byDate = {for (final p in series.points) p.date: p};
  return [
    for (final w in weightTrendWindow(
      [
        for (final p in series.points)
          WeightTrendPoint(date: p.date, weight: p.value),
      ],
      window,
    ))
      byDate[w.date]!,
  ];
}

/// Index in [shown] of the PR point: the FIRST day of the full [series] whose
/// value equals the PR. Null when the series never reaches the PR (its row has
/// no day) or that day is outside the shown range.
int? prMarkerIndex(
    List<PrSeriesPoint> shown, ExercisePrSeries series, ExercisePR pr) {
  for (final p in series.points) {
    if (p.value == pr.bestValue) {
      final i = shown.indexWhere((s) => s.date == p.date);
      return i < 0 ? null : i;
    }
  }
  return null;
}

/// Opens the full trend chart of one exercise's personal record.
Future<void> showPrTrendSheet(
  BuildContext context, {
  required ExercisePR pr,
  required ExercisePrSeries series,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => PrTrendSheet(pr: pr, series: series),
  );
}

/// Bottom sheet: two lines over one exercise's history, the personal record as
/// a step (it only rises or holds) and the best set of each workout day, with
/// range chips, the PR point marked and a first-log-to-now line. Reads nothing: the
/// caller passes the PR and its series (both already local).
class PrTrendSheet extends StatefulWidget {
  const PrTrendSheet({super.key, required this.pr, required this.series});

  final ExercisePR pr;
  final ExercisePrSeries series;

  @override
  State<PrTrendSheet> createState() => _PrTrendSheetState();
}

/// Index of the lifted line in the chart's bars (0 is the PR step).
const _liftedBar = 1;

class _PrTrendSheetState extends State<PrTrendSheet> {
  String _range = 'All';
  static const _ranges = ['All', '1Y', '6M', '3M', '1M', '1W'];

  Duration? get _window => switch (_range) {
        '1W' => const Duration(days: 7),
        '1M' => const Duration(days: 30),
        '3M' => const Duration(days: 90),
        '6M' => const Duration(days: 180),
        '1Y' => const Duration(days: 365),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final pr = widget.pr;
    final hasTrend = widget.series.points.length >= 2;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, 12, AppSpacing.gutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              pr.exerciseName.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mono.copyWith(
                color: AppColors.textPrimary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  pr.formattedValue,
                  key: const Key('pr_trend_value'),
                  style: AppTypography.h2.copyWith(color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'PERSONAL RECORD · ${pr.formattedDate.toUpperCase()}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            if (hasTrend) ...[
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in _ranges)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          key: Key('pr_trend_range_$r'),
                          onTap: () => setState(() => _range = r),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: r == _range
                                  ? AppColors.accent
                                  : AppColors.input,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                  color: r == _range
                                      ? AppColors.accent
                                      : AppColors.line2),
                            ),
                            child: Text(
                              r,
                              style: AppTypography.monoXs.copyWith(
                                fontWeight: FontWeight.w700,
                                color: r == _range
                                    ? AppColors.bgDeep
                                    : AppColors.textMute,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(height: 190, child: _chart()),
              const SizedBox(height: 8),
              Wrap(
                key: const Key('pr_trend_legend'),
                spacing: 16,
                runSpacing: 4,
                children: [
                  _legend(AppColors.accent, 'Personal record'),
                  _legend(AppColors.textDim, 'Best set that day'),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Text(
              prJourneyLine(widget.series, pr),
              key: const Key('pr_trend_journey'),
              style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 2.5, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: AppTypography.monoXs.copyWith(color: AppColors.textMute)),
        ],
      );

  Widget _chart() {
    final pr = widget.pr;
    final shown = prWindowPoints(widget.series, _window);
    if (shown.length < 2) {
      // The range holds one day and nothing precedes it.
      return Center(
        child: Text(
          'One log in this range',
          style: AppTypography.monoXs.copyWith(color: AppColors.textMute),
        ),
      );
    }
    final marker = prMarkerIndex(shown, widget.series, pr);

    // Date-proportional x: days since the first SHOWN point.
    final first = _utcDay(shown.first.date);
    final spots = [
      for (final p in shown)
        FlSpot(
          _utcDay(p.date).difference(first).inDays.toDouble(),
          p.value,
        ),
    ];
    // The PR as of each shown day, over the FULL series (a PR set before the
    // range still holds inside it).
    final running = prRunningBest(widget.series.points);
    final bestByDate = {
      for (var i = 0; i < running.length; i++)
        widget.series.points[i].date: running[i],
    };
    final prSpots = [
      for (var i = 0; i < shown.length; i++)
        FlSpot(spots[i].x, bestByDate[shown[i].date]!),
    ];
    // The record still stands today: carry the step on to today.
    final todayX = _utcDay(istTodayStr()).difference(first).inDays.toDouble();
    if (todayX > prSpots.last.x) prSpots.add(FlSpot(todayX, prSpots.last.y));
    final values = [...shown.map((p) => p.value), ...prSpots.map((s) => s.y)];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    // 10 % head and foot room; a flat history gets a fixed band around it.
    final pad = hi == lo ? 1.0 : (hi - lo) * 0.1;
    final minY = lo - pad;
    final maxY = hi + pad;
    final maxX = prSpots.last.x;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX <= 0 ? 1 : maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.line2.withValues(alpha: 0.5), strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, meta) => Text(
                v == v.roundToDouble()
                    ? v.toStringAsFixed(0)
                    : v.toStringAsFixed(1),
                style:
                    AppTypography.monoXs.copyWith(color: AppColors.textDim),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: (maxX / 4).clamp(1, 100000).toDouble(),
              getTitlesWidget: (v, meta) {
                final d = first.add(Duration(days: v.round()));
                return Text(
                  '${d.day} ${_months[d.month - 1]}',
                  style: AppTypography.monoXs
                      .copyWith(fontSize: 8, color: AppColors.textDim),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [
              for (final s in touched)
                // One tooltip per day, on the lifted line, naming the PR that
                // stood that day.
                s.barIndex == _liftedBar
                    ? LineTooltipItem(
                        '${prPointLabel(shown[s.spotIndex], pr)}\n'
                        'PR ${prValueLabel(prSpots[s.spotIndex].y, pr)}',
                        AppTypography.bodySm.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : null,
            ],
          ),
        ),
        lineBarsData: [
          // 0: the personal record, a step: flat until a new PR, then a jump.
          LineChartBarData(
            spots: prSpots,
            isStepLineChart: true,
            // Flat until the new PR's day, then the rise (the default,
            // middle, would rise half-way BEFORE the record was set).
            lineChartStepData: const LineChartStepData(
                stepDirection: LineChartStepData.stepDirectionForward),
            color: AppColors.accent,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, bar) => bar.spots.indexOf(spot) == marker,
              getDotPainter: (s, pct, bar, i) => FlDotCirclePainter(
                radius: 5.5,
                color: AppColors.accent,
                strokeWidth: 2,
                strokeColor: AppColors.textPrimary,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withValues(alpha: 0.06),
            ),
          ),
          // 1: the best set actually lifted each day. Straight segments: each
          // point is a real logged day.
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.textDim,
            barWidth: 1.5,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, bar) => bar.spots.length <= 30,
              getDotPainter: (s, pct, bar, i) => FlDotCirclePainter(
                radius: 2.5,
                color: AppColors.textDim,
                strokeWidth: 1,
                strokeColor: AppColors.bg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
