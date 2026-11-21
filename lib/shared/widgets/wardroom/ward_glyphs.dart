import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Naval-officer glyph set — anchor, compass rose, officer chevrons,
/// circular seal, rank bar. Each glyph is a [CustomPainter] so they
/// render crisp at any size and cost zero bytes on disk.
///
/// The Wardroom voice leans on these shapes sparingly: an anchor next
/// to a screen eyebrow, a compass rose in the weekly report, a seal on
/// the workout receipt. Never layer more than two glyphs on one screen.

// ── Anchor ──────────────────────────────────────────────────────────────
class AnchorGlyph extends StatelessWidget {
  const AnchorGlyph({super.key, this.size = 14, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AnchorPainter(color: color ?? AppColors.accent),
    );
  }
}

class _AnchorPainter extends CustomPainter {
  _AnchorPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final unit = size.width / 24;
    final cx = size.width / 2;
    // Top ring
    canvas.drawCircle(Offset(cx, 4 * unit), 1.8 * unit, paint);
    // Shank
    canvas.drawLine(Offset(cx, 6 * unit), Offset(cx, 22 * unit), paint);
    // Stock
    canvas.drawLine(Offset(8 * unit, 10 * unit), Offset(16 * unit, 10 * unit),
        paint);
    // Flukes (arc)
    final arcRect = Rect.fromLTRB(5 * unit, 12 * unit, 19 * unit, 24 * unit);
    canvas.drawArc(arcRect, math.pi * 0.15, math.pi * 0.7, false, paint);
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => old.color != color;
}

// ── Compass rose ────────────────────────────────────────────────────────
class CompassRoseGlyph extends StatelessWidget {
  const CompassRoseGlyph({
    super.key,
    this.size = 120,
    this.bearingDegrees = 84,
    this.color,
    this.trackColor,
    this.textColor,
  });

  final double size;

  /// Rotation in degrees — 0 = north, clockwise positive.
  final double bearingDegrees;
  final Color? color;
  final Color? trackColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CompassPainter(
        bearing: bearingDegrees,
        color: color ?? AppColors.accent,
        track: trackColor ?? AppColors.textPrimary.withValues(alpha: 0.06),
        textColor: textColor ?? AppColors.textPrimary,
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.bearing,
    required this.color,
    required this.track,
    required this.textColor,
  });

  final double bearing;
  final Color color;
  final Color track;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final unit = size.width / 120;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = track;
    canvas.drawCircle(Offset(cx, cy), 58 * unit, trackPaint);
    canvas.drawCircle(Offset(cx, cy), 52 * unit, trackPaint);

    // 36 marks
    for (var i = 0; i < 36; i++) {
      final a = (i * 10) * math.pi / 180;
      final major = i % 9 == 0;
      final r1 = (major ? 46 : 52) * unit;
      final r2 = 58 * unit;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = major ? 1 : 0.5
        ..color = major ? color : track;
      canvas.drawLine(
        Offset(cx + r1 * math.sin(a), cy - r1 * math.cos(a)),
        Offset(cx + r2 * math.sin(a), cy - r2 * math.cos(a)),
        paint,
      );
    }

    // N / E / S / W
    const letters = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final a = i * 90 * math.pi / 180;
      final letter = letters[i];
      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: AppTypography.monoXs.copyWith(
            fontSize: 8 * unit,
            color: letter == 'N' ? color : textColor,
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cx + 40 * unit * math.sin(a) - tp.width / 2,
          cy - 40 * unit * math.cos(a) - tp.height / 2,
        ),
      );
    }

    // Needle
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(bearing * math.pi / 180);
    final needleUp = Path()
      ..moveTo(0, -46 * unit)
      ..lineTo(-3 * unit, 0)
      ..lineTo(0, -5 * unit)
      ..lineTo(3 * unit, 0)
      ..close();
    final needleDown = Path()
      ..moveTo(0, 46 * unit)
      ..lineTo(-3 * unit, 0)
      ..lineTo(0, 5 * unit)
      ..lineTo(3 * unit, 0)
      ..close();
    canvas.drawPath(needleUp, Paint()..color = color);
    canvas.drawPath(
      needleDown,
      Paint()..color = color.withValues(alpha: 0.3),
    );
    canvas.drawCircle(Offset.zero, 2.5 * unit, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.bearing != bearing ||
      old.color != color ||
      old.track != track ||
      old.textColor != textColor;
}

// ── Tier chevrons ───────────────────────────────────────────────────────
/// Officer stripes — 1-5 parallel bars of decreasing width. Used as a
/// rank indicator next to avatars, tier badges on the profile screen.
class TierChevronsGlyph extends StatelessWidget {
  const TierChevronsGlyph({
    super.key,
    required this.tier,
    this.color,
    this.width = 36,
  });

  final int tier;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final count = tier.clamp(0, 5);
    if (count == 0) return SizedBox(width: width);
    final paint = color ?? AppColors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: Container(
              height: 3,
              width: width * (1 - i * 0.12),
              decoration: BoxDecoration(
                color: paint,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Seal ────────────────────────────────────────────────────────────────
/// Circular stamp — double gold ring with mono label + date. Used on
/// the workout receipt card and weekly report hero.
class SealGlyph extends StatelessWidget {
  const SealGlyph({
    super.key,
    this.label = 'SEAL',
    required this.date,
    this.size = 64,
    this.color,
  });

  final String label;
  final String date;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: c.withValues(alpha: 0.33),
                width: 0.5,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTypography.monoXs.copyWith(
                  fontSize: 7,
                  color: c,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                date,
                style: AppTypography.mono.copyWith(
                  fontSize: 9,
                  color: c,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Rank bar ────────────────────────────────────────────────────────────
/// Heatmap-style single-cell row. Track + inline fill for leaderboard
/// positions (streak vs. personal best, category rank vs. peers).
class RankBarGlyph extends StatelessWidget {
  const RankBarGlyph({
    super.key,
    required this.value,
    this.max = 100,
    this.height = 3,
    this.color,
    this.trackColor,
    this.width,
  });

  final double value;
  final double max;
  final double height;
  final Color? color;
  final Color? trackColor;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final pct = (value / (max == 0 ? 1 : max)).clamp(0.0, 1.0).toDouble();
    final fill = color ?? AppColors.accent;
    final track = trackColor ?? AppColors.line2;
    final bar = SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          return Stack(
            children: [
              Container(width: c.maxWidth, height: height, color: track),
              Container(width: c.maxWidth * pct, height: height, color: fill),
            ],
          );
        },
      ),
    );
    return width == null ? bar : SizedBox(width: width, child: bar);
  }
}
