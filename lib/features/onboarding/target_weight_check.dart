// lib/features/onboarding/target_weight_check.dart
//
// Pure rules for the Stats-screen TARGET weight (founder call 2026-11-01):
//   Cut      (lose_fat)        -> target strictly BELOW current weight
//   Build    (build_muscle)    -> target strictly ABOVE current weight
//   Maintain (general_fitness) -> target within +-3.0 kg of current (inclusive)
// Any other goal key (`recomp`, `strength`, unknown — no longer offered, but they
// can still arrive from legacy extras) has no rule and passes.
//
// Comparisons run in integer TENTHS of a kg. The Stats fields are one-decimal
// text, and plain double subtraction is not exact (78.3 - 75.3 is 2.9999999999999...
// or 3.0000000000000004 depending on the pair), which would make the inclusive
// 3.0 boundary flaky.
//
// OI-191: this file is also the ONE home of the goal / target agreement rules every
// door and every projection reader shares: [goalTargetAgree] (direction only),
// [canProjectGoalDate] (the date-projection gate of the Nutrition, Profile and pace
// surfaces), [projectionCalloutKind] / [journeyEtaAllowed] (the two trend-based
// readers, extracted so their branch order is testable). A target <= 0 is `missing`
// (an Edit Profile save used to store an empty field as 0.0, which passed Cut as
// "0 is below current").
library;

/// Result of [validateTargetWeight].
enum TargetWeightCheck {
  ok,

  /// Blank / unparseable / non-finite target (or current) for a validated goal.
  missing,

  /// Cut with a target at or above the current weight.
  mustBeBelowCurrent,

  /// Build with a target at or below the current weight.
  mustBeAboveCurrent,

  /// Maintain with a target more than 3.0 kg from the current weight.
  outsideMaintainWindow,
}

/// The Maintain window half-width, in kg.
const double kMaintainWindowKg = 3.0;

bool _finite(double? v) => v != null && v.isFinite;

/// Validates [target] against [current] for [goal]. Uses the RAW parsed values
/// (never the 40-250 clamp the screen applies afterwards).
TargetWeightCheck validateTargetWeight({
  required String goal,
  required double? current,
  required double? target,
}) {
  if (goal != 'lose_fat' &&
      goal != 'build_muscle' &&
      goal != 'general_fitness') {
    return TargetWeightCheck.ok;
  }
  if (!_finite(current) || !_finite(target)) return TargetWeightCheck.missing;
  if (current! <= 0 || target! <= 0) return TargetWeightCheck.missing;
  final tenths = ((target - current) * 10).round();
  switch (goal) {
    case 'lose_fat':
      return tenths < 0
          ? TargetWeightCheck.ok
          : TargetWeightCheck.mustBeBelowCurrent;
    case 'build_muscle':
      return tenths > 0
          ? TargetWeightCheck.ok
          : TargetWeightCheck.mustBeAboveCurrent;
    default: // general_fitness
      return tenths.abs() <= (kMaintainWindowKg * 10).round()
          ? TargetWeightCheck.ok
          : TargetWeightCheck.outsideMaintainWindow;
  }
}

/// True when the goal and the target weight point the same way (direction only,
/// no gap rule): [validateTargetWeight] is `ok`. A goal with no rule agrees.
bool goalTargetAgree({
  required String goal,
  required double? current,
  required double? target,
}) =>
    validateTargetWeight(goal: goal, current: current, target: target) ==
    TargetWeightCheck.ok;

/// The ONE gate of every "you'll reach X on a date" surface that projects from
/// the profile's own pair (Nutrition, Profile MY TARGETS, the pace sheet's tap):
/// a Cut or Build goal, both weights present and positive, more than 0.1 kg apart,
/// and the target on the side of the current weight the goal needs.
bool canProjectGoalDate({
  required String goal,
  required double? current,
  required double? target,
}) {
  if (goal != 'lose_fat' && goal != 'build_muscle') return false;
  if (!_finite(current) || !_finite(target)) return false;
  if ((current! - target!).abs() <= 0.1) return false;
  return goalTargetAgree(goal: goal, current: current, target: target);
}

/// What the Weekly Report's weight callout shows.
enum ProjectionCalloutKind { adjust, reached, eta, none }

/// The callout's decision, in its original branch order (OI-191 gates only the
/// date sentence): too little history -> none; not moving the right way and not
/// there yet -> adjust; within 0.5 kg of the target -> reached; otherwise the date
/// sentence, but only when the goal and the target agree (judged on the LAST
/// weigh-in, the callout's own "current").
ProjectionCalloutKind projectionCalloutKind({
  required String goal,
  required double firstW,
  required double lastW,
  required double weeksDiff,
  required double target,
}) {
  if (weeksDiff < 0.5) return ProjectionCalloutKind.none;
  final weeklyRate = (lastW - firstW) / weeksDiff;
  final remaining = target - lastW;
  final wantsLose = goal.contains('lose');
  final movingRight =
      (wantsLose && weeklyRate < 0) || (!wantsLose && weeklyRate > 0);
  if (!movingRight && remaining.abs() > 0.5) return ProjectionCalloutKind.adjust;
  if (remaining.abs() < 0.5) return ProjectionCalloutKind.reached;
  return goalTargetAgree(goal: goal, current: lastW, target: target)
      ? ProjectionCalloutKind.eta
      : ProjectionCalloutKind.none;
}

/// The Journey card's "~N weeks to goal" line is allowed only when the goal and
/// the target agree, judged on the last weigh-in. The "Lost / Gained" line is not
/// routed through this.
bool journeyEtaAllowed({
  required String goal,
  required double lastValue,
  required double target,
}) =>
    goalTargetAgree(goal: goal, current: lastValue, target: target);

String _kg(double v) => v.toStringAsFixed(1);

/// Pounds per kilogram, the factor the Edit Profile form has always used.
const double _lbsPerKg = 2.20462;

/// Popup copy for a failed check. [current] is the user's current weight, in kg.
/// [editing] swaps only the closing words for Edit Profile ("save" instead of
/// "continue"); the onboarding strings are unchanged. [metric] false prints the
/// weights in whole pounds, the unit the Edit Profile fields show (onboarding is
/// always metric).
String targetWeightMessage(TargetWeightCheck check, double current,
    {bool editing = false, bool metric = true}) {
  final to = editing ? 'save' : 'continue';
  String w(double kg) => metric
      ? '${_kg(kg)} kg'
      : '${(kg * _lbsPerKg).toStringAsFixed(0)} lbs';
  final window = metric
      ? kMaintainWindowKg.toStringAsFixed(0)
      : (kMaintainWindowKg * _lbsPerKg).toStringAsFixed(0);
  final windowUnit = metric ? 'kg' : 'lbs';
  switch (check) {
    case TargetWeightCheck.ok:
      return '';
    case TargetWeightCheck.missing:
      return 'Enter your target weight to $to.';
    case TargetWeightCheck.mustBeBelowCurrent:
      return 'For a Cut your target has to be lower than your current weight '
          '(${w(current)}). Adjust it and $to.';
    case TargetWeightCheck.mustBeAboveCurrent:
      return 'For a Build your target has to be higher than your current '
          'weight (${w(current)}). Adjust it and $to.';
    case TargetWeightCheck.outsideMaintainWindow:
      final low = metric
          ? _kg(current - kMaintainWindowKg)
          : (((current - kMaintainWindowKg) * _lbsPerKg)).toStringAsFixed(0);
      final high = metric
          ? _kg(current + kMaintainWindowKg)
          : (((current + kMaintainWindowKg) * _lbsPerKg)).toStringAsFixed(0);
      return 'To maintain, keep your target within $window $windowUnit '
          'of your current weight ($low–$high $windowUnit). Adjust it and $to.';
  }
}

/// Default target shown when Stats opens.
///
/// Reseeds from the goal delta when there is no stored target OR the stored one
/// was seeded for a DIFFERENT goal (`seededForGoal` != [goal]): a Cut target kept
/// across Stats -> BACK -> Goal(Build) -> Stats would otherwise fail the Build
/// rule on an untouched CONTINUE. A same-goal BACK keeps the user's edit; extras
/// with no `seeded_for_goal` key (legacy) keep a stored target as before.
double seedTargetWeight({
  required String goal,
  required double currentKg,
  required Object? storedTarget,
  required Object? seededForGoal,
}) {
  final stored = storedTarget is num ? storedTarget.toDouble() : null;
  final sameGoalOrLegacy = seededForGoal == null || seededForGoal == goal;
  if (stored != null && sameGoalOrLegacy) return stored;
  final delta = switch (goal) {
    'lose_fat' => -5.0,
    'recomp' => -2.0,
    'build_muscle' => 3.0,
    _ => 0.0,
  };
  return (currentKg + delta).clamp(40.0, 250.0);
}
