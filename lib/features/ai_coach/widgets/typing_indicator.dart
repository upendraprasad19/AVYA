import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// 3-dot typing animation. Used between Captain's induction messages
/// (Plan B / B4) and anywhere else the coach needs a "thinking" pause.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 12,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            children: List.generate(3, (i) {
              final t = (_ctrl.value + i / 3) % 1.0;
              final opacity = (0.3 + 0.7 * (1 - (t * 2 - 1).abs())).clamp(0.3, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
