import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Sharp 2-px accentSoft slab showing the current streak count with fire
/// icon. Fraunces h3 number + Mono "DAY"/"DAYS" caps + freeze counter.
///
/// Plays a subtle pulse animation (1.0 -> 1.1 -> 1.0, 300ms) once on build
/// to draw attention when the streak is non-zero.
class StreakBadge extends StatefulWidget {
  final int days;
  final int freezesAvailable;

  const StreakBadge(
      {super.key, required this.days, this.freezesAvailable = 0});

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.33),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('\u{1F525}', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              '${widget.days}',
              style: AppTypography.h3.copyWith(
                color: AppColors.accent,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              widget.days == 1 ? 'DAY' : 'DAYS',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
              ),
            ),
            // Streak freeze indicator
            const SizedBox(width: 8),
            Text(
              '\u{2744}\uFE0F', // ❄️
              style: TextStyle(
                fontSize: 11,
                color: widget.freezesAvailable > 0
                    ? AppColors.info
                    : AppColors.textDisabled,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '${widget.freezesAvailable}',
              style: AppTypography.mono.copyWith(
                color: widget.freezesAvailable > 0
                    ? AppColors.info
                    : AppColors.textDisabled,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
