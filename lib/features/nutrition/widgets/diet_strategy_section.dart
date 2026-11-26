// lib/features/nutrition/widgets/diet_strategy_section.dart
//
// Diet plan Unit 3a (docs/plans/diet-strategy.md §3.5-§3.8): the Diet Plan
// screen's strategy control. Since layout v2 (docs/plans/diet-layout-v2.md
// §3.2) it is a dropdown column in the screen's settings row
// ([DietStrategyField]) plus the lines under the row ([DietStrategyFootnotes]:
// the Keto note, the vegan-Keto reason, the paused hint). The screen mounts
// them only when DietStrategyFlags.enabled.
//
// The selected chip is the EFFECTIVE strategy, read from macroTargetsProvider's
// `strategy_index` (the same object as the numbers on screen), never a
// separately read profile value. A free user who stored a strategy while PRO
// sees Balanced selected plus a one-line "paused" hint.
//
// Unit 3b (docs/plans/diet-strategy-3b.md §3.5, §3.8): Keto is not offered
// to a Vegan food type (the chip is disabled, with the reason line), and the
// Keto medical note shows while Keto is selected. The 3a "Meals for Keto
// come in the next update" line is gone: the plan below now follows the
// strategy, and the screen says so under its header when it does not.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/diet_strategy_notes.dart';
import '../providers/nutrition_provider.dart';
import '../services/diet_strategy_actions.dart';
import 'diet_plan_dropdown.dart';

/// The hint for a stored strategy that is not applied because PRO lapsed.
String dietStrategyPausedHint(DietStrategy stored) =>
    '${stored.label} is paused. It comes back with PRO.';

class DietStrategyField extends ConsumerStatefulWidget {
  const DietStrategyField({super.key});

  @override
  ConsumerState<DietStrategyField> createState() => _DietStrategyFieldState();
}

class _DietStrategyFieldState extends ConsumerState<DietStrategyField> {
  bool _busy = false;

  Future<void> _onTap(DietStrategy next, DietStrategy current) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await handleDietStrategyTap(context, ref, next, current: current);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effective = dietStrategyOfTargets(ref.watch(macroTargetsProvider));
    final isPro = ref.watch(subscriptionInfoProvider.select((s) => s.isPro));
    final foodType =
        ref.watch(userProfileProvider.select((p) => foodTypeOfProfile(p)));
    final off = dietStrategiesDisabledFor(foodType);
    return DietPlanDropdown<DietStrategy>(
      label: 'Diet strategy',
      fieldKey: const ValueKey('diet_plan_strategy_dropdown'),
      value: effective,
      enabled: !_busy,
      onChanged: (s) => _onTap(s, effective),
      options: [
        for (final s in DietStrategy.values)
          DietPlanDropdownOption<DietStrategy>(
            value: s,
            label: s.label,
            itemKey: ValueKey('diet_strategy_chip_${s.storageKey}'),
            enabled: !off.contains(s),
            badge: !isPro && s != DietStrategy.balanced ? 'PRO' : null,
            badgeKey: ValueKey('diet_strategy_pro_badge_${s.storageKey}'),
          ),
      ],
    );
  }
}

/// The lines under the settings row for the strategy: the vegan-Keto reason,
/// the Keto medical note and the PRO-lapsed hint.
class DietStrategyFootnotes extends ConsumerWidget {
  const DietStrategyFootnotes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effective = dietStrategyOfTargets(ref.watch(macroTargetsProvider));
    final isPro = ref.watch(subscriptionInfoProvider.select((s) => s.isPro));
    final stored = dietStrategyOf(
        ref.watch(userProfileProvider.select((p) => p['diet_strategy'])));
    final paused = !isPro && stored != DietStrategy.balanced;
    final foodType =
        ref.watch(userProfileProvider.select((p) => foodTypeOfProfile(p)));
    final dim =
        AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DietStrategyNotes(foodType: foodType, selected: effective),
        if (paused) ...[
          const SizedBox(height: 8),
          Text(dietStrategyPausedHint(stored),
              key: const ValueKey('diet_strategy_paused_hint'), style: dim),
        ],
      ],
    );
  }
}
