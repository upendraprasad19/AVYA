import 'package:flutter/material.dart';

/// Animates a numeric value from 0 to [value] using TweenAnimationBuilder.
///
/// The animation runs for [duration] (default 500ms) with [curve] (default easeOut).
/// The [builder] callback receives the current animated double value.
class AnimatedCounter extends StatelessWidget {
  final double value;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double value, Widget? child)
      builder;

  const AnimatedCounter({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 500),
    this.curve = Curves.easeOut,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: curve,
      builder: builder,
    );
  }
}
