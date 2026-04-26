import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
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

/// Embedded full-text search reusing the existing food search query
/// infrastructure. Body is intentionally minimal here — the heavy
/// lifting is delegated to existing providers.
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
        // The actual results list reuses the same query path as
        // showFoodSearchSheet — see Task 7 for wiring detail.
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

/// Placeholder wired in Task 7 — pulls from the same provider used by
/// `food_search_sheet.dart` so behavior matches the legacy bottom-sheet
/// path verbatim.
class _SearchResultsList extends ConsumerWidget {
  const _SearchResultsList({required this.query, required this.onLogged});
  final String query;
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Implementation in Task 7.
    return const Center(child: SizedBox.shrink());
  }
}

class _RecentLogs extends ConsumerWidget {
  const _RecentLogs({required this.onLogged});
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Implementation in Task 7.
    return const Center(child: SizedBox.shrink());
  }
}
