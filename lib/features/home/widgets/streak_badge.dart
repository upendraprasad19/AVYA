import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Pill-shaped badge showing the current streak count with fire icon.
///
/// Plays a subtle pulse animation (1.0 -> 1.1 -> 1.0, 300ms) once on build
/// to draw attention when the streak is non-zero.
class StreakBadge extends StatefulWidget {
  final int days;

  const StreakBadge({super.key, required this.days});

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_pulseController);

    // Fire pulse once if streak is non-zero.
    if (widget.days > 0) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _pulseController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant StreakBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pulse when streak value increases.
    if (widget.days > oldWidget.days && widget.days > 0) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.badge),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('\u{1F525}', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              '${widget.days}',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              widget.days == 1 ? 'day' : 'days',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
