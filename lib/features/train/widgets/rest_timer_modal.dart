import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import '../providers/train_provider.dart';

/// Full-screen overlay rest timer modal matching the mockup:
/// - Blurred/dark background
/// - Centered card with "REST TIMER" title, next exercise name
/// - Circular countdown ring (130px) with color transitions
/// - "Skip Rest" button + "+15s more rest" link
class RestTimerModal extends StatelessWidget {
  final RestTimerData restTimer;
  final VoidCallback onSkip;
  final VoidCallback onAddTime;

  const RestTimerModal({
    super.key,
    required this.restTimer,
    required this.onSkip,
    required this.onAddTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
          decoration: BoxDecoration(
            color: const Color(0xFF0e1219),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                'REST TIMER',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 5),

              // Next exercise
              Text(
                'Next: ${restTimer.nextExerciseName}',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),

              // Circular countdown ring
              SizedBox(
                width: 130,
                height: 130,
                child: CustomPaint(
                  painter: _RestRingPainter(
                    progress: restTimer.progress,
                    color: restTimer.timerColor,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${restTimer.secondsRemaining}',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: restTimer.timerColor,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'seconds',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Tip text
              Text(
                'Stay loose. Sip some water.\nNext set target: keep form tight.',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 18),

              // Skip Rest button
              GestureDetector(
                onTap: onSkip,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Center(
                    child: Text(
                      'Skip Rest \u2192',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),

              // +15s link
              GestureDetector(
                onTap: onAddTime,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '+ 15s more rest',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the circular countdown ring.
class _RestRingPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0 (remaining fraction)
  final Color color;

  _RestRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 52.0; // match mockup r=52 for 130px ring
    const strokeWidth = 10.0;

    // Track
    final trackPaint = Paint()
      ..color = const Color(0xFF161d28)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Fill arc
    final fillPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RestRingPainter old) =>
      old.progress != progress || old.color != color;
}
