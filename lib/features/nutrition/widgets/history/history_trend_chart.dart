// The trend chart of the Nutrition History screen: one bar per day (weekly
// averages over a long range), the 7-day average line and the target line.
// Painted, not built per bar. A tap on a daily bar reports its day.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import '../../services/nutrition_history.dart';
import 'history_common.dart';

/// Above this many days the bars are weekly averages.
const int kTrendWeeklyAboveDays = 92;

class TrendBar {
  /// The day (daily mode) or the week's Monday (weekly mode).
  final String key;
  final double value;

  /// False = drawn muted (a partial or in-progress day) and not judged.
  final bool counted;
  final double? target;
  final double? average;
  const TrendBar({
    required this.key,
    required this.value,
    this.counted = true,
    this.target,
    this.average,
  });
}

class TrendSeries {
  final List<TrendBar> bars;
  final bool weekly;
  const TrendSeries(this.bars, {required this.weekly});
}

/// The bars for [days] (already cut to the range) and [metric]. For water the
/// target is [waterTargetMl] on every bar.
TrendSeries buildTrendSeries(
  List<JudgedDay> days,
  NutritionMetric metric,
  String todayKey, {
  required int waterTargetMl,
}) {
  double? targetOf(JudgedDay j) => metric == NutritionMetric.water
      ? (waterTargetMl > 0 ? waterTargetMl.toDouble() : null)
      : metricTarget(j.target, metric);

  if (days.length <= kTrendWeeklyAboveDays) {
    final roll = rollingAverage(days, metric, todayKey);
    return TrendSeries([
      for (var i = 0; i < days.length; i++)
        TrendBar(
          key: days[i].date,
          value: metricValue(days[i].day, metric),
          counted: countsFor(days[i], metric, todayKey),
          target: targetOf(days[i]),
          average: roll[i],
        ),
    ], weekly: false);
  }

  final byWeek = <String, List<JudgedDay>>{};
  for (final j in days) {
    (byWeek[mondayOfDayKey(j.date)] ??= []).add(j);
  }
  final mondays = byWeek.keys.toList()..sort();
  return TrendSeries([
    for (final monday in mondays)
      () {
        final week = byWeek[monday]!;
        final avg = averageOf(week, metric, todayKey);
        return TrendBar(
          key: monday,
          value: avg.avg ?? 0,
          counted: avg.n > 0,
          target: targetOf(week.last),
        );
      }(),
  ], weekly: true);
}

class HistoryTrendChart extends StatelessWidget {
  const HistoryTrendChart({
    super.key,
    required this.series,
    required this.metric,
    this.onDayTap,
    this.height = 170,
  });

  final TrendSeries series;
  final NutritionMetric metric;
  final ValueChanged<String>? onDayTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bars = series.bars;
    if (bars.isEmpty) return SizedBox(height: height);
    var maxY = 0.0;
    for (final b in bars) {
      maxY = math.max(maxY, math.max(b.value, b.target ?? 0));
      maxY = math.max(maxY, b.average ?? 0);
    }
    if (maxY <= 0) maxY = 1;
    final color = metricColor(metric);

    final topY = maxY * 1.1;
    final labels = [
      groupedInt(topY.round()),
      groupedInt((topY / 2).round()),
      '0',
    ];
    final axisCol = yAxisWidth(context, labels);
    final mid = bars[bars.length ~/ 2].key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            YAxisLabels(labels: labels, height: height, width: axisCol),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                return GestureDetector(
                  key: const Key('history_trend_chart'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (onDayTap == null || series.weekly)
                      ? null
                      : (d) {
                          final i =
                              (d.localPosition.dx / c.maxWidth * bars.length)
                                  .floor()
                                  .clamp(0, bars.length - 1);
                          onDayTap!(bars[i].key);
                        },
                  child: CustomPaint(
                    key: const Key('history_trend_plot'),
                    size: Size(c.maxWidth, height),
                    painter: _TrendPainter(bars, topY, color),
                  ),
                );
              }),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.only(left: axisCol),
          child: Row(
            children: [
              Expanded(
                  child: _axis(historyDayLabel(bars.first.key), TextAlign.left)),
              if (bars.length > 2)
                Expanded(child: _axis(historyDayLabel(mid), TextAlign.center)),
              if (bars.length > 1)
                Expanded(
                    child:
                        _axis(historyDayLabel(bars.last.key), TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        HistoryLegend([
          (color, series.weekly ? 'Weekly average' : 'Day'),
          if (!series.weekly) (AppColors.textGhost, 'Partial / today'),
          if (!series.weekly) (AppColors.textPrimary, '7-day average'),
          if (bars.any((b) => b.target != null))
            (AppColors.textDim, 'Target'),
        ]),
      ],
    );
  }
}

/// Width of a y-axis label column: the widest label under the ambient text
/// scale, at least 28 dp (plan §11). Shared by every chart on the screen.
double yAxisWidth(BuildContext context, List<String> labels) {
  final scaler = MediaQuery.textScalerOf(context);
  var w = 0.0;
  for (final l in labels) {
    final tp = TextPainter(
      text: TextSpan(
          text: l,
          style: AppTypography.monoXs.copyWith(color: AppColors.textMute)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    if (tp.width > w) w = tp.width;
  }
  return math.max(28.0, w + 6);
}

/// Labels top, middle, bottom along a chart of [height]; numbers only.
class YAxisLabels extends StatelessWidget {
  const YAxisLabels(
      {super.key,
      required this.labels,
      required this.height,
      required this.width});
  final List<String> labels;
  final double height, width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in labels)
            Text(l,
                maxLines: 1,
                softWrap: false,
                style:
                    AppTypography.monoXs.copyWith(color: AppColors.textMute)),
        ],
      ),
    );
  }
}

Widget _axis(String text, TextAlign align) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: AppTypography.monoXs.copyWith(color: AppColors.textMute),
    );

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.bars, this.maxY, this.color);

  final List<TrendBar> bars;
  final double maxY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    final slot = size.width / n;
    final barW = math.max(1.0, slot * 0.7);
    double y(double v) => size.height - (v / maxY) * size.height;

    final grid = Paint()..color = AppColors.border;
    for (final gy in [0.5, size.height / 2, size.height - 0.5]) {
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final counted = Paint()..color = color;
    final muted = Paint()..color = AppColors.textGhost;
    for (var i = 0; i < n; i++) {
      final b = bars[i];
      if (b.value <= 0) continue;
      final left = i * slot + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left, y(b.value), left + barW, size.height),
          topLeft: const Radius.circular(1.5),
          topRight: const Radius.circular(1.5),
        ),
        b.counted ? counted : muted,
      );
    }

    // Target: a stepped dashed line (it changes on the day the target did).
    final targetPaint = Paint()
      ..color = AppColors.textDim
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final t = bars[i].target;
      if (t == null) continue;
      final ty = y(t);
      final x0 = i * slot, x1 = (i + 1) * slot;
      for (var x = x0; x < x1; x += 6) {
        canvas.drawLine(
            Offset(x, ty), Offset(math.min(x + 3, x1), ty), targetPaint);
      }
    }

    // 7-day average.
    final path = Path();
    var open = false;
    for (var i = 0; i < n; i++) {
      final a = bars[i].average;
      if (a == null) {
        open = false;
        continue;
      }
      final p = Offset(i * slot + slot / 2, y(a));
      if (open) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        open = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.bars != bars || old.maxY != maxY || old.color != color;
}
