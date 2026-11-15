// Unit 1B-R (seed v26, founder d24, docs/plans/2026-11-12-generator-1br-loaded-wins.md): G0355 Dumbbell Single Arm
// Lateral Raise gained `beginner` in core_levels. The seed tests that rebuild an OLDER bundle from the current asset
// (v23, v24 and v25) put G0355 back to its v25 levels here, restated (never read from git: CI checks out shallow), so
// their digest pins keep proving the older bundles byte for byte. Assigning an existing key keeps its position in the
// map, so the JSON key order is unchanged.

const g0355Id = 'G0355';

/// G0355's core_levels as seeds v15 to v25 shipped them.
const g0355CoreLevelsV25 = <String>['intermediate', 'advanced'];

/// [r] with G0355's v25 core_levels; every other row unchanged (the same instance).
Map<String, dynamic> withG0355V25(Map<String, dynamic> r) =>
    r['id'] == g0355Id ? (Map<String, dynamic>.from(r)..['core_levels'] = g0355CoreLevelsV25) : r;
