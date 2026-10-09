import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// One weight sample: an IST date string (`YYYY-MM-DD`) + weight in kg.
class WeightTrendPoint {
  final String date;
  final double weight;
  const WeightTrendPoint({required this.date, required this.weight});
}

/// Sorts [entries] by parsed date ascending (dropping unparseable dates),
/// windows to [window] anchored at the LATEST sample, then CARRIES FORWARD the
/// last point strictly before the window so a post-gap weigh-in always connects
/// to prior history with a line — never a misleading lone dot. [window] null →
/// all points (sorted). This is the lone-dot fix (e1c6a9); kept top-level + pure
/// so it is unit-testable.
@visibleForTesting
List<WeightTrendPoint> weightTrendWindow(
    List<WeightTrendPoint> entries, Duration? window) {
  DateTime? dayOf(WeightTrendPoint p) {
    final parsed = DateTime.tryParse(p.date);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  final all = entries.where((e) => dayOf(e) != null).toList()
    ..sort((a, b) => dayOf(a)!.compareTo(dayOf(b)!));
  if (window == null || all.isEmpty) return all;

  // Anchor the cutoff to the latest sample (not "now") so a user who hasn't
  // logged recently still sees their most recent stretch.
  final cutoff = dayOf(all.last)!.subtract(window);
  final inWindow = all.where((p) => !dayOf(p)!.isBefore(cutoff)).toList();
  // Carry-forward: prepend the last point strictly before the cutoff if one
  // exists, so a lone recent weigh-in still draws a connecting line.
  final beforeIdx = all.lastIndexWhere((p) => dayOf(p)!.isBefore(cutoff));
  if (beforeIdx >= 0) return [all[beforeIdx], ...inWindow];
  return inWindow;
}

/// Rich weight-trend line chart (fl_chart) with range chips, a dashed goal
/// line, and a **date-proportional** x-axis so the gap between weigh-ins
/// renders at its true width.
///
/// Obs 4 (2026-06-02): the old Home sparkline drew a single dot when only one
/// point fell in the range (the founder logged after a 7+ day gap → lone dot,
/// reading as a stray entry). This chart **carries the last logged point
/// BEFORE the selected window into the series**, so a recent weigh-in after a
/// gap always connects to prior history with a line — never an isolated dot.
/// A genuine single-ever weigh-in still shows one point (nothing to connect to).
///
/// Self-contained card chrome (label + latest + chips + chart + optional goal
/// footer + optional "View full history →"). Shared by Home; the Reports screen
/// keeps its own framing.
class WeightTrendChart extends StatefulWidget {
  /// Any order — the widget sorts by date ascending.
  final List<WeightTrendPoint> entries;

  /// Goal weight in kg; `<= 0` hides the goal line + footer.
  final double targetWeight;

  /// Chart-area height (px). Home uses a compact value.
  final double chartHeight;

  /// Optional tap on the "View full history →" footer (Home → Reports).
  final VoidCallback? onViewFullHistory;

  const WeightTrendChart({
    super.key,
    required this.entries,
    this.targetWeight = 0,
    this.chartHeight = 150,
    this.onViewFullHistory,
  });

  @override
  State<WeightTrendChart> createState() => _WeightTrendChartState();
}

class _WeightTrendChartState extends State<WeightTrendChart> {
  String _range = '3M';
  static const _ranges = ['All', '1Y', '6M', '3M', '1M', '1W'];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Duration? _rangeWindow() {
    switch (_range) {
      case '1W':
        return const Duration(days: 7);
      case '1M':
        return const Duration(days: 30);
      case '3M':
        return const Duration(days: 90);
      case '6M':
        return const Duration(days: 180);
      case '1Y':
        return const Duration(days: 365);
      default:
        return null; // 'All'
    }
  }

  // Sorting + windowing + carry-forward live in the top-level pure function
  // `weightTrendWindow` (above the class) so they're unit-testable — that is the
  // lone-dot fix (e1c6a9). build() converts its WeightTrendPoint output to the
  // (date, weight) tuples the chart math uses.

  @override
  Widget build(BuildContext context) {
    final allPts = weightTrendWindow(widget.entries, null); // all, sorted

    if (allPts.isEmpty) {
      return _card(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.monitor_weight_outlined,
                size: 16, color: AppColors.textDim),
            const SizedBox(width: 8),
            Text('Log your weight to see trends here',
                style: AppTypography.bodySm.copyWith(color: AppColors.textDim)),
          ],
        ),
      );
    }

    final shown = [
      for (final p in weightTrendWindow(widget.entries, _rangeWindow()))
        (d: DateTime.parse(p.date), w: p.weight),
    ];
    final latest = allPts.last.weight;
    final target = widget.targetWeight;
    final reachedGoal = target > 0 &&
        // "reached" = within 0.2 kg of goal (either direction).
        (latest - target).abs() <= 0.2;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: label + latest value.
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined,
                  size: 12, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text('WEIGHT TREND',
                  style: AppTypography.mono
                      .copyWith(color: AppColors.textMute, letterSpacing: 2)),
              const Spacer(),
              Text(latest.toStringAsFixed(1),
                  style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
              const SizedBox(width: 3),
              Text('KG',
                  style: AppTypography.monoXs
                      .copyWith(color: AppColors.textMute, letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 10),

          // Range chips.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _ranges.map((r) {
                final active = r == _range;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _range = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent : AppColors.input,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                            color: active ? AppColors.accent : AppColors.line2),
                      ),
                      child: Text(r,
                          style: AppTypography.monoXs.copyWith(
                            fontWeight: FontWeight.w700,
                            color: active ? AppColors.bgDeep : AppColors.textMute,
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(height: widget.chartHeight, child: _buildChart(shown, target)),

          if (reachedGoal) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 14, color: AppColors.ok),
                const SizedBox(width: 6),
                Text("You've reached your goal weight!",
                    style: AppTypography.bodySm.copyWith(color: AppColors.ok)),
              ],
            ),
          ],

          if (widget.onViewFullHistory != null) ...[
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onViewFullHistory,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Text('View full history →',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.line2),
        ),
        child: child,
      );

  Widget _buildChart(List<({DateTime d, double w})> shown, double target) {
    if (shown.length < 2) {
      // Genuine single weigh-in (no prior history to connect to). Show the one
      // point clearly rather than a misleading empty/flat line.
      final only = shown.isEmpty ? null : shown.first;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (only != null)
              Text('${only.w.toStringAsFixed(1)} kg',
                  style: AppTypography.h3.copyWith(color: AppColors.accent)),
            const SizedBox(height: 4),
            Text('Log again to see your trend line',
                style:
                    AppTypography.monoXs.copyWith(color: AppColors.textMute)),
          ],
        ),
      );
    }

    // Date-proportional x: days since the first SHOWN point.
    final first = shown.first.d;
    final spots = <FlSpot>[];
    for (final p in shown) {
      spots.add(FlSpot(p.d.difference(first).inDays.toDouble(), p.w));
    }

    final weights = shown.map((p) => p.w);
    double minY = weights.reduce((a, b) => a < b ? a : b) - 1;
    double maxY = weights.reduce((a, b) => a > b ? a : b) + 1;
    if (target > 0) {
      minY = minY < target ? minY : target - 1;
      maxY = maxY > target ? maxY : target + 1;
    }
    final maxX = spots.last.x;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX <= 0 ? 1 : maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 50.0),
          getDrawingHorizontalLine: (v) =>
              FlLine(color: AppColors.line2.withValues(alpha: 0.5), strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0),
                  style: AppTypography.monoXs.copyWith(color: AppColors.textDim)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: (maxX / 4).clamp(1, 100000).toDouble(),
              getTitlesWidget: (v, meta) {
                final d = first.add(Duration(days: v.round()));
                return Text('${d.day} ${_months[d.month - 1]}',
                    style: AppTypography.monoXs
                        .copyWith(fontSize: 8, color: AppColors.textDim));
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
            getTooltipItems: (touched) => touched.map((s) {
              final d = first.add(Duration(days: s.x.round()));
              return LineTooltipItem(
                '${s.y.toStringAsFixed(1)} kg\n${d.day} ${_months[d.month - 1]}',
                AppTypography.bodySm.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              );
            }).toList(),
          ),
        ),
        extraLinesData: target > 0
            ? ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: target,
                  color: AppColors.ok.withValues(alpha: 0.5),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    labelResolver: (_) => 'Goal: ${target.toStringAsFixed(0)}kg',
                    style: AppTypography.monoXs.copyWith(color: AppColors.ok),
                  ),
                ),
              ])
            : ExtraLinesData(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.accent,
            barWidth: 2.5,
            dotData: FlDotData(
              show: spots.length <= 30,
              getDotPainter: (s, pct, bar, i) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.accent,
                strokeWidth: 1,
                strokeColor: AppColors.bg,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}
