// lib/shared/widgets/wardroom/ward_rank_insignia.dart
//
// Indian Navy rank insignia rendered via CustomPaint. One widget,
// 11 painters, dispatched by `rankCode`.
//
// Sizes:
//   24dp — used inside WardRankPill (top of Profile)
//   48dp — used inside Service Record popups + ladder detail sheets
//   16dp — used inside compact RankChip variants (existing widget)
//
// All shapes drawn with `AppColors.accent` (Campaign Gold) by default.
// Pass `color:` to override (e.g. dimmed past-rank rows).
//
// Source: docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md §7.3.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class WardRankInsignia extends StatelessWidget {
  const WardRankInsignia({
    super.key,
    required this.rankCode,
    required this.size,
    this.color,
  });

  final String rankCode;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final paint = color ?? AppColors.accent;

    final painter = _painterForCode(rankCode, paint);
    if (painter == null) {
      // Fallback: text-only label inside a gold-ringed circle.
      return _TextFallback(rankCode: rankCode, size: size, color: paint);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: painter),
    );
  }

  CustomPainter? _painterForCode(String code, Color color) {
    switch (code) {
      case 'SD2':
        // Text-only fallback (no military insignia for entry rank).
        return null;
      case 'SD1':
        return _ChevronPainter(color: color);
      case 'LS':
        return _AnchorPainter(color: color);
      case 'PO':
        return _AnchorWithCrownPainter(color: color);
      case 'CPO':
        return _CrossedAnchorsPainter(color: color);
      case 'MCPO':
        return _CrownStarCrossedAnchorsPainter(color: color);
      case 'SubLt':
        return _StripePainter(
            color: color, thickStripes: 0, thinStripes: 1, curl: true);
      case 'Lt':
        return _StripePainter(
            color: color, thickStripes: 2, thinStripes: 0, curl: false);
      case 'LtCdr':
        return _StripePainter(
            color: color, thickStripes: 2, thinStripes: 1, curl: false);
      case 'Cdr':
        return _StripePainter(
            color: color, thickStripes: 3, thinStripes: 0, curl: false);
      case 'Capt':
        return _StripePainter(
            color: color, thickStripes: 4, thinStripes: 0, curl: false);
      default:
        return null;
    }
  }
}

// ── Text fallback (used by SD2 + unknown codes) ──────────────────

class _TextFallback extends StatelessWidget {
  const _TextFallback({
    required this.rankCode,
    required this.size,
    required this.color,
  });

  final String rankCode;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.2),
        ),
        child: Center(
          child: Text(
            rankCode.toUpperCase(),
            style: AppTypography.mono.copyWith(
              fontSize: size * 0.32,
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chevron (SD1) ────────────────────────────────────────────────

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.18, h * 0.62)
      ..lineTo(w * 0.50, h * 0.30)
      ..lineTo(w * 0.82, h * 0.62);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

// ── Anchor (LS) ──────────────────────────────────────────────────

class _AnchorPainter extends CustomPainter {
  _AnchorPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _drawAnchor(canvas, size, color, scale: 1.0, offsetY: 0);
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => old.color != color;
}

void _drawAnchor(Canvas canvas, Size size, Color color,
    {required double scale, required double offsetY}) {
  final stroke = Paint()
    ..color = color
    ..strokeWidth = size.width * 0.08 * scale
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  final w = size.width;
  final h = size.height;
  final cx = w * 0.5;
  final topY = h * (0.18 + offsetY);
  final shankBottomY = h * (0.66 + offsetY);
  final crownY = h * (0.82 + offsetY);

  // Crown ring at top
  final ringR = w * 0.08 * scale;
  canvas.drawCircle(Offset(cx, topY), ringR, stroke);

  // Shank
  canvas.drawLine(Offset(cx, topY + ringR), Offset(cx, shankBottomY), stroke);

  // Stock (horizontal crossbar)
  final stockHalf = w * 0.18 * scale;
  final stockY = h * (0.32 + offsetY);
  canvas.drawLine(
      Offset(cx - stockHalf, stockY), Offset(cx + stockHalf, stockY), stroke);

  // Crown (curved arms)
  final armHalf = w * 0.26 * scale;
  final armPath = Path()
    ..moveTo(cx - armHalf, shankBottomY)
    ..quadraticBezierTo(
        cx - armHalf * 0.6, crownY, cx, shankBottomY + h * 0.04 * scale)
    ..quadraticBezierTo(cx + armHalf * 0.6, crownY, cx + armHalf, shankBottomY)
    ..close();
  canvas.drawPath(armPath, fill);
}

// ── Anchor + Crown (PO) ──────────────────────────────────────────

class _AnchorWithCrownPainter extends CustomPainter {
  _AnchorWithCrownPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Crown above
    _drawCrown(canvas, size, color,
        cx: size.width * 0.5,
        cy: size.height * 0.16,
        width: size.width * 0.32);
    // Anchor below — shrunk to 80% so they fit together at 24dp
    _drawAnchor(canvas, size, color, scale: 0.78, offsetY: 0.12);
  }

  @override
  bool shouldRepaint(_AnchorWithCrownPainter old) => old.color != color;
}

void _drawCrown(Canvas canvas, Size size, Color color,
    {required double cx, required double cy, required double width}) {
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  final halfW = width / 2;
  final h = width * 0.55;

  // Three arches with small balls on top.
  final base = Path()
    ..moveTo(cx - halfW, cy + h * 0.4)
    ..lineTo(cx + halfW, cy + h * 0.4)
    ..lineTo(cx + halfW, cy + h * 0.55)
    ..lineTo(cx - halfW, cy + h * 0.55)
    ..close();
  canvas.drawPath(base, fill);

  // Three small balls on top (jewels).
  final ballR = width * 0.07;
  canvas.drawCircle(Offset(cx - halfW * 0.7, cy - h * 0.05), ballR, fill);
  canvas.drawCircle(Offset(cx, cy - h * 0.18), ballR * 1.1, fill);
  canvas.drawCircle(Offset(cx + halfW * 0.7, cy - h * 0.05), ballR, fill);

  // Connect balls to base with thin lines.
  final stroke = Paint()
    ..color = color
    ..strokeWidth = width * 0.06
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(cx - halfW * 0.7, cy - h * 0.05),
      Offset(cx - halfW * 0.6, cy + h * 0.4), stroke);
  canvas.drawLine(Offset(cx, cy - h * 0.18), Offset(cx, cy + h * 0.4), stroke);
  canvas.drawLine(Offset(cx + halfW * 0.7, cy - h * 0.05),
      Offset(cx + halfW * 0.6, cy + h * 0.4), stroke);
}

// ── Crossed Anchors (CPO) ────────────────────────────────────────

class _CrossedAnchorsPainter extends CustomPainter {
  _CrossedAnchorsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // First anchor rotated -25°
    canvas.save();
    canvas.rotate(-0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();

    // Second anchor rotated +25°
    canvas.save();
    canvas.rotate(0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrossedAnchorsPainter old) => old.color != color;
}

// ── Crown + Star + Crossed Anchors (MCPO) ────────────────────────

class _CrownStarCrossedAnchorsPainter extends CustomPainter {
  _CrownStarCrossedAnchorsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Star at very top
    _drawStar(canvas, color,
        cx: size.width * 0.5,
        cy: size.height * 0.1,
        radius: size.width * 0.08);

    // Crown below star
    _drawCrown(canvas, size, color,
        cx: size.width * 0.5,
        cy: size.height * 0.26,
        width: size.width * 0.28);

    // Crossed anchors below crown — shrunk + offset down
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.62);
    canvas.scale(0.7);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.save();
    canvas.rotate(-0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();
    canvas.save();
    canvas.rotate(0.436);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawAnchor(canvas, size, color, scale: 0.85, offsetY: 0);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrownStarCrossedAnchorsPainter old) => old.color != color;
}

void _drawStar(Canvas canvas, Color color,
    {required double cx, required double cy, required double radius}) {
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final angle = (i * 36 - 90) * math.pi / 180;
    final r = i.isEven ? radius : radius * 0.45;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  canvas.drawPath(path, fill);
}

// ── Stripes (officer ranks: SubLt / Lt / LtCdr / Cdr / Capt) ─────

class _StripePainter extends CustomPainter {
  _StripePainter({
    required this.color,
    required this.thickStripes,
    required this.thinStripes,
    required this.curl,
  });

  final Color color;
  final int thickStripes;
  final int thinStripes;
  final bool curl; // SubLt — small loop above the topmost stripe

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Layout: stripes stack vertically inside a "shoulder board" rectangle
    // that occupies the central 80% of the box. Thick = h*0.10, thin = h*0.05,
    // gap = h*0.04 between stripes.
    const thickH = 0.10;
    const thinH = 0.05;
    const gap = 0.04;

    final totalStripes = thickStripes + thinStripes;
    final totalH = thickStripes * thickH +
        thinStripes * thinH +
        (totalStripes - 1).clamp(0, totalStripes) * gap;
    const centerY = 0.5;
    var y = centerY - totalH / 2;

    for (var i = 0; i < thickStripes; i++) {
      final rect = Rect.fromLTWH(w * 0.15, h * y, w * 0.70, h * thickH);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h * 0.012)), fill);
      y += thickH + gap;
    }
    for (var i = 0; i < thinStripes; i++) {
      final rect = Rect.fromLTWH(w * 0.18, h * y, w * 0.64, h * thinH);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h * 0.008)), fill);
      y += thinH + gap;
    }

    if (curl) {
      // Small loop above the (single) thin stripe — Sub-Lieutenant detail.
      final loopCenter =
          Offset(w * 0.5, h * (centerY - thinH / 2 - gap - 0.04));
      final loopR = h * 0.05;
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.02;
      canvas.drawCircle(loopCenter, loopR, stroke);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) =>
      old.color != color ||
      old.thickStripes != thickStripes ||
      old.thinStripes != thinStripes ||
      old.curl != curl;
}
