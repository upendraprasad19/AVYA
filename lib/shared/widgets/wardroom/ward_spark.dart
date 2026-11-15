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
  });

  final List<double> data;
  final double width;
  final double height;
  final Color? color;

  /// When non-null, fills the area beneath the line with [color] at this
  /// alpha (0-1). Used on hero cards where the spark needs more weight.
  final double? fillAlpha;
  final double strokeWidth;

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
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.data,
    required this.color,
    required this.fillAlpha,
    required this.strokeWidth,
  });

  final List<double> data;
  final Color color;
  final double? fillAlpha;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final min = data.reduce((a, b) => a < b ? a : b);
    final max = data.reduce((a, b) => a > b ? a : b);
    final span = (max - min) == 0 ? 1 : (max - min);

    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - min) / span) * (size.height - 2) - 1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
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
      old.strokeWidth != strokeWidth;
}
