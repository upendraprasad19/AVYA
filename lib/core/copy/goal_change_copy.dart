// lib/core/copy/goal_change_copy.dart
//
// The words of the coach's goal-switch preview (OI-191): what else changes when
// the goal changes. Plain and factual, in the vocabulary the rest of the app
// already uses (target weight, calories, protein; Build / Cut / Maintain). The
// numbers are estimates (the apply recomputes from the profile at that moment),
// so the lines say "about".
import 'package:icanbefitter/core/constants/fitness_goals.dart';

class GoalChangeCopy {
  GoalChangeCopy._();

  static const eyebrow = 'ALSO CHANGES';

  static const double _lbsPerKg = 2.20462;

  /// A weight in the unit the user reads: one decimal in kg, whole pounds in lbs
  /// (the formats the Edit Profile fields use).
  static String _w(double kg, bool metric) => metric
      ? '${kg.toStringAsFixed(1)} kg'
      : '${(kg * _lbsPerKg).toStringAsFixed(0)} lbs';

  static String _int(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// "Target weight 71.0 kg → 78.0 kg" (the old value reads "not set" when there
  /// was none).
  static String targetLine({
    required double? from,
    required double to,
    bool metric = true,
  }) =>
      'Target weight ${from != null && from > 0 ? _w(from, metric) : 'not set'} → ${_w(to, metric)}';

  /// Why the target moved: the rule of the NEW goal against the current weight.
  static String targetReason({
    required String goal,
    required double? currentKg,
    bool metric = true,
  }) {
    final cur = currentKg == null ? 'weight' : _w(currentKg, metric);
    switch (goal) {
      case 'build_muscle':
        return '${FitnessGoals.label(goal)} needs a target above your current $cur.';
      case 'lose_fat':
        return '${FitnessGoals.label(goal)} needs a target below your current $cur.';
      default:
        return '${FitnessGoals.label(goal)} keeps your target within ${metric ? '3 kg' : '7 lbs'} of your current $cur.';
    }
  }

  static String caloriesLine({required num? from, required num to}) =>
      'Daily calories about ${from == null ? 'not set' : _int(from)} → ${_int(to)} kcal';

  static String proteinLine({required num? from, required num to}) =>
      'Protein about ${from == null ? 'not set' : _int(from)} → ${_int(to)} g';
}
