/// ①.1d (Batch 11-C) — curated per-injury safe-substitute PREFERENCE.
///
/// When the cascade fills an exercise slot, `queryV4`'s injury filter
/// (`injuryExclusions`) has ALREADY removed every contraindicated exercise.
/// This map lets `_cascadeFill` PREFER a curated, joint-friendlier safe
/// substitute among the already-safe, same-`movement_pattern` candidates —
/// instead of whatever `queryV4`'s compound/priority/foundational sort ranked
/// first. It therefore CAN NEVER surface a contraindicated exercise (it only
/// re-ranks the post-filter candidate list), and it is a PREFERENCE: when no
/// curated sub is a candidate for the slot, the cascade pick is unchanged.
///
/// Keys = `InjuryVocab` canonical tokens. Values = ordered preferred substitute
/// EXACT library names (foundational / machine / dumbbell variants first =
/// joint-friendlier), each VERIFIED present + same-pattern + NOT tagged for the
/// injury against `assets/data/exercise_library.json` (Batch 11-C, 258 rows).
/// Hive/Flutter-FREE so the pure-Dart cascade tracer can import it.
///
/// Covers 6 of the 9 `InjuryVocab` tokens — `ankle`/`neck`/`hamstring` have no
/// curated list (1-2 contraindicated rows each) → safe fallthrough by
/// construction. `Romanian Deadlift` + variants are intentionally EXCLUDED from
/// `lower_back` (their empty `injury_contraindications` is an under-tagging gap,
/// not vetted safety — Round-1 review P1).
class InjurySubstitutes {
  InjurySubstitutes._();

  static const Map<String, List<String>> _preferred = {
    'shoulder': [
      // horizontal_push (8 contra / 18 safe)
      'Machine Chest Press', 'Dumbbell Bench Press', 'Push Up',
      // vertical_push (10 / 2 — thin pool, curation matters most here)
      'Kettlebell Goblet Press', 'Front Raise',
      // shoulder_isolation (4 / 4)
      'Face Pull', 'Band Pull Apart',
      // vertical_pull (4 / 6)
      'Lat Pulldown', 'Chin Up',
      // elbow_extension (3 / 6)
      'Tricep Pushdown (Cable)',
    ],
    'knee': [
      // knee_dominant (27 / 10)
      'Leg Press', 'Leg Curl (Lying)', 'Wall Sit',
      // hip_isolation (2 / 9)
      'Glute Bridge',
    ],
    'lower_back': [
      // hip_dominant — RDL variants dropped (under-tagging gap, Round-1 P1)
      'Hip Thrust',
      // horizontal_pull (3 / 12 — supported bench = spine unloaded)
      'Chest Supported Row', 'Seal Row',
    ],
    'wrist': [
      'Machine Chest Press', // horizontal_push (6 / 20)
      'Landmine Press', // vertical_push (2 / 10 — not wrist-tagged)
      'Cable Curl', // elbow_flexion (3 / 10)
    ],
    'elbow': [
      'Tricep Pushdown (Cable)', // elbow_extension (5 / 4)
      'Cable Curl', // elbow_flexion (4 / 9)
    ],
    'hip': [
      'Leg Press', 'Leg Extension', // knee_dominant (18 / 19)
      'Glute Bridge', // hip_isolation (3 / 8)
    ],
  };

  /// The ordered, deduped, LOWERCASED preferred-substitute names for [injuries]
  /// (canonical `InjuryVocab` tokens). Union in caller order, first-occurrence
  /// wins the dedup (deterministic). Empty when no injury has a curated list →
  /// the re-rank is a no-op. Lowercased for EXACT (never substring) matching
  /// against a candidate's `name` (the "Push Up" ⊄ "Pike Push Up" bug class —
  /// mirrors the house `_isContraindicated` lowercase-both-sides precedent).
  static List<String> preferredFor(List<String> injuries) {
    final out = <String>[];
    final seen = <String>{};
    for (final injury in injuries) {
      final list = _preferred[injury.toLowerCase().trim()];
      if (list == null) continue;
      for (final name in list) {
        final lc = name.toLowerCase();
        if (seen.add(lc)) out.add(lc);
      }
    }
    return out;
  }
}
