// lib/shared/widgets/diet_strategy_chips.dart
//
// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §3.6): the ONE
// diet-strategy selector, used by the Diet Plan screen and Edit Profile so the
// two cannot offer different choices. Same selectable pill as
// [FoodTypeChips]. Low carb and Keto carry a PRO badge for a free user;
// Balanced is always selectable. The PRO gate itself is the caller's
// (`gateAndVerify`); this widget only reports the tap.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class DietStrategyChips extends StatelessWidget {
  const DietStrategyChips({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isPro,
    this.enabled = true,
  });

  /// The EFFECTIVE strategy (the one the shown targets were made for).
  final DietStrategy value;
  final ValueChanged<DietStrategy> onChanged;

  /// False shows a PRO badge on Low carb and Keto.
  final bool isPro;

  /// False while a change is being saved; taps are ignored.
  final bool enabled;

  static const double minChipHeight = 44;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in DietStrategy.values) _chip(s),
      ],
    );
  }

  Widget _chip(DietStrategy s) {
    final isSelected = s == value;
    final locked = !isPro && s != DietStrategy.balanced;
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: locked ? '${s.label}, PRO' : s.label,
      onTap: enabled ? () => onChanged(s) : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('diet_strategy_chip_${s.storageKey}'),
        onTap: enabled ? () => onChanged(s) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: minChipHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentTint : AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.label,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color:
                      isSelected ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 6),
                Text(
                  'PRO',
                  key: ValueKey('diet_strategy_pro_badge_${s.storageKey}'),
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
