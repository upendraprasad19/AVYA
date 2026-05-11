import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../../providers/nutrition_provider.dart';
import '../saved_meals_section.dart';

/// SEARCH mode body for `LogFoodSheet`. Three sub-filters at the top:
///   `[All] [Saved Meals] [Recent]`.
/// Body switches based on the active filter:
///   * All        — full-text food search field (same UI as the
///                  legacy showFoodSearchSheet).
///   * Saved Meals — embedded SavedMealsSection.
///   * Recent     — most-recent foodlog rows from nutritionBox.
class SearchModeBody extends ConsumerStatefulWidget {
  const SearchModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  ConsumerState<SearchModeBody> createState() => _SearchModeBodyState();
}

enum _SearchFilter { all, saved, recent }

class _SearchModeBodyState extends ConsumerState<SearchModeBody> {
  _SearchFilter _filter = _SearchFilter.all;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-filter chip row
          Row(
            children: [
              _filterChip(_SearchFilter.all, 'All'),
              const SizedBox(width: 6),
              _filterChip(_SearchFilter.saved, 'Saved Meals'),
              const SizedBox(width: 6),
              _filterChip(_SearchFilter.recent, 'Recent'),
            ],
          ),
          const SizedBox(height: 12),
          // Body switches by filter
          Expanded(
            child: switch (_filter) {
              _SearchFilter.all => _AllFoodsSearch(
                  onLogged: widget.onLogged,
                ),
              _SearchFilter.saved => const SavedMealsSection(),
              _SearchFilter.recent => _RecentLogs(onLogged: widget.onLogged),
            },
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_SearchFilter value, String label) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: WardChip(
        label: label.toUpperCase(),
        tone: selected ? WardChipTone.gold : WardChipTone.neutral,
      ),
    );
  }
}

/// Embedded full-text search reusing `FoodRepository.search`. Each tap
/// logs the food at its standard serving (or 100g fallback) for the
/// current meal-window-derived meal type, then bubbles `onLogged` so
/// the host sheet dismisses.
class _AllFoodsSearch extends ConsumerStatefulWidget {
  const _AllFoodsSearch({required this.onLogged});
  final VoidCallback onLogged;
  @override
  ConsumerState<_AllFoodsSearch> createState() => _AllFoodsSearchState();
}

class _AllFoodsSearchState extends ConsumerState<_AllFoodsSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: AppColors.line2),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: AppColors.textDim, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: (_) => setState(() {}),
                  style: AppTypography.body,
                  decoration: const InputDecoration(
                    hintText: 'Search foods',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _SearchResultsList(
            query: _controller.text,
            onLogged: widget.onLogged,
          ),
        ),
      ],
    );
  }
}

/// Live results list. `FoodRepository.search` is synchronous (Hive read);
/// no FutureProvider wrapping needed.
class _SearchResultsList extends ConsumerWidget {
  const _SearchResultsList({required this.query, required this.onLogged});
  final String query;
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Type at least 2 characters to search.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
            ),
          ),
        ),
      );
    }

    final items = FoodRepository.instance.search(query, limit: 30);
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No results for "$query"',
          style: AppTypography.bodySm
              .copyWith(color: AppColors.textDim),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.line2),
      itemBuilder: (_, i) {
        final item = items[i];
        final cals =
            (item['calories_std'] as num?)?.toInt() ??
                (item['calories_per_100g'] as num?)?.toInt() ??
                0;
        final servingDesc =
            item['standard_serving_desc'] as String? ?? '1 serving';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(item['name'] as String? ?? 'Unknown',
              style: AppTypography.body),
          subtitle: Text(
            '$cals kcal · $servingDesc',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textDim),
          ),
          onTap: () async {
            final qty =
                (item['standard_serving_g'] as num?)?.toDouble() ?? 100.0;
            await ref.read(foodLogProvider.notifier).logFood(
                  food: item,
                  mealType: _mealTypeForNow(),
                  quantityG: qty,
                );
            onLogged();
          },
        );
      },
    );
  }
}

class _RecentLogs extends ConsumerWidget {
  const _RecentLogs({required this.onLogged});
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = HiveService.instance.nutritionBox;
    // Last 14 days, dedupe by food_name, top 8.
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final entries = <String, Map<String, dynamic>>{};
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('nlog_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final createdAtStr =
          (raw['created_at'] ?? raw['logged_at']) as String?;
      if (createdAtStr == null) continue;
      final createdAt = DateTime.tryParse(createdAtStr);
      if (createdAt == null || createdAt.isBefore(cutoff)) continue;
      final name = (raw['food_name'] as String?) ?? '';
      if (name.isEmpty || entries.containsKey(name)) continue;
      entries[name] = Map<String, dynamic>.from(raw);
      if (entries.length >= 8) break;
    }
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No recent logs in the last 14 days.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textDim),
          ),
        ),
      );
    }
    final list = entries.values.toList();
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.line2),
      itemBuilder: (_, i) {
        final item = list[i];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(item['food_name'] as String? ?? 'Unknown',
              style: AppTypography.body),
          subtitle: Text(
            '${(item['total_calories'] as num?)?.toInt() ?? 0} kcal',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.textDim),
          ),
          onTap: () async {
            await _relogFromHistory(ref, item);
            onLogged();
          },
        );
      },
    );
  }
}

/// Re-log a previous nutrition_log row.
///
/// T-12 / audit-2026-05-11 — routed through
/// `NutritionWriteService.logMeal` so the new `nlog_*` row inherits
/// the canonical field shape (IST date, deterministic key, `items[]`
/// array). Pre-fix this wrote a flat-totals row directly to Hive with
/// no `items[]`, so `_syncNutritionLogs` cloud projection wrote 0
/// rows to `nutrition_log_items`. Same C-12 sibling bug class.
///
/// The "recent foods" surface only carries flat totals, so we
/// synthesise a single `FoodItem` from the source name + quantity +
/// macros — same approach used by `FoodLogNotifier.logFood`.
Future<void> _relogFromHistory(
    WidgetRef ref, Map<String, dynamic> source) async {
  final item = FoodItem(
    name: (source['food_name'] ?? 'Unknown') as String,
    quantityG: (source['quantity_g'] as num?)?.toDouble() ?? 100.0,
    calories: (source['total_calories'] as num?)?.toDouble() ?? 0,
    protein: (source['total_protein'] as num?)?.toDouble() ?? 0,
    carbs: (source['total_carbs'] as num?)?.toDouble() ?? 0,
    fat: (source['total_fat'] as num?)?.toDouble() ?? 0,
    fiber: (source['total_fiber'] as num?)?.toDouble() ?? 0,
  );
  await NutritionWriteService.instance.logMeal(
    date: DateTime.now(),
    mealType: _mealTypeForNow(),
    items: [item],
    source: NutritionWriteSource.manualSearch,
  );
  // WriteService invalidates providers + fires sync internally, but
  // keep these explicit so the recent-foods sheet rebuilds even when
  // the WriteService onStateChanged hook isn't wired in this widget
  // tree (defensive — matches the pattern used elsewhere).
  ref.invalidate(dailyNutritionProvider);
  ref.invalidate(recentFoodLogsProvider);
}

String _mealTypeForNow() {
  final hour = DateTime.now().hour;
  if (hour < 11) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 19) return 'dinner';
  return 'snacks';
}
