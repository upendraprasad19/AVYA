// lib/features/nutrition/widgets/diet_plan_dropdown.dart
//
// Diet chart layout v2 (docs/plans/diet-layout-v2.md section 3.1): the labelled
// dropdown the Diet chart screen uses for the food type and the diet strategy.
// One small label, one 44 dp field in the app's input colours; the OPEN menu
// lists every option (an option can be disabled and can carry a PRO badge),
// the closed field shows the selected option's short text.
//
// It only reports the tap: the caller owns the write (a strategy tap may open
// the paywall or a confirm dialog and leave the shown value as it was, which
// a controlled `value` handles).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// One entry of a [DietPlanDropdown].
class DietPlanDropdownOption<T> {
  const DietPlanDropdownOption({
    required this.value,
    required this.label,
    required this.itemKey,
    this.enabled = true,
    this.badge,
    this.badgeKey,
  });

  final T value;

  /// The text in the open menu and in the closed field.
  final String label;

  /// Key of the menu item (the old chip keys, so the pins stay valid).
  final Key itemKey;

  /// False: shown greyed in the menu and not selectable.
  final bool enabled;

  /// A small tag after the label in the menu (`PRO`).
  final String? badge;
  final Key? badgeKey;
}

class DietPlanDropdown<T> extends StatelessWidget {
  const DietPlanDropdown({
    super.key,
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  /// The small caption above the field.
  final String label;

  /// Key of the field (the closed control).
  final Key fieldKey;

  final T value;
  final List<DietPlanDropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  /// False while a change is being saved: the field is shown and ignores taps.
  final bool enabled;

  /// Minimum touch-target height (accessibility).
  static const double fieldHeight = 44;

  @override
  Widget build(BuildContext context) {
    final text = AppTypography.body.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body
                .copyWith(fontSize: 12, color: AppColors.textDim)),
        const SizedBox(height: 6),
        Container(
          key: fieldKey,
          constraints: const BoxConstraints(minHeight: fieldHeight),
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.soft),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              itemHeight: 48,
              dropdownColor: AppColors.card,
              iconEnabledColor: AppColors.textDim,
              iconDisabledColor: AppColors.textDisabled,
              style: text,
              onChanged: enabled
                  ? (v) {
                      if (v != null && v != value) onChanged(v);
                    }
                  : null,
              selectedItemBuilder: (_) => [
                for (final o in options)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(o.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
                  ),
              ],
              items: [
                for (final o in options)
                  DropdownMenuItem<T>(
                    key: o.itemKey,
                    value: o.value,
                    enabled: o.enabled,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            o.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.copyWith(
                              fontWeight: o.value == value
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: !o.enabled
                                  ? AppColors.textDisabled
                                  : o.value == value
                                      ? AppColors.accent
                                      : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (o.badge != null && o.enabled) ...[
                          const SizedBox(width: 6),
                          Text(
                            o.badge!,
                            key: o.badgeKey,
                            style: AppTypography.monoXs.copyWith(
                                fontSize: 9,
                                letterSpacing: 1.2,
                                color: AppColors.accent),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
