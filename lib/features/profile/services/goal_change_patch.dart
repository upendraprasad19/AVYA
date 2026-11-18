// lib/features/profile/services/goal_change_patch.dart
//
// OI-191: the ONE place that decides what a goal change writes. Edit Profile (its
// prefill and its Save) and the coach `switchGoal` both call it, so the seeded
// target weight and the recomputed calorie / protein targets cannot drift between
// the two doors (precedent: `legacyGoalHealPatch`, which writes the healed goal and
// its targets in one patch).
//
// Pure: no Hive, no Riverpod, no clock of its own. The caller passes `now` and the
// body-fat kill-switch value (`configBox['disable_bodyfat_calc'] == true`, the same
// read `ProfileNotifier.recalculateTargets` makes).
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

/// Rounds to one decimal, the precision of the target field.
double _tenths(double v) => (v * 10).round() / 10;

/// A positive, finite number from a profile value, else null.
double? _positive(Object? v) {
  final d = v is num ? v.toDouble() : null;
  return d != null && d.isFinite && d > 0 ? d : null;
}

/// The goal's onboarding seed for [currentKg] (Build +3 kg, Cut -5 kg, Maintain =
/// current), rounded to tenths, or null when the current weight is unknown or the
/// seed would itself break the goal's rule (the 40..250 clamp does at the edges:
/// a Cut at 40 kg or a Build at 250 kg).
double? goalTargetSeed({required String goal, required double? currentKg}) {
  final cur = _positive(currentKg);
  if (cur == null) return null;
  final seed = _tenths(seedTargetWeight(
    goal: goal,
    currentKg: cur,
    storedTarget: null,
    seededForGoal: null,
  ));
  return validateTargetWeight(goal: goal, current: cur, target: seed) ==
          TargetWeightCheck.ok
      ? seed
      : null;
}

/// True when [targetKg] cannot stand beside [goal] at [currentKg]: it is missing,
/// not positive, or fails the goal's rule. False when the current weight is
/// unknown (nothing can be judged) and for a goal with no rule.
bool targetNeedsSeed({
  required String goal,
  required double? currentKg,
  required double? targetKg,
}) {
  final cur = _positive(currentKg);
  if (cur == null) return false;
  return validateTargetWeight(goal: goal, current: cur, target: targetKg) !=
      TargetWeightCheck.ok;
}

/// What Edit Profile puts in the target field, in kg, or null to leave the field
/// alone.
///
/// - A target that already fits the goal is never touched (founder decision 2).
/// - [priorPrefill]: the field still holds a value this function (or the form's
///   open) put there, not something the user typed. Then, when
///   [originalStoredTargetKg] fits the NEW goal, it comes back instead of a seed
///   (Cut 71 -> Build -> Cut returns 71).
/// - Otherwise the goal's seed, or null when no seed fits.
double? targetPrefill({
  required String goal,
  required double? currentKg,
  required double? targetKg,
  double? originalStoredTargetKg,
  bool priorPrefill = false,
}) {
  final cur = _positive(currentKg);
  if (cur == null) return null;
  if (!targetNeedsSeed(goal: goal, currentKg: cur, targetKg: targetKg)) {
    return null;
  }
  if (priorPrefill &&
      originalStoredTargetKg != null &&
      !targetNeedsSeed(
          goal: goal, currentKg: cur, targetKg: originalStoredTargetKg)) {
    return originalStoredTargetKg;
  }
  return goalTargetSeed(goal: goal, currentKg: cur);
}

/// The pounds-per-kilogram factor the Edit Profile form has always used.
const double kLbsPerKg = 2.20462;

/// The kg a form field SAVES. A field whose text is still the one the form put
/// there (its initial text, or a prefill) is saved as the exact stored kg, never
/// re-converted from the displayed text: imperial fields show whole pounds, so a
/// 75.0 / 78.0 kg Maintain pair reads back as 74.84 / 78.02 kg and an untouched
/// Save would be refused (and would overwrite the weight with the rounded value).
/// An edited field is the typed number, converted from lbs when not metric. Null
/// when there is nothing to read.
double? resolveFieldKg({
  required String text,
  required String initialText,
  required double? storedKg,
  required double? parsed,
  required bool metric,
}) {
  if (storedKg != null && text.trim() == initialText.trim()) return storedKg;
  if (parsed == null) return null;
  return metric ? parsed : parsed / kLbsPerKg;
}

/// The text a weight field shows for [kg]: one decimal in kg, whole pounds in lbs
/// (the format the form's `initState` has always used).
String weightFieldText(double kg, {required bool metric}) =>
    metric ? kg.toStringAsFixed(1) : (kg * kLbsPerKg).toStringAsFixed(0);

/// The result of changing the goal of a profile.
class GoalChange {
  const GoalChange({
    required this.patch,
    required this.goalChanged,
    this.seededTarget,
    this.targetFrom,
    this.currentKg,
    this.caloriesFrom,
    this.caloriesTo,
    this.proteinFrom,
    this.proteinTo,
  });

  /// What to merge into the stored profile: `primary_goal`, the seeded
  /// `target_weight_kg` (only when seeded), and the whole recomputed target set
  /// (only when the goal changed or a target was seeded, and the profile is
  /// complete enough to compute one).
  final Map<String, dynamic> patch;

  /// The new goal differs from the stored one (a legacy stored token counts).
  final bool goalChanged;

  /// The seeded target in kg, when the old one could not stand beside the goal.
  final double? seededTarget;

  /// The stored target the seed replaces (null or 0.0 when there was none).
  final double? targetFrom;

  /// The profile's current weight the rule was judged against (kg), when known.
  final double? currentKg;

  final num? caloriesFrom;
  final num? caloriesTo;
  final num? proteinFrom;
  final num? proteinTo;

  bool get targetSeeded => seededTarget != null;

  /// The recompute produced calorie targets (the profile was complete).
  bool get hasTargets => caloriesTo != null;

  /// A calorie or protein number moved, so a preview has something to say.
  bool get targetsMoved =>
      hasTargets && (caloriesFrom != caloriesTo || proteinFrom != proteinTo);
}

/// Decides what changing [profile]'s goal to [newGoal] writes.
///
/// 1. The target is seeded ONLY when it cannot stand beside the new goal (missing,
///    not positive, or against the direction) and a seed that fits exists.
/// 2. The calorie, protein, carb and fat targets are recomputed from the healed
///    profile (new goal, seeded target) when the goal changed or a target was
///    seeded; the FULL overlay is kept (`carb_grams` and `carbs_grams` both). An
///    incomplete profile (no height, birth date or sex) yields goal and seed only,
///    never a partial overlay.
/// 3. A same-goal call on a consistent profile writes the goal and nothing else, so
///    it never moves a stored value silently.
///
/// [profile] is only read; the patch is built from copies.
GoalChange goalChange(
  Map<dynamic, dynamic> profile, {
  required String newGoal,
  required DateTime now,
  required bool bodyFatCalcDisabled,
}) {
  final stored = <String, dynamic>{
    for (final e in profile.entries) e.key.toString(): e.value,
  };
  final goalChanged = stored['primary_goal'] != newGoal;
  final currentKg = _positive(stored['current_weight_kg']);
  final rawTarget = stored['target_weight_kg'];
  final storedTarget = rawTarget is num ? rawTarget.toDouble() : null;

  double? seeded;
  if (targetNeedsSeed(
      goal: newGoal, currentKg: currentKg, targetKg: storedTarget)) {
    seeded = goalTargetSeed(goal: newGoal, currentKg: currentKg);
  }

  final patch = <String, dynamic>{'primary_goal': newGoal};
  if (seeded != null) patch['target_weight_kg'] = seeded;

  Map<String, dynamic>? overlay;
  if (goalChanged || seeded != null) {
    final healed = <String, dynamic>{...stored, ...patch};
    try {
      overlay = recomputeDerivedTargets(
        healed,
        now: now,
        bodyFatCalcDisabled: bodyFatCalcDisabled,
      );
    } catch (_) {
      // A corrupt stored value (NaN weight, a non-numeric height) makes the
      // calculator throw. The goal change itself must still go through, so the
      // patch falls back to the goal and the seed only, the same shape an
      // incomplete profile gets. This runs under the profile lock, after the
      // plan-window sweep: throwing here would leave the rows swept and the goal
      // unchanged.
      overlay = null;
    }
    if (overlay != null) patch.addAll(overlay);
  }

  num? n(Object? v) => v is num ? v : null;
  return GoalChange(
    patch: patch,
    goalChanged: goalChanged,
    seededTarget: seeded,
    targetFrom: storedTarget,
    currentKg: currentKg,
    caloriesFrom: n(stored['daily_calories']),
    caloriesTo: n(overlay?['daily_calories']),
    proteinFrom: n(stored['protein_grams']),
    proteinTo: n(overlay?['protein_grams']),
  );
}
