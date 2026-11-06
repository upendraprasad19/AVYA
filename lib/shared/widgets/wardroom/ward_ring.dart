import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Single progress ring — 6-px stroke, round cap, starts at 12 o'clock,
/// sweeps clockwise. Animates from 0 → [pct] over 600 ms ease-out on
/// mount, then tweens smoothly when [pct] changes afterwards. Optional
/// [child] centred inside the ring — typically a [WardBigNumber] or a
/// tier chevron.
class WardRing extends StatefulWidget {
  const WardRing({
    super.key,
    required this.pct,
    this.size = 72,
    this.stroke = 6,
    this.color,
    this.trackColor,
    this.child,
  });

  final double pct;
  final double size;
  final double stroke;
  final Color? color;
  final Color? trackColor;
  final Widget? child;

  @override
  State<WardRing> createState() => _WardRingState();
}

class _WardRingState extends State<WardRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(begin: 0, end: widget.pct.clamp(0.0, 1.0))
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(WardRing old) {
    super.didUpdateWidget(old);
    if (old.pct != widget.pct) {
      _anim = Tween<double>(
        begin: _anim.value,
        end: widget.pct.clamp(0.0, 1.0),
      ).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _RingPainter(
            pct: _anim.value,
            stroke: widget.stroke,
            color: widget.color ?? AppColors.accent,
            trackColor:
                widget.trackColor ?? AppColors.textPrimary.withValues(alpha: 0.08),
          ),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(child: widget.child),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.pct,
    required this.stroke,
    required this.color,
    required this.trackColor,
  });

  final double pct;
  final double stroke;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    if (pct <= 0) return;
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * pct;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.pct != pct ||
      old.stroke != stroke ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// Stacked concentric rings — one per channel (calories / protein /
/// water / sleep). Outer ring first in [rings]. Each entry takes a
/// percentage and a colour; the painter handles spacing.
class WardMultiRing extends StatelessWidget {
  const WardMultiRing({
    super.key,
    required this.rings,
    this.size = 120,
    this.stroke = 5,
    this.gap = 8,
    this.child,
  });

  final List<WardRingData> rings;
  final double size;
  final double stroke;
  final double gap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < rings.length; i++)
            WardRing(
              pct: rings[i].pct,
              size: size - i * (stroke + gap) * 2,
              stroke: stroke,
              color: rings[i].color,
            ),
          ?child,
        ],
      ),
    );
  }
}

class WardRingData {
  const WardRingData({required this.pct, required this.color});
  final double pct;
  final Color color;
}
