// lib/features/nutrition/services/diet_plan_totals.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.1): what the plan
// on screen PROVIDES per day, summed from the same rounded item values the
// meal cards show, so the totals row always equals the sum of the card
// headers. Pure, so it is testable without the screen.

/// One item's four shown numbers.
typedef DietMacroTuple = ({int calories, int protein, int carbs, int fat});

/// A day's four totals.
class DietPlanTotals {
  const DietPlanTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  static const DietPlanTotals zero =
      DietPlanTotals(calories: 0, protein: 0, carbs: 0, fat: 0);

  @override
  bool operator ==(Object other) =>
      other is DietPlanTotals &&
      other.calories == calories &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(calories, protein, carbs, fat);

  @override
  String toString() => 'DietPlanTotals($calories kcal, P$protein C$carbs F$fat)';
}

/// The sum of [items] (every item of every meal).
DietPlanTotals sumDietPlanTotals(Iterable<DietMacroTuple> items) {
  var c = 0, p = 0, cb = 0, f = 0;
  for (final i in items) {
    c += i.calories;
    p += i.protein;
    cb += i.carbs;
    f += i.fat;
  }
  return DietPlanTotals(calories: c, protein: p, carbs: cb, fat: f);
}

/// True when [plan] is more than 10 % away from [target] (a target of 0 or
/// less never warns: there is nothing to compare with).
bool dietPlanTotalOffTarget(num plan, num target) =>
    target > 0 && (plan - target).abs() > target * 0.10;
