---
branch: workout-wu2-cardio-gate
scope: ⑥ C2 — WU-2 gym-cardio gate (fix hasGymEquipment always-false + honor exclusions in warmup/cardio)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-wu2-cardio-gate-bpass.md
---

# Plan-review record — ⑥ C2 (WU-2 gym-cardio gate)

Plan: [`docs/plans/wu2-gym-cardio-gate-batch.md`](../plans/wu2-gym-cardio-gate-batch.md).
§4.12 ×2 context-blind review; every load-bearing claim verified against `warmup_cooldown.dart` /
`cardio_finisher.dart` / `plan_generator.dart` / `equipment_vocab.dart` / `generator_matrix.dart` /
`shared_contracts_test.dart`. **Converged — implemented.** PLATFORM tier. WU-2 was founder-split from C1 as a
distinct unit (2026-07-17). Diagnose `b7a4e2` (a `fix:` — genuine writer/reader-drift bug). No migration.

## Ground-truth verified (self + reviewers, against code)
- **Always-false bug real:** `hasGymEquipment = equipmentList.any(contains('gym')||contains('full'))`
  (`warmup_cooldown.dart:141`, `cardio_finisher.dart:28`), but generateV4 passes `_getEquipmentList(tier)` =
  ITEM tokens (none/bodyweight/…) → always-false on the generated path. Writer/reader drift (reader expects the
  tier STRING; writer passes the item LIST). Path-scoped: template_service passes the tier string → old predicate
  correctly TRUE (must not regress).
- **Token = `cardio machine`** (gym-cardio pools normalize to it; in NO tier → must add to the gym tiers to match
  the old predicate's both-`gym`-string intent). Added to basic_gym + full_gym.
- **Design = generateV4 computes the flag-gated signal; attach default = old predicate.** Optional
  `bool? hasGymEquipmentOverride` (null → old predicate → template_service + `shared_contracts_test:825`
  byte-identical). generateV4: `hasGymOverride = flag ? effective(equipmentList − exclusions).contains('cardio
  machine') : null`, passed to both attach calls (`:196`/`:205`). Flag OFF → null → always-false → byte-identical.
- **No baseline move:** `generator_matrix.dart:112 equipmentItemsForTier` is DEAD CODE (0 call sites); the
  scorecard keys off `equipment_tier`, not the item list → scorecard gate 7/7 green (VERIFIED, unsafe 0, mean
  86.7). No regen. The gym-cardio warmup/finisher are not in `plan.allExercises` → the behavioral test is the
  sole proof (`wu2_gym_cardio_gate_behavioral_test.dart`, 3/3, 5-day week for pool rotation, general_fitness for
  the finisher hasGym branch).

## Round 1 (context-blind) — CONVERGED, 4 P2 folds
Core design verified sound; 4 wording/test-precision P2s (no re-architecture): (P2-1) the matrix mirror is dead
code → no regen; (P2-2) update the stale `equipment_vocab.dart:24-26` "11 non-cardio-machine tokens" comment;
(P2-3) precise flag-OFF wording (the GENERATED PLAN is byte-identical; the Customize UI gains one inert chip);
(P2-4) the finisher test MUST use general_fitness (→cycling→hasGym branch). All folded.

## Round 2 (context-blind, on the hardened plan) — CONVERGED
All 4 folds verified correct against code; core design re-confirmed (null-default keeps template_service +
tier-string tests byte-identical; the generateV4 signal correct; right tiers). New-defect hunt clean: the
override × injury-filter is orthogonal (override sets pool membership, injury filter runs after with the Slow
Walking floor); B1 × cardio-machine main-exercise exclusion is already tested green
(`equipment_exclusion_filter_behavioral_test:39-42` already lists cardio machine). 4 non-blocking polish items
(≥3-day warmup test, comment "12→13 items", dead-mirror note, fix+diagnose-doc) all folded.

## Verdict: converged
Add `cardio machine` to the gym tiers; the null-default `hasGymEquipmentOverride` on both attach methods; the
flag-gated generateV4 signal from the effective (exclusion-subtracted) equipment. Byte-identical flag-OFF on the
generated path; template_service + tier-string tests untouched; no baseline move. Diagnose `b7a4e2` + behavioral
test. B-pass runs on the implemented diff before the `--no-ff` merge (§4.3 / platform).

## Post-B-pass — shared-flag no-op consequence (surfaced by the pre-commit full suite)
WU-2 rides the SAME `enable_equipment_exclusions` flag as C1, so flag-ON-empty is byte-identical to flag-OFF only
for the MAIN selection — NOT the whole Phase: the gym-tier warmup/finisher gain gym cardio when the flag is ON
(the intended fix). B1's + C1's shipped whole-Phase NO-OP tests were adapted (test-only) to exempt the two
WU-2-owned fields (`warmup`+`finisher`, both day structures); coverage of that behavior moves to
`wu2_gym_cardio_gate_behavioral_test`. **Founder-relevant at flag-flip:** flipping the exclusions flag now also
activates the gym-cardio fix for every gym user (even with no exclusions) — the old "flip = no change until a
user acts" guarantee weakens for gym tiers. Full reasoning in the B-pass record. Verdict stays converged (a
direct consequence of the B-pass's confirmed finding; no production logic changed).
