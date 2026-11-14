// lib/shared/widgets/diet_strategy_notes.dart
//
// Diet plan Unit 3b (docs/plans/diet-strategy-3b.md §3.5, §3.8): the lines
// under the strategy chips, shared by the Diet Plan screen and Edit Profile
// so both say the same thing: the reason the Keto chip is off for a Vegan
// food type, and the Keto medical note while Keto is selected.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// The strategies the chips do not offer for [foodType] (Keto for Vegan).
Set<DietStrategy> dietStrategiesDisabledFor(FoodType foodType) =>
    foodType == FoodType.vegan ? const {DietStrategy.keto} : const {};

class DietStrategyNotes extends StatelessWidget {
  const DietStrategyNotes({
    super.key,
    required this.foodType,
    required this.selected,
  });

  /// The food type the chips are shown for (Edit Profile: the FORM's).
  final FoodType foodType;

  /// The selected chip.
  final DietStrategy selected;

  @override
  Widget build(BuildContext context) {
    final dim =
        AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dietStrategiesDisabledFor(foodType).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(kVeganKetoChipReason,
              key: const ValueKey('diet_strategy_vegan_keto_reason'),
              style: dim),
        ],
        if (selected == DietStrategy.keto) ...[
          const SizedBox(height: 8),
          Text(kKetoMedicalNote,
              key: const ValueKey('diet_strategy_keto_medical_note'),
              style: dim),
        ],
      ],
    );
  }
}
