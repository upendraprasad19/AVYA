// lib/core/constants/diet_strategies.dart
//
// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §3.1): the diet
// STRATEGY vocabulary (PRO). Stored as the profile key `diet_strategy` (Hive
// profile and the cloud column `user_profile.diet_strategy`).
//
// A strategy changes only how the carb and fat targets are SHOWN
// (`effectiveMacroTargets`, lib/core/utils/effective_macro_targets.dart). The
// stored targets are always the Balanced split; calories and protein never
// change. The strategy is chosen only through the selector, never by the
// coach's profile extraction (a chat "I'm keto" folds to Non-veg in
// `foodTypeOf`).
//
// Fail-safe direction: Balanced is today's behaviour, so ANY value this table
// cannot read (null, empty, unknown, not a string) is Balanced.
library;

enum DietStrategy {
  balanced('balanced', 'Balanced', ''),
  lowCarb('low_carb', 'Low carb', 'LOW CARB'),
  keto('keto', 'Keto', 'KETO');

  const DietStrategy(this.storageKey, this.label, this.tag);

  /// The value written to `diet_strategy` (Hive profile and cloud).
  final String storageKey;

  /// Chip label.
  final String label;

  /// Upper-case tag after the food type (`NON-VEG · KETO`). Empty for
  /// Balanced, which adds nothing to the label.
  final String tag;
}

/// The strategy assumed when none was ever chosen, or none can be read.
const DietStrategy kDefaultDietStrategy = DietStrategy.balanced;

/// Tolerant read of a stored value.
DietStrategy dietStrategyOf(Object? raw) {
  if (raw is! String) return kDefaultDietStrategy;
  final key = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  for (final s in DietStrategy.values) {
    if (s.storageKey == key) return s;
  }
  return kDefaultDietStrategy;
}

/// The strategy a targets map carries (`'strategy_index'`, written by
/// `_resolveNutritionTargets`). Absent or out of range = Balanced. The ONE
/// read of that key (plan §3.3): screens show the strategy that came with the
/// numbers, never a separately read profile value.
DietStrategy dietStrategyOfTargets(Map<String, dynamic>? targets) {
  final raw = targets?['strategy_index'];
  if (raw is! num) return kDefaultDietStrategy;
  final i = raw.toInt();
  if (i < 0 || i >= DietStrategy.values.length) return kDefaultDietStrategy;
  return DietStrategy.values[i];
}

/// The food-type tag with the strategy appended (`NON-VEG · KETO`); Balanced
/// adds nothing. Used by the calorie card, the Diet Plan header and the PDF.
String withDietStrategyTag(String foodTypeTag, DietStrategy strategy) =>
    strategy.tag.isEmpty ? foodTypeTag : '$foodTypeTag \u00B7 ${strategy.tag}';

/// The `diet_strategy` entry of the profile push (`_syncUserProfile`, plan
/// §3.10). Empty unless [enabled] (DietStrategyFlags: ship-dark identity, a
/// flag-off build sends no new key even for a profile holding the field) and
/// the profile holds a non-blank value. The value is always a canonical key,
/// so a stray local value can never fail the column's CHECK and with it the
/// whole profile upsert.
Map<String, String> dietStrategyPushEntry(
  Map<dynamic, dynamic> profile, {
  required bool enabled,
}) {
  if (!enabled) return const {};
  final raw = profile['diet_strategy'];
  if (raw == null || (raw is String && raw.trim().isEmpty)) return const {};
  return {'diet_strategy': dietStrategyOf(raw).storageKey};
}
