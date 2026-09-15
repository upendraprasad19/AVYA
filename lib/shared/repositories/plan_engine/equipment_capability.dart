import '../../../core/utils/equipment_vocab.dart';

/// ⑦ OI-89: can this user physically perform this exercise?
///
/// Keyed on `equipment_needed`, NEVER on `equipment_tier`. `docs/sot_registry.yaml`
/// (concept `exercise_equipment_tier`) documents that field as ADD-only with
/// "over-tags tolerated" — imprecise in exactly the unsafe direction for a
/// capability check. The first attempt at OI-89 keyed on it and shipped Chin Up
/// to bodyweight users anyway.
///
/// NOT named "bodyweight floor": that term already means the un-excludable
/// `none`/`bodyweight` tokens in six places (equipment_vocab, plan_generator,
/// training_history_analyzer, the SoT registry, plan_engine/CLAUDE.md, and
/// OI-89's own board entry). This predicate is TIER-AGNOSTIC — only its
/// enforcement is scoped.
class EquipmentCapability {
  EquipmentCapability._();

  /// True iff every token [equipmentNeeded] requires is in [effective].
  ///
  /// FAILS CLOSED on unreadable input. `EquipmentVocab.normalize` DROPS
  /// unmappable tokens, so a row whose requirement cannot be parsed yields `[]`
  /// — and `[].every(...)` is vacuously TRUE. That permissiveness is correct for
  /// `queryV4`'s soft curation (it must never over-exclude) and wrong for a hard
  /// capability check, where an unreadable requirement means "we do not know",
  /// not "no requirement".
  ///
  /// 0 of 259 seed rows are affected. The live population is community-synced
  /// rows (`normalizedEquipmentRow`) and user/AI-authored customs
  /// (`createCustomExercise`), both of which can store `[]` by design.
  static bool canPerform(Object? equipmentNeeded, Set<String> effective) {
    final needed = EquipmentVocab.fromProfile(equipmentNeeded);
    if (needed.isEmpty) return false; // fail CLOSED — see doc above
    return needed.every(effective.contains);
  }
}
