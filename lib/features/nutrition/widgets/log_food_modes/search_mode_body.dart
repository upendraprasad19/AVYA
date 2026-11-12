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
///   * All        — full-text food search field.
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
                  mealType: ref.read(mealTypeProvider),
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
    final rows = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('nlog_')) continue;
      final raw = box.get(key);
      if (raw is Map) rows.add(Map<String, dynamic>.from(raw));
    }
    final list = recentLoggedItems(rows,
        cutoff: DateTime.now().subtract(const Duration(days: 14)));
    if (list.isEmpty) {
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
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.line2),
      itemBuilder: (_, i) {
        final item = list[i];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(item.name, style: AppTypography.body),
          subtitle: Text(
            '${item.calories.round()} kcal',
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

/// The Search tab's "recent" list (OI-493): every item of the `nlog_` rows
/// logged since [cutoff], newest first, one entry per lowercased name, at most
/// [limit]. Names live in `items[]` (the writer never writes a top-level
/// `food_name`, which this list used to read, so it was always empty). An item
/// that does not parse or has no name is skipped, so one bad item never blanks
/// the list; a legacy flat row without `items[]` adds nothing.
@visibleForTesting
List<FoodItem> recentLoggedItems(Iterable<Map<String, dynamic>> rows,
    {required DateTime cutoff, int limit = 8}) {
  final dated = <(DateTime, int, FoodItem)>[];
  var seq = 0;
  for (final row in rows) {
    final stamp = row['created_at'] ?? row['logged_at'];
    final at = stamp is String ? DateTime.tryParse(stamp) : null;
    if (at == null || at.isBefore(cutoff)) continue;
    final items = row['items'];
    if (items is! List) continue;
    for (final e in items) {
      if (e is! Map) continue;
      try {
        final item = FoodItem.fromMap(Map<String, dynamic>.from(e));
        if (item.name.trim().isEmpty) continue;
        dated.add((at, seq++, item));
      } catch (_) {
        continue;
      }
    }
  }
  dated.sort((x, y) {
    final byTime = y.$1.compareTo(x.$1);
    return byTime != 0 ? byTime : x.$2.compareTo(y.$2);
  });
  final seen = <String>{};
  final out = <FoodItem>[];
  for (final (_, _, item) in dated) {
    if (!seen.add(item.name.trim().toLowerCase())) continue;
    out.add(item);
    if (out.length >= limit) break;
  }
  return out;
}

/// Re-log an item from the "recent" list exactly as it was stored (name,
/// grams, macros, fibre; no rescale), so a coach item at the 100 g sentinel and
/// a screen item with real grams each log as first written. A 0 g item is
/// relogged at the 100 g sentinel. Routed through `NutritionWriteService.logMeal`
/// (T-12) so the new row has the canonical shape.
/// The item a tap on a recent entry logs again: the stored item as it is,
/// except a 0 g item (an old coach write) takes the 100 g sentinel the other
/// AI writers use, so the copy shows a portion and edits like them.
@visibleForTesting
FoodItem relogItem(FoodItem stored) => stored.quantityG > 0
    ? stored
    : FoodItem(
        name: stored.name,
        quantityG: 100.0,
        calories: stored.calories,
        protein: stored.protein,
        carbs: stored.carbs,
        fat: stored.fat,
        fiber: stored.fiber,
      );

Future<void> _relogFromHistory(WidgetRef ref, FoodItem stored) async {
  final item = relogItem(stored);
  await NutritionWriteService.instance.logMeal(
    date: DateTime.now(),
    mealType: ref.read(mealTypeProvider),
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
