// lib/features/nutrition/services/diet_plan_stale_targets.dart
//
// goal-change-targets B4 (founder decision 3): a saved diet chart is never regenerated silently and
// hand swaps are never erased silently; when the calorie / protein targets moved since the plan was
// built, the Diet chart shows a banner and the user chooses. The plan carries the targets it was
// built for (`diet_target_calories`, `diet_target_protein`, the "target stamp", beside
// `diet_strategy` / `diet_supplements`). Pure.

/// The two numbers a plan was built for, or the targets now.
typedef TargetStamp = ({int calories, int protein});

/// The plan's stamp keys.
const String kDietTargetCaloriesKey = 'diet_target_calories';
const String kDietTargetProteinKey = 'diet_target_protein';

/// The stamp a saved plan carries, or null for a plan saved before the stamp existed (or a
/// half-written one): such a plan shows no banner until it is regenerated and saved again.
TargetStamp? dietTargetStampOfSaved(Map<dynamic, dynamic> planData) {
  final c = planData[kDietTargetCaloriesKey];
  final p = planData[kDietTargetProteinKey];
  if (c is! num || p is! num || !c.isFinite || !p.isFinite) return null;
  return (calories: c.round(), protein: p.round());
}

/// The (stamp, current) pair to show in the banner, or null when there is nothing to say: no stamp,
/// the targets on screen are the fallback defaults (the profile cannot produce real ones), or both
/// rounded numbers still match.
({TargetStamp stamp, TargetStamp current})? staleTargetsOf(
  TargetStamp? stamp, {
  required double calories,
  required double protein,
  required bool usingFallback,
}) {
  if (stamp == null || usingFallback) return null;
  final current = (calories: calories.round(), protein: protein.round());
  if (stamp.calories == current.calories && stamp.protein == current.protein) {
    return null;
  }
  return (stamp: stamp, current: current);
}
