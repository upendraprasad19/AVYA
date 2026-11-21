// scripts/equipment_vocab_lockstep_lib.dart
//
// Pure logic for `check_equipment_vocab_lockstep.dart` (⑦ OI-89).
//
// `EquipmentVocab` keeps FOUR structures describing the same token set, and
// three of them fail SILENTLY when they disagree — they produce a quietly wrong
// answer rather than an error, which is how the OI-89 class survived:
//
//   `canonicalTokens`  the set itself
//   `_precedence`      `normalizeToken` does `_precedence.indexOf(c)` and the
//                      `rank >= 0` guard SKIPS an absent token, so an
//                      OR-compound resolves to `[]` = "no equipment required" —
//                      the most permissive possible answer, and exactly backwards
//                      for a capability floor.
//   `_chipLabels`      `chipLabel` falls back to the raw token, shipping
//                      `elevated surface` as user-visible UI copy.
//   `_aliases`         `_mapPart` checks `canonicalTokens` FIRST, so an alias key
//                      that is also canonical is unreachable dead code.
//
// Kept pure (no dart:io, no Hive) so the gate's own test can drive it directly.
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

/// Tokens never rendered as a Customize chip, so exempt from the label rule.
/// `bodyweight` is the floor — it is granted unconditionally and never offered.
const _chipLabelExempt = <String>{'bodyweight'};

/// Returns a human-readable violation per disagreement; empty means in lockstep.
///
/// Every message names the offending token — a gate that says only "mismatch"
/// costs an hour each time it fires.
List<String> lockstepViolations({
  required Set<String> canonical,
  required List<String> precedence,
  required Map<String, String> chipLabels,
  required Set<String> aliasKeys,
}) {
  final violations = <String>[];

  // 1. every canonical token must rank in _precedence
  for (final t in canonical) {
    if (!precedence.contains(t)) {
      violations.add(
        "'$t' is canonical but absent from _precedence — normalizeToken's "
        "`rank >= 0` guard will silently DROP it from every OR-compound, "
        "yielding [] (no requirement), the most permissive answer.",
      );
    }
  }

  // 2. no _precedence entry may be non-canonical (a rename leaves a ghost)
  for (final t in precedence) {
    if (!canonical.contains(t)) {
      violations.add(
        "'$t' ranks in _precedence but is not a canonical token — a stale "
        'entry left by a rename; it can never be produced by _mapPart.',
      );
    }
  }

  // 3. no duplicates — indexOf silently honours only the first
  final seen = <String>{};
  for (final t in precedence) {
    if (!seen.add(t)) {
      violations.add("'$t' appears more than once in _precedence (duplicate) — "
          'indexOf honours only the first, so the later rank is dead.');
    }
  }

  // 4. every canonical token needs a real chip label
  for (final t in canonical) {
    if (_chipLabelExempt.contains(t)) continue;
    final label = chipLabels[t];
    if (label == null || label.isEmpty || label == t) {
      violations.add(
        "'$t' has no chipLabel entry — chipLabel() falls back to the raw token, "
        'so this ships as user-visible UI copy.',
      );
    }
  }

  // 5. no alias key may shadow a canonical token
  for (final k in aliasKeys) {
    if (canonical.contains(k)) {
      violations.add(
        "'$k' is BOTH an alias key and a canonical token — _mapPart checks "
        'canonicalTokens first, so the alias row is unreachable dead code. '
        'Delete the alias (it shadows).',
      );
    }
  }

  return violations;
}

/// The same check against the shipped `EquipmentVocab` constants.
List<String> liveLockstepViolations() {
  final canonical = EquipmentVocab.canonicalTokens;
  // chipLabel() returns the raw token on fallback, so a self-equal result means
  // "no entry" — build the map from observed behaviour rather than reaching for
  // the private field.
  final labels = <String, String>{
    for (final t in canonical)
      if (EquipmentVocab.chipLabel(t) != t) t: EquipmentVocab.chipLabel(t),
  };
  return lockstepViolations(
    canonical: canonical,
    precedence: EquipmentVocab.precedenceOrder,
    chipLabels: labels,
    aliasKeys: EquipmentVocab.aliasKeys,
  );
}
