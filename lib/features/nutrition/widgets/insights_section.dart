// "INSIGHTS & TRENDS" on the Nutrition tab: the always-visible SEE FULL
// HISTORY row (opens the Nutrition History screen) and, expanded, the two
// weekly cards. Moved out of nutrition_screen.dart (plan
// docs/plans/nutrition-history.md 5.6 / S8).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/nutrition_provider.dart';
import 'weekly_chart_card.dart';

class NutritionInsightsSection extends ConsumerStatefulWidget {
  const NutritionInsightsSection({super.key});

  @override
  ConsumerState<NutritionInsightsSection> createState() =>
      _NutritionInsightsSectionState();
}

class _NutritionInsightsSectionState
    extends ConsumerState<NutritionInsightsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final weeklyData = ref.watch(weeklyNutritionProvider);
    return WardCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          GestureDetector(
            key: const Key('insights_header'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Text(
                    'INSIGHTS & TRENDS',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textDim,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const WardRule(margin: EdgeInsets.zero),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('see_full_history'),
              onTap: () => context.go('/nutrition/history'),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SEE FULL HISTORY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.mono.copyWith(
                          color: AppColors.accent,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.accent, size: 18),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const WardRule(margin: EdgeInsets.zero),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: WeeklyChartCard(
                title: 'This Week — Calories',
                emoji: '\u{1F4CA}',
                data: weeklyData.calories,
                barColor: AppColors.accent,
                avgLabel: 'Avg: ${weeklyData.avgCalories.round()} kcal/day',
                targetLabel: 'Target: ${weeklyData.calorieTarget.round()}',
                targetColor: AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: WeeklyChartCard(
                title: 'This Week — Protein',
                emoji: '\u{1F4AA}',
                data: weeklyData.protein,
                barColor: AppColors.warn,
                avgLabel: 'Avg: ${weeklyData.avgProtein.round()}g/day',
                targetLabel: 'Target: ${weeklyData.proteinTarget.round()}g',
                targetColor: AppColors.warn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
