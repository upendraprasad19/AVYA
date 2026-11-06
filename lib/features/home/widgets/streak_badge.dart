import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Streak badge — matches the handoff header combined pill
/// (`design_handoff_wardroom/src/screens/daily.jsx` lines 32–43).
///
/// Single pill with `cardHi` bg and a 27% gold border; shows a small
/// gold dot, the streak number in gold, "DAYS" caps, a 1-px neutral
/// divider, a snowflake glyph, and the freeze count as `available/max`
/// in `info`. Sharp `radPill` corners.
///
/// Pulses once on mount when `days > 0` and re-pulses when the streak
/// increases via `didUpdateWidget`.
///
/// APK Test #14 / Bug D.3 — freeze display switched from `❄ <available>`
/// (single digit) to `❄ <available>/<max>` so users see capacity, not
/// just remaining count. A free user sees `❄ 1/1`; a PRO user with two
/// burnt mid-week sees `❄ 1/3`. `freezesMax` defaults to 1 (free max)
/// for back-compat with callsites that haven't been updated yet.
class StreakBadge extends StatefulWidget {
  final int days;
  final int freezesAvailable;
  final int freezesMax;

  const StreakBadge({
    super.key,
    required this.days,
    this.freezesAvailable = 0,
    this.freezesMax = 1,
  });

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

    if (widget.days > 0) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _pulseController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant StreakBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final freezeColor = widget.freezesAvailable > 0
        ? AppColors.info
        : AppColors.textDisabled;

    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardHi,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.27),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Fire emoji — color-emoji carries its own color; AppColors.accent
            // tint does not apply. Size bumped to 12 to read balanced against
            // the 11px streak number.
            const Text(
              '\u{1F525}',
              style: TextStyle(fontSize: 12, height: 1),
            ),
            const SizedBox(width: 4),
            Text(
              '${widget.days}',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              widget.days == 1 ? 'DAY' : 'DAYS',
              style: AppTypography.monoXs.copyWith(
                fontSize: 8,
                color: AppColors.textDim,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Divider.
            Container(
              width: 1,
              height: 10,
              color: AppColors.line2,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
            // Snowflake.
            Text(
              '\u2744',
              style: TextStyle(fontSize: 10, color: freezeColor, height: 1),
            ),
            const SizedBox(width: 3),
            Text(
              '${widget.freezesAvailable}/${widget.freezesMax}',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: freezeColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
