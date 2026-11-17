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
import '../services/diet_plan_generator.dart';

Future<DietPlanFoodItem?> showDietPlanPortionSheet(
  BuildContext context, {
  required Map<String, dynamic> row,
  required String? role,
  bool processed = false,
  bool yours = false,
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
          row: row, role: role, processed: processed, yours: yours),
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
  });

  final Map<String, dynamic> row;
  final String? role;
  final bool processed;
  final bool yours;

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
    _m = 1; // one standard serving to start
    _grams = TextEditingController(text: _fmtG(_stdG * _m));
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  String _fmtG(double g) => g.round().toString();

  void _setM(double m) {
    final lo = _step > kDietPortionMinGrams / _stdG ? _step : kDietPortionMinGrams / _stdG;
    setState(() {
      _m = m.clamp(lo, _maxM).toDouble();
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
    return SafeArea(
      child: Padding(
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
                  child: Text(item.servingDesc,
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
                    decoration: const InputDecoration(
                        isDense: true, suffixText: 'g'),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('diet_portion_add'),
                onPressed: () => Navigator.of(context).pop(item),
                child: const Text('Add to plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
