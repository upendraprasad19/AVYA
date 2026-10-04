import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';

/// Quick-action state that drives visual treatment.
enum QuickActionState {
  /// Default: parchment-dim icon + mono label on navy card — action pending.
  idle,

  /// Action completed: ok-green tint + green icon/label.
  completed,

  /// Rest day: muted gold — "nothing to do, you're good".
  restDay,
}

/// Wardroom quick-action card on the Home dashboard.
///
/// Renders as a short, sharp-cornered (4-px) navy tile with a mono
/// uppercase label under the icon. Completion flips to a green-tinted
/// surface. Rest day dims into the gold family.
///
/// Supports an optional 0–1 [progress] rendered as a 3-px vertical bar
/// on the right edge — fills bottom-to-top and switches to ok-green once
/// target is met.
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final QuickActionState state;

  /// Optional 0.0–1.0 progress shown as a vertical bar on the right edge.
  /// null = no bar shown.
  final double? progress;

  /// Bar color while target not yet met. Defaults to Campaign Gold.
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
      bgColor = AppColors.ok.withValues(alpha: 0.10);
      borderColor = AppColors.ok.withValues(alpha: 0.33);
      iconColor = AppColors.ok;
      labelColor = AppColors.ok;
    } else if (isRest) {
      bgColor = AppColors.accentSoft;
      borderColor = AppColors.accent.withValues(alpha: 0.22);
      iconColor = AppColors.accent.withValues(alpha: 0.55);
      labelColor = AppColors.accent.withValues(alpha: 0.55);
    } else {
      bgColor = AppColors.card;
      borderColor = AppColors.line2;
      iconColor = AppColors.textDim;
      labelColor = AppColors.textDim;
    }

    return Expanded(
      child: TapScale(
        onTap: onTap,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: bgColor,
            // Sharp Wardroom corners — 4 px, not 11.
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Thin gold top rule — flagship Wardroom motif, only on idle.
              if (!isDone && !isRest)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    height: 1,
                    color: AppColors.accent.withValues(alpha: 0.27),
                  ),
                ),

              // Main content: icon + mono uppercase label
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRest ? Icons.check_circle_outline : icon,
                      size: 17,
                      color: iconColor,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (isRest ? 'REST' : label).toUpperCase(),
                      style: AppTypography.monoXs.copyWith(
                        color: labelColor,
                        letterSpacing: 1.8,
                        height: 1.0,
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
                    color: progress! >= 1.0 ? AppColors.ok : progressColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin vertical progress bar that fills bottom-to-top. Wardroom keeps
/// sharp edges — no rounding on the bar itself.
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
              curve: Curves.easeOutCubic,
              width: 3,
              height: barHeight,
              color: color,
            ),
          );
        },
      ),
    );
  }
}
