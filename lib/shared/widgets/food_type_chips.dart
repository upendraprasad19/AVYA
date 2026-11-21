// lib/shared/widgets/food_type_chips.dart
//
// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md §2.2.3): the ONE
// food-type selector, used by Edit Profile and the Diet Plan screen so the two
// cannot offer different choices.
//
// Style: Edit Profile's existing selectable pill, moved here verbatim (its
// sibling selectors, goal and injuries, use the same pill). The Wardroom
// `WardChip` is a status pill (9 px mono caps, `filled` reserved for the one
// most-important chip on a screen), not a selector, so it is not used here.
// Every chip is at least 44 dp tall and announces itself as a selected or
// unselected button.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class FoodTypeChips extends StatelessWidget {
  const FoodTypeChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final FoodType value;
  final ValueChanged<FoodType> onChanged;

  /// False while a change is being saved; taps are ignored.
  final bool enabled;

  /// Minimum touch-target height (accessibility).
  static const double minChipHeight = 44;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in FoodType.values) _chip(type),
      ],
    );
  }

  Widget _chip(FoodType type) {
    final isSelected = type == value;
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: type.label,
      // excludeSemantics drops the GestureDetector's own tap action, so the
      // node carries it itself (a button a screen reader cannot press is the
      // failure this guards; T4 pins hasTapAction).
      onTap: enabled ? () => onChanged(type) : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('food_type_chip_${type.storageKey}'),
        onTap: enabled ? () => onChanged(type) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // No `alignment` here: in a Wrap it would stretch the chip across
          // the row. The Center below hugs the label and centres it inside
          // the minimum height.
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
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              type.label,
              style: AppTypography.body.copyWith(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? AppColors.accent : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
