// lib/features/nutrition/widgets/diet_plan_food_search_sheet.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.3): "Search any
// food". A text field over the hits the flow supplies; a tap opens the portion
// sheet. Returns the plan item, or null when dismissed. The rows of the result
// list are NOT ListTiles (the swap-sheet tests count ListTiles as
// alternatives).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../providers/diet_serving_view_provider.dart';
import '../services/diet_plan_food_search.dart';
import '../services/diet_serving_label.dart';
import '../services/diet_plan_generator.dart';
import 'diet_plan_portion_sheet.dart';

Future<DietPlanFoodItem?> showDietPlanFoodSearchSheet(
  BuildContext context, {
  required List<DietPlanSearchHit> Function(String query) search,
  required String? role,
  DietServingView view = DietServingView.portions,
}) {
  // The route's own builder context has the top padding removed, so read it
  // from the caller's context.
  final topInset = MediaQuery.of(context).padding.top;
  return showModalBottomSheet<DietPlanFoodItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
    ),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      // 80% of the screen, but never taller than what the keyboard leaves
      // (B-pass seat B finding 5: the fixed 0.8H put the list's lower fifth
      // behind the keyboard).
      // minus the status bar / notch (B-pass delta seat finding 3), and never
      // negative (a small window under a tall keyboard)
      final room =
          mq.size.height - mq.viewInsets.bottom - topInset - 8;
      final raw = mq.size.height * 0.8 < room ? mq.size.height * 0.8 : room;
      final height = raw < 0 ? 0.0 : raw;
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SizedBox(
          height: height,
          child: DietPlanFoodSearchSheet(search: search, role: role, view: view),
        ),
      );
    },
  );
}

class DietPlanFoodSearchSheet extends StatefulWidget {
  const DietPlanFoodSearchSheet(
      {super.key,
      required this.search,
      required this.role,
      this.view = DietServingView.portions});

  final List<DietPlanSearchHit> Function(String query) search;
  final String? role;
  final DietServingView view;

  @override
  State<DietPlanFoodSearchSheet> createState() =>
      _DietPlanFoodSearchSheetState();
}

class _DietPlanFoodSearchSheetState extends State<DietPlanFoodSearchSheet> {
  String _query = '';

  Future<void> _open(DietPlanSearchHit hit) async {
    final item = await showDietPlanPortionSheet(
      context,
      row: hit.row,
      role: widget.role,
      processed: hit.processed,
      yours: hit.yours,
      view: widget.view,
    );
    if (item != null && mounted) Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final hits = widget.search(_query);
    final dim =
        AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search any food',
                style: AppTypography.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('diet_search_field'),
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Type a food, e.g. oats'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: hits.isEmpty
                  ? Text(
                      _query.trim().isEmpty
                          ? 'Type to search the food list.'
                          : 'Nothing found for this diet.',
                      key: const ValueKey('diet_search_empty'),
                      style: dim)
                  : ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (ctx, i) {
                        final h = hits[i];
                        return InkWell(
                          key: ValueKey('diet_search_hit_${h.id}'),
                          onTap: () => _open(h),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(h.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.body.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                      Text(
                                          '${servingLabelFor(h.id, '${h.row['standard_serving_desc'] ?? '1 serving'}', (h.row['standard_serving_g'] as num?)?.toDouble() ?? 0, widget.view)}'
                                          ' · ${(h.row['calories_std'] as num?)?.round() ?? 0} kcal',
                                          style: dim),
                                    ],
                                  ),
                                ),
                                if (h.yours || h.processed)
                                  Text(h.yours ? 'Yours' : 'Processed',
                                      key: ValueKey('diet_search_tag_${h.id}'),
                                      style: dim.copyWith(
                                          color: AppColors.accent)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
