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
  final tenths = ((target! - current!) * 10).round();
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

String _kg(double v) => v.toStringAsFixed(1);

/// Popup copy for a failed check. [current] is the user's current weight.
String targetWeightMessage(TargetWeightCheck check, double current) {
  switch (check) {
    case TargetWeightCheck.ok:
      return '';
    case TargetWeightCheck.missing:
      return 'Enter your target weight to continue.';
    case TargetWeightCheck.mustBeBelowCurrent:
      return 'For a Cut your target has to be lower than your current weight '
          '(${_kg(current)} kg). Adjust it and continue.';
    case TargetWeightCheck.mustBeAboveCurrent:
      return 'For a Build your target has to be higher than your current '
          'weight (${_kg(current)} kg). Adjust it and continue.';
    case TargetWeightCheck.outsideMaintainWindow:
      return 'To maintain, keep your target within ${kMaintainWindowKg.toStringAsFixed(0)} kg '
          'of your current weight (${_kg(current - kMaintainWindowKg)}–'
          '${_kg(current + kMaintainWindowKg)} kg). Adjust it and continue.';
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
