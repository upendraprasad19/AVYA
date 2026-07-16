---
branch: workout-equipment-filter
scope: ⑥ slice B1 — queryV4 equipment item-level exclusion filter (pure-exclusion, ship-dark)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-equipment-filter-bpass.md
---

# Plan-review record — ⑥ slice B1 (equipment item-level exclusion filter)

Plan: [`docs/plans/equipment-exclusion-filter-batch.md`](../plans/equipment-exclusion-filter-batch.md).
§4.12 ×2 context-blind review of the pre-implementation plan; review #2 on the hardened plan. Every
load-bearing claim verified against `exercise_selector.dart` / `exercise_repository.dart` /
`plan_generator.dart` / the asset (never subagent prose). **Converged — ready to implement.** PLATFORM tier
(plan_engine); `bpass: accepted` added after the pre-merge B-pass on the implemented diff.

## Ground-truth verified (self + reviewers, against actual code)
- **Live V4 filter reads `equipment_tier`, NOT `equipment_needed`** (queryV4 `exercise_repository.dart:270`);
  the `equipment_needed` filter is the DEAD V3 `query()` (0 callers). The exclusion filter is NET-NEW.
- **Intersection design REGRESSES 41 tier-selectable exercises at empty exclusions** (4 bodyweight / 25
  home_dumbbells / 12 basic_gym) — SELF-VERIFIED by enumerating the asset; `equipment_tier` membership ≠
  `equipment_needed ⊆ _getEquipmentList(tier)`. ⇒ rejected; **PURE EXCLUSION** (drop iff `equipment_needed`
  intersects the floor-sanitized exclusions; `equipment_tier` filter untouched; no-op at empty → 0 regression).
- **Four queryV4-adjacent pick paths** (all must honor exclusions — equipment exclusion is a HARD constraint):
  queryV4 att1-4 (`:792/808/820/830`, drop BEFORE the `:268` no-tier short-circuit), att4 (`:830`, tier
  dropped) KEEPS exclusions, the att5 universal pool (`:847-873`, mirror U2's `_isContraindicated` skip), the
  L2 custom-append (`:653-671`) + L6 swap (`:633`). pickV4 has NO other exercise source (round-2-confirmed).
- **att5 skip is slot-safe** — SELF-VERIFIED all 11 movement patterns' `universalPoolV4` have ≥1 pure-bodyweight
  exact-name move that survives exclude-everything (vertical_pull/elbow_flexion via Inverted Row `['bodyweight']`).
- **`EquipmentVocab.fromProfile`** (`equipment_vocab.dart:201-205`) is the read: crash-safe (the e9d1c7 class)
  + normalizes → fixes the `as List` crash + community-row under-exclusion + case-folding in ONE change, and
  **decouples B1 from B2**. Computed once at generateV4, mirroring the injury seam (`plan_generator.dart:90`).
- **Hard scorecard gates SATISFIABLE** — `missing==0` via the att5 floor; `fullGymEquipViolations==0` only
  counts full_gym personas (place exclusion personas at basic_gym/home_dumbbells); `totalFallback ≤ baseline`
  via re-freeze. SELF-VERIFIED against `scorecard_gate_test.dart:44-78`.

## Round 1 (multi-lens context-blind WORKFLOW — 27 agents, 4 lenses × per-finding adversarial verify)
22 of 23 findings survived verification. It rejected the intersection design and hardened the pure-exclusion
redesign: the exclusion filter must apply at ALL four pick paths (att5 pool + att4-keeps + L2 custom were
un-covered); the predicate must use crash-safe normalizing `fromProfile` (a raw `as List` reintroduced e9d1c7
+ under-excluded community rows + wasn't case-folded); the behavioral test must flip the flag ON via configBox
(default-OFF-without-Hive made a pure-unit call vacuous); a stale line-17 subset-predicate reference; rule-#14
(the founder-approved overhaul authorizes plan_generator.dart edits). All 22 folded into the hardened plan.

## Round 2 (context-blind, on the HARDENED plan)
**No P0, no P1.** Verified airtight: the no-op (empty-set `.isNotEmpty` guards + required-leaf/defaulted-
intermediate threading), determinism (no RNG/time in the pick path; `Phase.toMap` byte-comparable), all four
pick paths reached with no missed source, `fromProfile` crash-safety, floor-sanitize, `fullGymEquipViolations`
compatibility, mirror-vs-prod flag asymmetry (breaks no parity test), flag-flip + synthetic-row test mechanics.
Verdict CONVERGED, explicitly "do NOT run a 5th review or split." 5 P2 clarifications — test-harness naming
(no generateV4 Hive-boot harness exists → build one + extract a unit-testable seam helper), scorecard threading
(Persona field + generatePlan + CascadeTracer.trace param), drop the redundant `applyEquipmentExclusions` bool,
cardio-finisher/warmup scope boundary (→ WU-2/slice C, conscious), leaf-required wording — ALL folded.

## Verdict: converged
The pure-exclusion design (crash-safe normalizing read, flag-gated + floor-sanitized single seam at generateV4,
`.isNotEmpty`-guarded inert guards, exclusion at all four pick paths, required-leaf/defaulted-intermediate
threading, mirror + baseline discipline) is correct and implementable as specified. B-pass runs on the
implemented diff before the `--no-ff` merge (§4.3 / platform `requires: bpass`).
