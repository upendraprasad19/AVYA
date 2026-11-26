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

const double kHeatMonthGap = 10;
const double kHeatLabelRow = 16;

/// One month of the calendar: its label, the weekday row of its first day
/// (Monday 0), where its days start in [days], how many, its x offset and its
/// width (cells, or the label when wider).
typedef MonthBlock = ({
  String label,
  int firstRow,
  int start,
  int length,
  double x,
  double width,
});

/// Columns (weeks) a block of [length] days starting on [firstRow] spans.
int monthColumns(int firstRow, int length) => ((firstRow + length) / 7).ceil();

/// The ONE layout of the calendar, used by the painter AND the tap mapping
/// (plan §9 U6). [labelWidth] measures a label (the widget passes a text
/// measure under the ambient text scale). The year joins the first block and
/// every January when the calendar spans more than one year.
List<MonthBlock> monthBlocks(
  List<JudgedDay> days,
  double Function(String) labelWidth,
) {
  if (days.isEmpty) return const [];
  const step = kHeatCell + kHeatGap;
  final spans =
      days.first.date.substring(0, 4) != days.last.date.substring(0, 4);
  final out = <MonthBlock>[];
  var x = 0.0;
  var i = 0;
  while (i < days.length) {
    final ym = days[i].date.substring(0, 7);
    var n = 0;
    while (i + n < days.length && days[i + n].date.startsWith(ym)) {
      n++;
    }
    final m = int.parse(ym.substring(5, 7));
    var label = kHistoryMonthNames[m - 1];
    if (spans && (out.isEmpty || m == 1)) {
      label = '$label ${ym.substring(0, 4)}';
    }
    final firstRow = parseDayKey(days[i].date)!.weekday - 1;
    final cells = monthColumns(firstRow, n) * step - kHeatGap;
    final width = cells > labelWidth(label) ? cells : labelWidth(label);
    out.add((
      label: label,
      firstRow: firstRow,
      start: i,
      length: n,
      x: x,
      width: width,
    ));
    x += width + kHeatMonthGap;
    i += n;
  }
  return out;
}

const List<String> kHistoryMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Total width of [blocks].
double monthBlocksWidth(List<MonthBlock> blocks) =>
    blocks.isEmpty ? 0 : blocks.last.x + blocks.last.width;

/// The index in [days] of the cell under ([dx], [dy]) (label row included in
/// [dy]), or null for a gap, the label row, or the empty part of a block.
int? monthBlockIndexAt(List<MonthBlock> blocks, double dx, double dy) {
  const step = kHeatCell + kHeatGap;
  final y = dy - kHeatLabelRow;
  if (y < 0) return null;
  final row = (y / step).floor();
  if (row > 6 || y - row * step > kHeatCell) return null;
  for (final b in blocks) {
    if (dx < b.x || dx >= b.x + b.width) continue;
    final lx = dx - b.x;
    final col = (lx / step).floor();
    // A column past the block's cells always gives k >= length (below).
    if (lx - col * step > kHeatCell) return null;
    final k = col * 7 + row - b.firstRow;
    if (k < 0 || k >= b.length) return null;
    return b.start + k;
  }
  return null;
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
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = AppTypography.monoXs.copyWith(color: AppColors.textMute);
    double measure(String text) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      return tp.width;
    }

    final blocks = monthBlocks(days, measure);
    const step = kHeatCell + kHeatGap;
    final width = monthBlocksWidth(blocks);
    const height = kHeatLabelRow + 7 * step - kHeatGap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: kHeatLabelRow),
              child: SizedBox(
                height: 7 * step - kHeatGap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final d in const ['M', 'W', 'F', 'S'])
                      Text(d, style: labelStyle),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('history_heatmap_scroll'),
                scrollDirection: Axis.horizontal,
                reverse: true, // open on the newest months
                child: GestureDetector(
                  key: const Key('history_heatmap'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onDayTap == null
                      ? null
                      : (d) {
                          final i = monthBlockIndexAt(
                            blocks,
                            d.localPosition.dx,
                            d.localPosition.dy,
                          );
                          if (i != null) onDayTap!(days[i].date);
                        },
                  child: Semantics(
                    label: heatmapSummary(days),
                    excludeSemantics: true,
                    child: CustomPaint(
                      size: Size(width, height),
                      painter: _HeatPainter(days, blocks, labelStyle, scaler),
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
            (
              statusColor(DayStatus.lowProtein),
              statusLabel(DayStatus.lowProtein),
            ),
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
  _HeatPainter(this.days, this.blocks, this.labelStyle, this.scaler);

  final List<JudgedDay> days;
  final List<MonthBlock> blocks;
  final TextStyle labelStyle;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    const step = kHeatCell + kHeatGap;
    final paint = Paint();
    for (final b in blocks) {
      final tp = TextPainter(
        text: TextSpan(text: b.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      tp.paint(canvas, Offset(b.x, 0));
      for (var k = 0; k < b.length; k++) {
        final cell = k + b.firstRow;
        final col = cell ~/ 7, row = cell % 7;
        paint.color = statusColor(days[b.start + k].status);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              b.x + col * step,
              kHeatLabelRow + row * step,
              kHeatCell,
              kHeatCell,
            ),
            const Radius.circular(3),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.days != days || old.blocks != blocks;
}
