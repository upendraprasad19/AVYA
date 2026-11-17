// lib/features/nutrition/widgets/diet_plan_settings_row.dart
//
// Diet chart layout v2 (docs/plans/diet-layout-v2.md section 3.4): the ONE row
// of three controls right under the title, so the calorie block and the diet
// start straight after it: food type (dropdown), diet strategy (dropdown) and
// Supplements (on/off). A control whose feature flag is off, or a Supplements
// column a minor must not see, is left out and the others share the row. The
// hints the controls can show (the Keto note, the paused hints, the
// birth-date hint) sit under the row, full width.
//
// Each control ends in the same write door as before (`_changeFoodType` on the
// screen, `handleDietStrategyTap`, `handleDietSupplementsToggle`); this widget
// only places them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import '../services/diet_strategy_flags.dart';
import '../services/diet_supplements_flags.dart';
import 'diet_plan_dropdown.dart';
import 'diet_strategy_section.dart';
import 'diet_supplements_section.dart';

class DietPlanSettingsRow extends ConsumerWidget {
  const DietPlanSettingsRow({
    super.key,
    required this.foodType,
    required this.foodTypeEnabled,
    required this.onFoodType,
  });

  final FoodType foodType;

  /// False while a food-type change is being saved.
  final bool foodTypeEnabled;
  final ValueChanged<FoodType> onFoodType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strategy = DietStrategyFlags.enabled;
    final supplements =
        DietSupplementsFlags.enabled && dietSupplementsColumnShown(ref);
    final columns = <Widget>[
      DietPlanDropdown<FoodType>(
        label: 'Food type',
        fieldKey: const ValueKey('diet_plan_food_type_dropdown'),
        value: foodType,
        enabled: foodTypeEnabled,
        onChanged: onFoodType,
        options: [
          for (final t in FoodType.values)
            DietPlanDropdownOption<FoodType>(
              value: t,
              label: t.label,
              itemKey: ValueKey('food_type_chip_${t.storageKey}'),
            ),
        ],
      ),
      if (strategy) const DietStrategyField(),
      if (supplements) const DietSupplementsField(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: columns[i]),
            ],
          ],
        ),
        if (strategy) const DietStrategyFootnotes(),
        if (DietSupplementsFlags.enabled) const DietSupplementsFootnotes(),
      ],
    );
  }
}
