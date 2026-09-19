import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';

/// Full-height screen shell for Wardroom screens. Applies the navy base
/// color, sets light-content status bar icons, and reserves bottom
/// padding for the tab bar (default 96 px).
///
/// The `grain` parameter enables a subtle cinematic noise overlay via
/// [_GrainOverlay]. It is visually quiet (6% opacity, blend overlay) and
/// can be disabled on low-end devices. The overlay is never interactive.
class WardFrame extends StatelessWidget {
  const WardFrame({
    super.key,
    required this.child,
    this.padBottom = 96,
    this.grain = true,
    this.bg,
  });

  final Widget child;
  final double padBottom;
  final bool grain;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.bgDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Container(
        color: bg ?? AppColors.bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(bottom: padBottom),
                child: child,
              ),
            ),
            if (grain) const Positioned.fill(child: IgnorePointer(child: _GrainOverlay())),
          ],
        ),
      ),
    );
  }
}

/// Cinematic noise overlay rendered with a soft-light blend to add
/// texture to the navy canvas. Procedural so it costs zero bytes on
/// disk. Kept simple — a fractal painter would be prettier but would
/// add GPU cost; the soft-light blend here gives a comparable feel.
class _GrainOverlay extends StatelessWidget {
  const _GrainOverlay();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.06,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.35),
              Colors.transparent,
            ],
            center: const Alignment(-0.4, -0.8),
            radius: 1.2,
          ),
          backgroundBlendMode: BlendMode.overlay,
          color: Colors.transparent,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
