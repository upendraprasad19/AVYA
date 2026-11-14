// lib/features/nutrition/widgets/diet_strategy_section.dart
//
// Diet plan Unit 3a (docs/plans/diet-strategy.md §3.5-§3.8): the Diet Plan
// screen's strategy block under the food-type chips. The screen mounts it
// only when DietStrategyFlags.enabled.
//
// The selected chip is the EFFECTIVE strategy, read from macroTargetsProvider's
// `strategy_index` (the same object as the numbers on screen), never a
// separately read profile value. A free user who stored a strategy while PRO
// sees Balanced selected plus a one-line "paused" hint.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/diet_strategy_chips.dart';
import '../providers/nutrition_provider.dart';
import '../services/diet_strategy_actions.dart';

/// The line under the targets for a strategy whose meals are not built yet
/// (removed by Unit 3b).
String dietStrategyMealsNote(DietStrategy s) =>
    'Meals for ${s.label} come in the next update. '
    'This plan uses balanced meals.';

/// The hint for a stored strategy that is not applied because PRO lapsed.
String dietStrategyPausedHint(DietStrategy stored) =>
    '${stored.label} is paused. It comes back with PRO.';

class DietStrategySection extends ConsumerStatefulWidget {
  const DietStrategySection({super.key});

  @override
  ConsumerState<DietStrategySection> createState() =>
      _DietStrategySectionState();
}

class _DietStrategySectionState extends ConsumerState<DietStrategySection> {
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
    final stored = dietStrategyOf(
        ref.watch(userProfileProvider.select((p) => p['diet_strategy'])));
    final paused = !isPro && stored != DietStrategy.balanced;
    final dim = AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diet strategy', style: dim),
        const SizedBox(height: 8),
        DietStrategyChips(
          value: effective,
          isPro: isPro,
          enabled: !_busy,
          onChanged: (s) => _onTap(s, effective),
        ),
        if (paused) ...[
          const SizedBox(height: 8),
          Text(dietStrategyPausedHint(stored),
              key: const ValueKey('diet_strategy_paused_hint'), style: dim),
        ],
        if (effective != DietStrategy.balanced) ...[
          const SizedBox(height: 8),
          Text(dietStrategyMealsNote(effective),
              key: const ValueKey('diet_strategy_meals_note'), style: dim),
        ],
      ],
    );
  }
}
