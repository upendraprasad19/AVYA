// lib/features/nutrition/widgets/food_type_tag.dart
//
// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md §2.3.5): the
// food-type tag on the Nutrition calorie card ("NON-VEG"), so the user sees
// which food type the targets and the diet plan follow. Unit 3a appends the
// diet strategy (" · KETO") from [strategy], the strategy carried WITH the
// card's numbers (DailyNutritionData.strategy), never read from the profile
// here (docs/plans/diet-strategy.md §3.7). Tapping it opens the Diet Plan
// screen.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class FoodTypeTag extends StatelessWidget {
  const FoodTypeTag({
    super.key,
    required this.profile,
    required this.onTap,
    this.strategy = DietStrategy.balanced,
  });

  final Map<String, dynamic> profile;
  final VoidCallback onTap;

  /// The strategy the shown targets were made for. Balanced adds nothing.
  final DietStrategy strategy;

  @override
  Widget build(BuildContext context) {
    final type = foodTypeOfProfile(profile);
    return Semantics(
      button: true,
      label: strategy == DietStrategy.balanced
          ? 'Food type ${type.label}. Open the diet plan'
          : 'Food type ${type.label}, ${strategy.label}. Open the diet plan',
      // excludeSemantics drops the GestureDetector's tap action: carry it here.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('nutrition_food_type_tag'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          withDietStrategyTag(type.shortLabel, strategy),
          overflow: TextOverflow.ellipsis,
          style: AppTypography.monoXs.copyWith(
            fontSize: 9,
            letterSpacing: 1.5,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
