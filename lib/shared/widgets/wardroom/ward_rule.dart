import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Horizontal rule — single neutral hairline by default, double gold
/// hairline for letterhead boundaries / major section starts.
///
/// Usage:
/// * `WardRule()` — neutral `line2` hairline (1 px).
/// * `WardRule(double: true)` — double gold (1 px + 1 px with 2 px gap).
/// * `WardRule(gold: true)` — single gold hairline. Reserved for hero
///   dividers and section kickers; never as a card border.
class WardRule extends StatelessWidget {
  const WardRule({
    super.key,
    this.doubleRule = false,
    this.gold = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 22),
  });

  final bool doubleRule;
  final bool gold;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    if (doubleRule) {
      return Padding(
        padding: margin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: AppColors.accent.withValues(alpha: 0.6)),
            const SizedBox(height: 2),
            Container(height: 1, color: AppColors.accent.withValues(alpha: 0.3)),
          ],
        ),
      );
    }
    return Padding(
      padding: margin,
      child: Container(
        height: 1,
        color: gold ? AppColors.line : AppColors.line2,
      ),
    );
  }
}
