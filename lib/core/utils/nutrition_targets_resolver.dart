// The ONE resolver of the nutrition targets a screen shows (plan
// docs/plans/nutrition-history.md 5.1 / U4): Nutrition, Home, the weekly
// Insights cards, the History screen and the target history all read it, so
// they can never disagree on a fallback (diagnose c2a4e8).
//
// Pure: no Hive, no Riverpod, core imports only.

import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/utils/effective_macro_targets.dart';

/// The targets to show, with the strategy they were made for.
typedef ResolvedTargets = ({
  double calories,
  double protein,
  double carbs,
  double fat,
  DietStrategy strategy,

  /// True when neither a stored pack nor the profile's inputs were available
  /// and the numbers are the hard-coded last resort.
  bool isFallback,
});

/// Last resort when the profile holds neither targets nor BMR inputs.
const ResolvedTargets kFallbackNutritionTargets = (
  calories: 2400,
  protein: 184,
  carbs: 280,
  fat: 80,
  strategy: DietStrategy.balanced,
  isFallback: true,
);

/// The Balanced pack the shown targets start from: the stored four-pack, else
/// the recompute from the profile's inputs. Null when only the hard-coded
/// defaults are left. Keys: `daily_calories`, `protein_grams`, `carb_grams`,
/// `fat_grams`. [now] feeds the age calculation (tests).
Map<String, double>? resolveBaseMacroTargets(
  Map<String, dynamic>? profile, {
  DateTime? now,
}) {
  // OBS-11 (2026-06-21) — dual-name read for `carb_grams`. The cloud column +
  // the restore/sync path (sync_profile `_restoreUserProfile`, sync_service)
  // use the PLURAL `carbs_grams`; this reader + onboarding use the SINGULAR
  // `carb_grams`. A RESTORED profile (established account) therefore carries
  // only `carbs_grams`; without the dual read the all-four canonical check
  // failed and this fell through to the RECOMPUTE branch, which re-derives
  // ALL four macros (so calories + protein drifted from the stored canonical,
  // e.g. 2540/140 -> 2583/150). (Writer/reader field drift — debugging skill
  // §2.1.)
  final carbCanonical = profile?['carb_grams'] ?? profile?['carbs_grams'];
  if (profile != null &&
      profile['daily_calories'] != null &&
      profile['protein_grams'] != null &&
      carbCanonical != null &&
      profile['fat_grams'] != null) {
    return {
      'daily_calories': (profile['daily_calories'] as num).toDouble(),
      'protein_grams': (profile['protein_grams'] as num).toDouble(),
      'carb_grams': (carbCanonical as num).toDouble(),
      'fat_grams': (profile['fat_grams'] as num).toDouble(),
    };
  }

  // Try to recalculate from profile inputs.
  if (profile != null) {
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final gender = profile['gender'] as String?;
    if (weightKg != null &&
        weightKg > 0 &&
        heightCm != null &&
        heightCm > 0 &&
        gender != null) {
      final goal = profile['primary_goal'] as String? ?? 'general_fitness';
      final activityLevel = profile['activity_level'] as String? ?? 'moderate';
      final dob = profile['date_of_birth'] as String?;
      int age = 25;
      if (dob != null) {
        final birthDate = DateTime.tryParse(dob);
        if (birthDate != null) {
          final today = now ?? DateTime.now();
          age = today.year - birthDate.year;
          if (today.month < birthDate.month ||
              (today.month == birthDate.month && today.day < birthDate.day)) {
            age--;
          }
          if (age <= 0) age = 25;
        }
      }
      final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();
      final targets = BmrCalculator.calculateTargets(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
        activityLevel: activityLevel,
        goal: goal,
        pacePreference: (profile['pace_preference'] as String?) ?? 'balanced',
        bodyFatPercent: bodyFat,
        targetWeightKg: (profile['target_weight_kg'] as num?)?.toDouble(),
      );
      return {
        'daily_calories': targets.dailyCalories.toDouble(),
        'protein_grams': targets.proteinGrams.toDouble(),
        'carb_grams': targets.carbGrams.toDouble(),
        'fat_grams': targets.fatGrams.toDouble(),
      };
    }
  }

  return null;
}

/// Stored pack -> recompute from inputs -> hard-coded last resort; then the
/// diet strategy ([effectiveMacroTargets]: a PRO user's non-Balanced strategy
/// changes carbs and fat, never calories or protein). With [strategyEnabled]
/// false the Balanced pack is returned untouched.
ResolvedTargets resolveNutritionTargets(
  Map<String, dynamic>? profile, {
  required bool strategyEnabled,
  required bool pro,
  DateTime? now,
}) {
  final base = resolveBaseMacroTargets(profile, now: now);
  if (base == null) return kFallbackNutritionTargets;
  final balanced = (
    calories: base['daily_calories']!,
    protein: base['protein_grams']!,
    carbs: base['carb_grams']!,
    fat: base['fat_grams']!,
    strategy: DietStrategy.balanced,
    isFallback: false,
  );
  if (!strategyEnabled) return balanced;
  final effective = effectiveMacroTargets(
    (
      calories: balanced.calories,
      protein: balanced.protein,
      carbs: balanced.carbs,
      fat: balanced.fat,
    ),
    profile!['diet_strategy'],
    pro: pro,
    enabled: strategyEnabled,
  )!;
  if (effective.strategy == DietStrategy.balanced) return balanced;
  return (
    calories: effective.calories,
    protein: effective.protein,
    carbs: effective.carbs,
    fat: effective.fat,
    strategy: effective.strategy,
    isFallback: false,
  );
}
