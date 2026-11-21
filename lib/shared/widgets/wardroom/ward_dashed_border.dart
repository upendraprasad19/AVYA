import 'package:flutter/material.dart';

/// Paints a dashed rectangular border with rounded corners.
///
/// Use as the `foregroundPainter` on a `CustomPaint` (or wrap with
/// `DashedBorder`) when a Wardroom "empty / add new" affordance is needed
/// (empty meal slots, "Request deep analysis" coach CTA, "+ Create custom
/// exercise" Train row, etc.).
///
/// Mirrors the `borderStyle: 'dashed'` pattern from the handoff
/// (`design_handoff_wardroom/src/screens/*.jsx`). Stroke width, dash length,
/// gap length, and corner radius are all overridable so callers can tune the
/// look per-surface — defaults follow the nutrition empty-slot spec
/// (nutrition.jsx line 121: `1px dashed ${t.accent}44`, radius = radCard).
class WardDashedBorderPainter extends CustomPainter {
  const WardDashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashLength = 4.0,
    this.gapLength = 3.0,
    this.radius = 6.0,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    // Walk the path metric, emitting dash segments.
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        if (draw) {
          canvas.drawPath(
            metric.extractPath(distance, distance + length),
            paint,
          );
        }
        distance += length;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant WardDashedBorderPainter old) {
    return old.color != color ||
        old.strokeWidth != strokeWidth ||
        old.dashLength != dashLength ||
        old.gapLength != gapLength ||
        old.radius != radius;
  }
}

/// Convenience wrapper — applies a dashed border around [child] via
/// `CustomPaint.foregroundPainter`. Preserve the child's own padding /
/// background; the painter only strokes the outline.
class WardDashedBorder extends StatelessWidget {
  const WardDashedBorder({
    super.key,
    required this.child,
    this.color,
    this.strokeWidth = 1.0,
    this.dashLength = 4.0,
    this.gapLength = 3.0,
    this.radius = 6.0,
  });

  final Widget child;

  /// Border color. Defaults to `Theme.of(context).dividerColor` when null.
  final Color? color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: WardDashedBorderPainter(
        color: color ?? Theme.of(context).dividerColor,
        strokeWidth: strokeWidth,
        dashLength: dashLength,
        gapLength: gapLength,
        radius: radius,
      ),
      child: child,
    );
  }
}
