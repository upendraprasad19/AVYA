import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// 1.5-px Campaign Gold sparkline for weight / volume / streak trends.
/// No axes, no labels — the surrounding [WardCard] provides context.
/// Min/max are auto-scaled to the data range. Optional fill gradient
/// under the line for hero cards.
class WardSpark extends StatelessWidget {
  const WardSpark({
    super.key,
    required this.data,
    this.width = 80,
    this.height = 24,
    this.color,
    this.fillAlpha,
    this.strokeWidth = 1.5,
    this.step = false,
  });

  final List<double> data;
  final double width;
  final double height;
  final Color? color;

  /// When non-null, fills the area beneath the line with [color] at this
  /// alpha (0-1). Used on hero cards where the spark needs more weight.
  final double? fillAlpha;
  final double strokeWidth;

  /// Draw a step (flat, then a vertical rise at the next point) instead of a
  /// straight segment between points. Off by default: every other caller's
  /// path is unchanged.
  final bool step;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      return SizedBox(width: width, height: height);
    }
    return CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(
        data: data,
        color: color ?? AppColors.accent,
        fillAlpha: fillAlpha,
        strokeWidth: strokeWidth,
        step: step,
      ),
    );
  }
}

/// The vertices of the spark path of [data] in [size]: points index-spaced
/// across the width, auto-scaled to the data range. With [step], each change
/// gets a corner at the NEXT point's x and the CURRENT value first, so the
/// line is flat until the next point and rises there. Pure, for tests.
List<Offset> wardSparkVertices(List<double> data, Size size,
    {bool step = false}) {
  final min = data.reduce((a, b) => a < b ? a : b);
  final max = data.reduce((a, b) => a > b ? a : b);
  final span = (max - min) == 0 ? 1 : (max - min);
  final out = <Offset>[];
  for (var i = 0; i < data.length; i++) {
    final x = (i / (data.length - 1)) * size.width;
    final y = size.height - ((data[i] - min) / span) * (size.height - 2) - 1;
    if (step && i > 0 && out.last.dy != y) out.add(Offset(x, out.last.dy));
    out.add(Offset(x, y));
  }
  return out;
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.data,
    required this.color,
    required this.fillAlpha,
    required this.strokeWidth,
    required this.step,
  });

  final List<double> data;
  final Color color;
  final double? fillAlpha;
  final double strokeWidth;
  final bool step;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final pts = wardSparkVertices(data, size, step: step);
    for (var i = 0; i < pts.length; i++) {
      if (i == 0) {
        path.moveTo(pts[i].dx, pts[i].dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }

    if (fillAlpha != null) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: fillAlpha!);
      canvas.drawPath(fillPath, fillPaint);
    }

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.data != data ||
      old.color != color ||
      old.fillAlpha != fillAlpha ||
      old.strokeWidth != strokeWidth ||
      old.step != step;
}
