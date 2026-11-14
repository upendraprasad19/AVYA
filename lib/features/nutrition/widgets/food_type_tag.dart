// lib/features/nutrition/widgets/food_type_tag.dart
//
// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md §2.3.5): the
// food-type tag on the Nutrition calorie card ("NON-VEG"), so the user sees
// which food type the targets and the diet plan follow. Unit 3 appends the
// diet strategy (" · KETO"). Tapping it opens the Diet Plan screen.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class FoodTypeTag extends StatelessWidget {
  const FoodTypeTag({super.key, required this.profile, required this.onTap});

  final Map<String, dynamic> profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = foodTypeOfProfile(profile);
    return Semantics(
      button: true,
      label: 'Food type ${type.label}. Open the diet plan',
      // excludeSemantics drops the GestureDetector's tap action: carry it here.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('nutrition_food_type_tag'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          type.shortLabel,
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
