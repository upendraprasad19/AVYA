import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';

/// Quick-action state that drives visual treatment.
enum QuickActionState {
  /// Default: cyan border, cyan icon — action not yet done.
  idle,

  /// Action completed: emerald tint background, emerald icon.
  completed,

  /// Rest day: muted cyan appearance — "nothing to do, you're good".
  restDay,
}

/// Compact quick action card on the Home dashboard.
///
/// Supports:
/// - **Completion state** — turns emerald tint when [state] is [QuickActionState.completed].
/// - **Optional progress bar** on the right edge — driven by [progress] (0.0–1.0).
///   Bar color transitions: [progressColor] while in progress → emerald when
///   [progress] >= 1.0 (target met).
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final QuickActionState state;

  /// Optional 0.0–1.0 progress shown as a vertical bar on the right edge.
  /// null = no bar shown.
  final double? progress;

  /// Bar color while target not yet met. Defaults to accent cyan.
  final Color progressColor;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.state = QuickActionState.idle,
    this.progress,
    this.progressColor = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = state == QuickActionState.completed;
    final isRest = state == QuickActionState.restDay;
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final Color labelColor;

    if (isDone) {
      bgColor = AppColors.emeraldTint;
      borderColor = AppColors.emerald.withValues(alpha: 0.28);
      iconColor = AppColors.emerald;
      labelColor = AppColors.emerald;
    } else if (isRest) {
      bgColor = AppColors.accentTint;
      borderColor = AppColors.accent.withValues(alpha: 0.18);
      iconColor = AppColors.accent.withValues(alpha: 0.5);
      labelColor = AppColors.accent.withValues(alpha: 0.5);
    } else {
      bgColor = AppColors.card;
      borderColor = AppColors.border;
      iconColor = AppColors.textSecondary;
      labelColor = AppColors.textSecondary;
    }

    return Expanded(
      child: TapScale(
        onTap: onTap,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Main content: icon + label
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRest ? Icons.check_circle_outline : icon,
                      size: 17,
                      color: iconColor,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isRest ? 'Rest' : label,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: labelColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Progress bar on right edge
              if (progress != null)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _VerticalProgressBar(
                    progress: progress!.clamp(0.0, 1.0),
                    color: progress! >= 1.0 ? AppColors.emerald : progressColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin vertical progress bar that fills bottom-to-top.
class _VerticalProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _VerticalProgressBar({
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barHeight = constraints.maxHeight * progress;
          return Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              width: 3,
              height: barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
