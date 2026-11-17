// lib/features/nutrition/services/diet_plan_free_item.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.3): the portion
// arithmetic of a free pick. Pure. A portion is a multiple of the row's
// standard serving; the grams field is the same number in another unit
// (grams = standard serving grams x multiple).
import 'curated_diet_plan_generator.dart';
import 'diet_plan_generator.dart';

num _n(Object? v) => v is num ? v : 0;

/// The row's standard serving in grams (100 when the row has none).
double dietServingGramsOf(Map<String, dynamic> row) {
  final g = _n(row['standard_serving_g']).toDouble();
  return g > 0 ? g : 100;
}

/// The row's standard serving text.
String dietServingDescOf(Map<String, dynamic> row) =>
    (row['standard_serving_desc'] as String?)?.trim().isNotEmpty == true
        ? row['standard_serving_desc'] as String
        : '1 serving';

final RegExp _qtyRe = RegExp(r'^\s*(\d+/\d+|\d+(?:\.\d+)?)');

double? _leadingQty(String desc) {
  final m = _qtyRe.firstMatch(desc);
  if (m == null) return null;
  final s = m.group(1)!;
  if (s.contains('/')) {
    final p = s.split('/');
    final d = double.parse(p[1]);
    return d == 0 ? null : double.parse(p[0]) / d;
  }
  return double.parse(s);
}

/// True when the serving counts things (1 roti, 2 idli): its scaled count must
/// stay whole (`kCountableServingUnits`, the T7 rule). A parenthetical such as
/// "1 cup (3 eggs)" is not read: a stated limit.
bool dietServingIsCountable(String desc) {
  final head = desc.toLowerCase().split('(').first;
  return head
      .split(RegExp(r'[^a-z]+'))
      .any((w) => w.isNotEmpty && kCountableServingUnits.contains(w));
}

/// The step of the portion stepper: whole counts for a countable serving
/// (`qty x m` a whole number), half servings otherwise.
double dietPortionStep(String desc) {
  if (!dietServingIsCountable(desc)) return 0.5;
  final q = _leadingQty(desc);
  if (q == null || q <= 0) return 1;
  return 1 / q;
}

/// Greatest multiple the picker allows (also capped by 2000 g).
const double kDietPortionMaxMultiple = 10;
const double kDietPortionMaxGrams = 2000;
const double kDietPortionMinGrams = 1;

/// The largest multiple allowed for [row].
double dietPortionMaxMultiple(Map<String, dynamic> row) {
  final byGrams = kDietPortionMaxGrams / dietServingGramsOf(row);
  return byGrams < kDietPortionMaxMultiple ? byGrams : kDietPortionMaxMultiple;
}

/// The plan item for [row] at [multiple] standard servings, filling [role]
/// (the REPLACED item's role, so a later swap of this pick finds that role's
/// catalog alternatives).
DietPlanFoodItem freePickItem({
  required Map<String, dynamic> row,
  required double multiple,
  required String? role,
}) {
  final stdG = dietServingGramsOf(row);
  final grams = stdG * multiple;
  double macro(String per100, String std) {
    final p = row[per100];
    if (p is num) return p.toDouble() * grams / 100;
    return _n(row[std]).toDouble() * multiple;
  }

  final desc = dietServingDescOf(row);
  final step = dietPortionStep(desc);
  final onStep = ((multiple / step) - (multiple / step).round()).abs() < 1e-9;
  final text = onStep && servingDescParses(desc)
      ? scaleServingDesc(desc, multiple)
      : '${grams.round()} g';
  final id = row['id'] as String? ?? '';
  return DietPlanFoodItem(
    foodId: id,
    name: row['name'] as String? ?? id,
    servingDesc: text,
    servingG: grams,
    calories: macro('calories_per_100g', 'calories_std').round(),
    protein: macro('protein_per_100g', 'protein_std').round(),
    carbs: macro('carbs_per_100g', 'carbs_std').round(),
    fat: macro('fat_per_100g', 'fat_std').round(),
    fiber: macro('fiber_per_100g', 'fiber_std').round(),
    category: row['category'] as String? ?? '',
    role: role,
  );
}
