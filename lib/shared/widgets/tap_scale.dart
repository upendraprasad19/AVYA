import 'package:flutter/material.dart';

/// Wraps a child widget with a subtle scale-down effect on tap.
///
/// On tap down, scales to [scaleEnd] (default 0.98) over 100ms.
/// On tap up / cancel, scales back to 1.0.
/// Fires [onTap] on tap up.
class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleEnd;
  final Duration duration;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleEnd = 0.98,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _scale = widget.scaleEnd);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _scale = 1.0);
    widget.onTap?.call();
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        duration: widget.duration,
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}
