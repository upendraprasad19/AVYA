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
/// injury against `assets/data/exercise_library.json` (Batch 11-C; re-verified for the v14 tags, 285 rows).
/// Hive/Flutter-FREE so the pure-Dart cascade tracer can import it.
///
/// Covers 5 of the 9 `InjuryVocab` tokens — `ankle`/`elbow`/`hamstring`/`neck` have no
/// curated list → safe fallthrough by construction. v14 (founder 2026-10-23) tagged
/// EVERY elbow_flexion / elbow_extension row for elbow, so an elbow user has no
/// same-pattern substitute to prefer; the key was removed rather than left dead.
/// `injury_recheck_v14_contract_test.dart` pins that every name below is a library
/// row NOT tagged for the injury it is listed under. `Romanian Deadlift` + variants stay EXCLUDED from `lower_back`
/// subs — as of 13-B they are properly `[lower_back,hamstring]`-tagged, so the
/// injury filter already removes them for lower_back users (the exclusion is now
/// moot-but-correct; the safe lower_back subs are the supported/hip-thrust rows).
class InjurySubstitutes {
  InjurySubstitutes._();

  static const Map<String, List<String>> _preferred = {
    'shoulder': [
      // horizontal_push — v14 tagged Dumbbell Bench Press and Push Up for shoulder
      // (founder 2026-10-23), so they are gone; Floor Press and Chest Squeeze Press
      // are untagged and take their place (plan Ruling 3)
      'Machine Chest Press', 'Floor Press', 'Chest Squeeze Press',
      // vertical_push — NO shoulder-safe overhead press remains: Front Raise (13-B) and
      // Kettlebell Goblet Press (v14) are both shoulder-tagged
      // shoulder_isolation
      'Face Pull', 'Band Pull Apart',
      // vertical_pull — Lat Pulldown is shoulder-tagged (v14); Machine High Row is untagged
      'Machine High Row', 'Chin Up',
      // elbow_extension — elbow-tagged only (v14), still shoulder-safe
      'Tricep Pushdown (Cable)',
    ],
    'knee': [
      // knee_dominant — Wall Sit removed (it is itself [knee]-tagged → was a dead sub, 13-B);
      // Leg Press removed too (v14: knee + lower_back).
      // Leg Curl (Lying) is now [hamstring]-tagged (13-B) but stays knee-SAFE (hamstring ≠ knee).
      'Leg Curl (Lying)',
      // hip_isolation (2 / 9)
      'Glute Bridge',
    ],
    'lower_back': [
      // hip_dominant — RDL variants are now [lower_back,hamstring]-tagged (13-B) so
      // the filter removes them anyway; Hip Thrust is the safe hinge sub
      'Hip Thrust',
      // horizontal_pull (3 / 12 — supported bench = spine unloaded)
      'Chest Supported Row', 'Seal Row',
    ],
    'wrist': [
      'Machine Chest Press', // horizontal_push (6 / 20)
      'Landmine Press', // vertical_push (2 / 10 — not wrist-tagged)
      'Cable Curl', // elbow_flexion (3 / 10)
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
