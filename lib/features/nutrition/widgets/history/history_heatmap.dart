// The consistency heatmap of the Nutrition History screen: one cell per day
// since the first day, a column per IST week (Monday on top), newest week at
// the right. Painted (a two-year account is 730 cells), horizontally
// scrollable, tap a cell to open that day.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import '../../services/nutrition_history.dart';
import 'history_common.dart';

const double kHeatCell = 14;
const double kHeatGap = 3;

/// Column (week) and row (weekday, Monday 0) of every day; [days] continuous.
({int columns, int firstRow}) heatmapShape(List<JudgedDay> days) {
  if (days.isEmpty) return (columns: 0, firstRow: 0);
  final firstRow = parseDayKey(days.first.date)!.weekday - 1;
  return (columns: ((firstRow + days.length) / 7).ceil(), firstRow: firstRow);
}

/// The index in [days] of the cell at ([column], [row]), or null.
int? heatmapIndexAt(List<JudgedDay> days, int column, int row) {
  final shape = heatmapShape(days);
  if (row < 0 || row > 6 || column < 0 || column >= shape.columns) return null;
  final i = column * 7 + row - shape.firstRow;
  return (i < 0 || i >= days.length) ? null : i;
}

/// The heatmap in words (the cells are painted, so colour needs a text twin):
/// `Consistency, 120 days: 40 on target, 12 under, ...`.
String heatmapSummary(List<JudgedDay> days) {
  final counts = <DayStatus, int>{};
  for (final j in days) {
    counts[j.status] = (counts[j.status] ?? 0) + 1;
  }
  final parts = [
    for (final s in DayStatus.values)
      if ((counts[s] ?? 0) > 0) '${counts[s]} ${statusLabel(s).toLowerCase()}',
  ];
  return 'Consistency, ${days.length} days: ${parts.join(', ')}';
}

class HistoryHeatmap extends StatelessWidget {
  const HistoryHeatmap({
    super.key,
    required this.days,
    required this.hasTargets,
    this.onDayTap,
  });

  final List<JudgedDay> days;
  final bool hasTargets;
  final ValueChanged<String>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final shape = heatmapShape(days);
    const step = kHeatCell + kHeatGap;
    final width = shape.columns * step - kHeatGap;
    const height = 7 * step - kHeatGap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final d in const ['M', 'W', 'F', 'S'])
                    Text(d,
                        style: AppTypography.monoXs
                            .copyWith(color: AppColors.textMute)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('history_heatmap_scroll'),
                scrollDirection: Axis.horizontal,
                reverse: true, // open on the newest weeks
                child: GestureDetector(
                  key: const Key('history_heatmap'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onDayTap == null
                      ? null
                      : (d) {
                          final i = heatmapIndexAt(
                            days,
                            (d.localPosition.dx / step).floor(),
                            (d.localPosition.dy / step).floor(),
                          );
                          if (i != null) onDayTap!(days[i].date);
                        },
                  child: Semantics(
                    label: heatmapSummary(days),
                    child: CustomPaint(
                      size: Size(width < 0 ? 0 : width, height),
                      painter: _HeatPainter(days, shape.firstRow),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HistoryLegend([
          if (hasTargets) ...[
            (statusColor(DayStatus.onTarget), statusLabel(DayStatus.onTarget)),
            (statusColor(DayStatus.lowProtein),
                statusLabel(DayStatus.lowProtein)),
            (statusColor(DayStatus.under), statusLabel(DayStatus.under)),
            (statusColor(DayStatus.over), statusLabel(DayStatus.over)),
          ] else
            (statusColor(DayStatus.logged), statusLabel(DayStatus.logged)),
          (statusColor(DayStatus.partial), 'Partial / today'),
          (statusColor(DayStatus.notLogged), statusLabel(DayStatus.notLogged)),
        ]),
      ],
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.days, this.firstRow);

  final List<JudgedDay> days;
  final int firstRow;

  @override
  void paint(Canvas canvas, Size size) {
    const step = kHeatCell + kHeatGap;
    final paint = Paint();
    for (var i = 0; i < days.length; i++) {
      final cell = i + firstRow;
      final col = cell ~/ 7, row = cell % 7;
      paint.color = statusColor(days[i].status);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(col * step, row * step, kHeatCell, kHeatCell),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.days != days || old.firstRow != firstRow;
}
