// lib/core/copy/target_impact_copy.dart
//
// The words that say "your calorie / protein targets just changed" with EXACT numbers
// (goal-change-targets B2 weigh-in snackbar, B3 Edit Profile dialog, B4 stale-plan banner).
// `GoalChangeCopy` says "about" because the coach's preview is an estimate; here the targets are
// already saved, so the numbers are the saved ones. Plain and factual, in the app's vocabulary.
class TargetImpactCopy {
  TargetImpactCopy._();

  static const title = 'Targets updated';
  static const alreadyUpdatedEyebrow = 'ALREADY UPDATED';
  static const savedPlanSentence =
      'Your saved diet chart still shows the old numbers.';
  static const dismissLabel = 'OK';

  static String _int(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String caloriesLine({required num? from, required num to}) =>
      'Daily calories ${from == null ? 'not set' : _int(from)} → ${_int(to)} kcal';

  static String proteinLine({required num? from, required num to}) =>
      'Protein ${from == null ? 'not set' : _int(from)} → ${_int(to)} g';

  /// The weight sheet's snackbar when the weigh-in moved the targets.
  static String weighInSnackbar({
    required num? caloriesFrom,
    required num caloriesTo,
    required num? proteinFrom,
    required num proteinTo,
  }) =>
      'Weight logged ✓  Targets updated: '
      '${_int(caloriesTo)} kcal, ${_int(proteinTo)} g protein '
      '(was ${caloriesFrom == null ? 'not set' : _int(caloriesFrom)} kcal, '
      '${proteinFrom == null ? 'not set' : _int(proteinFrom)} g)';
}
