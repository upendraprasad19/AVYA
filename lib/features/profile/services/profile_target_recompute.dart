import 'package:icanbefitter/core/services/water_target_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

/// The profile keys the derivation READS. Exposed so callers can ask the one
/// question that decides whether a recompute is warranted at all: did anything
/// this calculation depends on actually change?
///
/// ⚠ This list is the recompute's own input contract. Adding a `profile[...]`
/// read to [recomputeDerivedTargets] without adding the key here makes the
/// restore gate blind to it, and the derived set silently stops tracking that
/// input. Pinned by `profile_target_recompute_test.dart`.
const List<String> derivedTargetInputKeys = <String>[
  'current_weight_kg',
  'height_cm',
  'date_of_birth',
  'gender',
  'primary_goal',
  'lifestyle_activity',
  'days_per_week',
  'pace_preference',
  'target_weight_kg',
  'body_fat_percent',
  'activity_level',
];

/// True when [after] differs from [before] on any key the derivation reads.
///
/// This is what keeps the restore recompute NARROW, and it is load-bearing for
/// a founder-locked decision, not merely an optimisation.
/// `body_fat_default_healer.dart:28` states: *"NO `daily_calories` recompute
/// (founder-locked: no silent backfill)"* — the healer deliberately nulls a
/// fabricated `body_fat_percent` and leaves the calorie target alone, because
/// silently moving someone's daily calorie goal with no action on their part is
/// worse than leaving a slightly-wrong number in place.
///
/// A blanket recompute-on-every-restore would have overridden that decision
/// through a different door. It does not, because the healer clears the CLOUD
/// column first and then the local one — so by the next restore both sides are
/// null, the merge changes nothing, and no recompute fires. The lock is
/// honoured structurally rather than by a special case for body fat.
bool derivedTargetInputsChanged(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  for (final k in derivedTargetInputKeys) {
    if (before[k] != after[k]) return true;
  }
  return false;
}

/// Recomputes the DERIVED half of the profile map from its INPUT half (OI-150).
///
/// The profile splits cleanly into inputs the user supplies (weight, height,
/// date of birth, gender, goal, lifestyle, days/week) and values COMPUTED from
/// them (`bmr`, `tdee`, `daily_calories`, `protein_grams`, `carbs_grams`,
/// `fat_grams`, `activity_level`, `water_target_ml`).
///
/// `_restoreUserProfile` merges cloud over local per key with no guard of any
/// kind, so it can take cloud's weight while keeping the phone's calorie
/// target — leaving a target computed from a weight that is no longer in the
/// map. Rather than versioning the profile (it has no client-written version
/// stamp; `updated_at` is server-set and absent from the 34-field client
/// payload), merge the inputs and RECOMPUTE the outputs. Nothing is left to
/// keep consistent because consistency is regenerated.
///
/// `ProfileProvider.recalculateTargets` delegates here rather than repeating
/// the derivation — it previously lived in the provider AND was mirrored again
/// in `profile_edit_recompute_consistency_test.dart`, and a third copy on the
/// restore path is the drift class this repo tracks (debugging skill §2.53).
///
/// ⚠ It is NOT the only derivation in the tree, and saying so would invite
/// nobody to look (review round 2 / N4). Two others exist:
///   * `UserRepository.ensureComputedTargets` — different semantics (raw
///     `activity_level`, `age = 25` fallback, no `> 0` guard on
///     `target_weight_kg`) and **zero production callers**, so it is latent
///     rather than live;
///   * onboarding's preview/commit pair (`plan_screen.dart:653`,
///     `onboarding_provider.dart:421`), which calls `BmrCalculator` directly.
/// This one is canonical for the EDIT and RESTORE paths.
///
/// Returns `null` when the inputs are incomplete. Callers must then leave the
/// map untouched rather than writing partial or invented values.
///
/// ⚠ `bodyFatPercent` is passed through NULLABLE and is NEVER defaulted.
/// Diagnose `c3f2d8`: a `?? 18.0` here fed a fabricated body-fat into every
/// skip-user's Katch-McArdle calculation, and `body_fat_default_healer.dart`
/// exists to undo it.
Map<String, dynamic>? recomputeDerivedTargets(
  Map<String, dynamic> profile, {
  required DateTime now,
  bool bodyFatCalcDisabled = false,
}) {
  final weight = (profile['current_weight_kg'] as num?)?.toDouble();
  final height = (profile['height_cm'] as num?)?.toDouble();
  final dob = profile['date_of_birth'] as String?;
  final gender = profile['gender'] as String?;
  final goal = profile['primary_goal'] as String?;

  if (weight == null ||
      height == null ||
      dob == null ||
      gender == null ||
      goal == null) {
    return null;
  }

  final birthDate = DateTime.tryParse(dob);
  if (birthDate == null) return null;

  // CALENDAR age, matching onboarding (onboarding_provider.dart:384-392).
  // The `inDays ~/ 365` form this replaced disagrees with onboarding for
  // ~2.1% of birthdays on any given day (232 of 10,958 DOBs swept 1980-2009 at
  // 2026-08-30), which meant onboarding and the profile-edit recompute could
  // store different daily_calories for the same person.
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  if (age <= 0) return null;

  // Prefer resolving from lifestyle + days (the current system) over the older
  // stored `activity_level` string, which the user picked directly.
  final lifestyle = profile['lifestyle_activity'] as String?;
  final days = (profile['days_per_week'] as num?)?.toInt() ?? 4;
  final resolvedActivity = lifestyle != null
      ? BmrCalculator.resolveActivityLevel(lifestyle, days)
      : (profile['activity_level'] as String? ?? 'moderate');

  final targetWeight = (profile['target_weight_kg'] as num?)?.toDouble();
  // Routed through the SHARED selector so the `disable_bodyfat_calc`
  // kill-switch reaches this path too. Without it the switch was
  // half-effective: Mifflin at onboarding, Katch-McArdle here, on the same
  // device — the exact preview-vs-saved drift that selector exists to prevent.
  final bodyFat = BmrCalculator.bodyFatForCalc(
    (profile['body_fat_percent'] as num?)?.toDouble(),
    disabled: bodyFatCalcDisabled,
  );

  final targets = BmrCalculator.calculateTargets(
    weightKg: weight,
    heightCm: height,
    age: age,
    gender: gender,
    activityLevel: resolvedActivity,
    goal: goal,
    pacePreference: (profile['pace_preference'] as String?) ?? 'balanced',
    targetWeightKg:
        targetWeight != null && targetWeight > 0 ? targetWeight : null,
    bodyFatPercent: bodyFat,
  );

  return <String, dynamic>{
    ...targets.toMap(),
    'activity_level': resolvedActivity,
    // N3 (review round 2): `water_target_ml` is the EIGHTH derived field —
    // computed from weight / days_per_week / lifestyle_activity, all of which
    // are already inputs above — and the per-key merge could leave it beside a
    // weight it was not computed from, exactly like the macros.
    //
    // Local impact is nil because `WaterTargetService.currentTargetMl()`
    // recomputes at read time and never reads the stored value; what goes
    // stale is the CLOUD mirror, which server-side consumers read. A
    // user-set override lives under a separate key and is unaffected.
    'water_target_ml': WaterTargetService.computeFromProfile(profile),
  };
}
