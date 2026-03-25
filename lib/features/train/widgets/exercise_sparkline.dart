import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

class ExerciseSparkline extends StatelessWidget {
  final List<double> dataPoints;
  final String exerciseName;

  const ExerciseSparkline({
    super.key,
    required this.dataPoints,
    required this.exerciseName,
  });

  @override
  Widget build(BuildContext context) {
    if (dataPoints.length < 2) {
      return Text(
        'No history',
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      );
    }

    final first = dataPoints.first;
    final last = dataPoints.last;

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Expanded(
            child: CustomPaint(
              size: const Size(double.infinity, 20),
              painter: _SparklinePainter(
                dataPoints: dataPoints,
                lineColor: AppColors.accent,
                fillColor: AppColors.accent.withValues(alpha: 0.1),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_formatWeight(first)} \u2192 ${_formatWeight(last)}',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatWeight(double value) {
    if (value == value.roundToDouble()) {
      return '${value.toInt()}kg';
    }
    return '${value.toStringAsFixed(1)}kg';
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> dataPoints;
  final Color lineColor;
  final Color fillColor;

  _SparklinePainter({
    required this.dataPoints,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.length < 2) return;

    final minVal = dataPoints.reduce(min);
    final maxVal = dataPoints.reduce(max);
    final range = maxVal - minVal;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final padding = 1.0;
    final drawHeight = size.height - padding * 2;
    final stepX = size.width / (dataPoints.length - 1);

    final linePath = Path();
    final fillPath = Path();

    for (var i = 0; i < dataPoints.length; i++) {
      final normalized =
          range > 0 ? (dataPoints[i] - minVal) / range : 0.5;
      final x = i * stepX;
      final y = padding + drawHeight * (1 - normalized);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path along the bottom
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.dataPoints != dataPoints ||
        oldDelegate.lineColor != lineColor;
  }
}
