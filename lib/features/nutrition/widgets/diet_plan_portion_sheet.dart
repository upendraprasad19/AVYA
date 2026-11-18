// lib/features/nutrition/widgets/diet_plan_portion_sheet.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.3): the portion
// picker of a free pick. A stepper of the row's standard serving (whole counts
// for a countable serving) and a grams field kept in step with it, with the
// four macros live. Returns the plan item, or null when dismissed.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../services/diet_plan_free_item.dart';
import '../providers/diet_serving_view_provider.dart';
import '../services/diet_plan_generator.dart';
import '../services/diet_serving_label.dart';

Future<DietPlanFoodItem?> showDietPlanPortionSheet(
  BuildContext context, {
  required Map<String, dynamic> row,
  required String? role,
  bool processed = false,
  bool yours = false,
  DietServingView view = DietServingView.portions,
}) {
  return showModalBottomSheet<DietPlanFoodItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: DietPlanPortionSheet(
          row: row,
          role: role,
          processed: processed,
          yours: yours,
          view: view),
    ),
  );
}

class DietPlanPortionSheet extends StatefulWidget {
  const DietPlanPortionSheet({
    super.key,
    required this.row,
    required this.role,
    this.processed = false,
    this.yours = false,
    this.view = DietServingView.portions,
  });

  final Map<String, dynamic> row;
  final String? role;
  final bool processed;
  final bool yours;
  final DietServingView view;

  @override
  State<DietPlanPortionSheet> createState() => _DietPlanPortionSheetState();
}

class _DietPlanPortionSheetState extends State<DietPlanPortionSheet> {
  late double _m;
  late final double _stdG;
  late final double _step;
  late final double _maxM;
  late final TextEditingController _grams;

  @override
  void initState() {
    super.initState();
    _stdG = dietServingGramsOf(widget.row);
    _step = dietPortionStep(dietServingDescOf(widget.row));
    _maxM = dietPortionMaxMultiple(widget.row);
    // one standard serving to start (less when the serving alone is over the
    // 2000 g cap: a custom food may state up to 10000 g)
    _m = _maxM < 1 ? _maxM : 1;
    _grams = TextEditingController(text: _fmtG(_stdG * _m));
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  String _fmtG(double g) => g.round().toString();

  void _setM(double m) {
    final rawLo =
        _step > kDietPortionMinGrams / _stdG ? _step : kDietPortionMinGrams / _stdG;
    // `clamp` throws when the lower limit is above the upper one (a serving
    // over 4000 g makes `_maxM` less than a half step).
    final lo = rawLo < _maxM ? rawLo : _maxM;
    // A typed amount may sit above the 10-serving cap (a 5 g serving, 1500 g
    // typed): `+` then stays where it is instead of jumping down to the cap
    // (B-pass delta seat finding 4).
    final hi = _m > _maxM ? _m : _maxM;
    setState(() {
      _m = m.clamp(lo, hi).toDouble();
      _grams.text = _fmtG(_stdG * _m);
    });
  }

  void _stepBy(int dir) {
    final snapped = (_m / _step).round() * _step;
    _setM(snapped + dir * _step);
  }

  void _onGrams(String text) {
    final g = double.tryParse(text.trim());
    if (g == null) return;
    final clamped = g.clamp(kDietPortionMinGrams, kDietPortionMaxGrams).toDouble();
    setState(() => _m = clamped / _stdG);
  }

  @override
  Widget build(BuildContext context) {
    final item = freePickItem(row: widget.row, multiple: _m, role: widget.role);
    final dim = AppTypography.bodySm
        .copyWith(fontSize: 12, color: AppColors.textDim);
    final hasCalories = dietRowHasCalories(widget.row);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name,
                style: AppTypography.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            if (widget.processed || widget.yours) ...[
              const SizedBox(height: 4),
              Text(widget.yours ? 'Yours' : 'Processed',
                  key: const ValueKey('diet_portion_tag'),
                  style: dim.copyWith(color: AppColors.accent)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('diet_portion_minus'),
                  onPressed: () => _stepBy(-1),
                  icon: const Icon(Icons.remove_circle_outline,
                      color: AppColors.accent),
                ),
                Expanded(
                  child: Text(
                      servingLabelFor(
                          item.foodId, item.servingDesc, item.servingG, widget.view),
                      key: const ValueKey('diet_portion_desc'),
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                IconButton(
                  key: const ValueKey('diet_portion_plus'),
                  onPressed: () => _stepBy(1),
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppColors.accent),
                ),
              ],
            ),
            Row(
              children: [
                Text('Weight', style: dim),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: TextField(
                    key: const ValueKey('diet_portion_grams'),
                    controller: _grams,
                    keyboardType: TextInputType.number,
                    onChanged: _onGrams,
                    style: AppTypography.body
                        .copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                        isDense: true,
                        suffixText: widget.view == DietServingView.grams &&
                                isLiquidFood(item.foodId)
                            ? 'ml'
                            : 'g'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${item.calories} kcal · P ${item.protein}g · '
              'C ${item.carbs}g · F ${item.fat}g',
              key: const ValueKey('diet_portion_macros'),
              style: AppTypography.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent),
            ),
            if (!hasCalories) ...[
              const SizedBox(height: 8),
              Text('No calories are saved for this food. Add them in '
                  'My foods first.',
                  key: const ValueKey('diet_portion_no_calories'),
                  style: dim.copyWith(color: AppColors.warn)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('diet_portion_add'),
                onPressed:
                    hasCalories ? () => Navigator.of(context).pop(item) : null,
                child: const Text('Add to plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
