// Batch 9 (W2.7 volume titration) — canonical library-muscle-token → major
// muscle-group map.
//
// Shared by the plan-quality scorecard (`test/plan_generator/plan_scorecard.dart`,
// whose `_groupOf` now delegates here) AND `VolumeTitration` — which aggregates
// the per-exercise e1RM trend and clamps weekly sets at the GROUP level, so the
// [MEV,MRV] band is a science-valid PER-GROUP landmark rather than a
// per-fragmented-sub-token one (the library splits e.g. chest into
// Chest/Upper Chest/Lower Chest…).
//
// The map CONTENT is byte-identical to the scorecard's original `_muscleToGroup`.
// It is deliberately NOT extended: extending it would move the frozen Batch-0 D3
// scorecard baseline (the D4 gate). ~17 qualifier-tagged isolation lifts
// (`Triceps (Long Head)`, `Lateral Delts`, `Lower Abs`, `Lats (Width)`, …) + ~8
// empty-`primary_muscles` rows therefore map to null and are simply never
// titrated — a CONSERVATIVE, safe miss (those small groups sit below MEV=8 in a
// real plan, so −1 never fired for them anyway).

const Map<String, String> _muscleToGroup = <String, String>{
  'chest': 'Chest', 'upper chest': 'Chest', 'lower chest': 'Chest',
  'mid chest': 'Chest',
  'lats': 'Back', 'upper back': 'Back', 'mid back': 'Back', 'lower back': 'Back',
  'traps': 'Back', 'rhomboids': 'Back', 'full back': 'Back', 'back': 'Back',
  'front deltoid': 'Shoulders', 'side deltoid': 'Shoulders',
  'rear deltoid': 'Shoulders', 'deltoids': 'Shoulders', 'shoulders': 'Shoulders',
  'biceps': 'Biceps', 'brachialis': 'Biceps',
  'triceps': 'Triceps',
  'forearms': 'Forearms',
  'quads': 'Quads', 'quadriceps': 'Quads',
  'hamstrings': 'Hamstrings',
  'glutes': 'Glutes', 'hip flexors': 'Glutes',
  'calves': 'Calves',
  'abs': 'Core', 'core': 'Core', 'obliques': 'Core', 'erector spinae': 'Core',
};

/// Maps a raw library primary/secondary muscle token → its canonical major
/// group, or `null` when unmapped (ignored for titration/coverage). Normalizes
/// `.toLowerCase().trim()` — matching the scorecard's original `_groupOf` exactly
/// so it can delegate here without shifting the frozen baseline.
String? muscleGroupOf(String token) =>
    _muscleToGroup[token.toLowerCase().trim()];

/// ADDITIVE read-only view of [_muscleToGroup]'s keys (2026-09-17,
/// custom-picker-fix). The map CONTENT stays frozen — this getter exists so
/// the custom-exercise sheet's muscle chips can assert their tokens are
/// library-canonical (every UI token must be a member; pinned by
/// test/contracts/custom_muscle_vocabulary_test.dart). A new UI token
/// requires adding its key here first, which is a deliberate act — not a
/// silent map edit.
Set<String> get canonicalMuscleTokens => _muscleToGroup.keys.toSet();
