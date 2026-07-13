---
branch: workout-progression
review_type: b-pass
blast_radius: platform
verdict: accepted
---

# B-Pass Review — workout-progression (Batch 3a: ④ goal-aware cardio finisher default)

Context-blind adversarial review + B-pass on the implemented diff (self-initiated before the
`--no-ff` merge, §4.3; platform-tier). Every claim verified against the actual code across six
dimensions.

## Verified (all six PASS)

1. **Mapping validity** — `_buildFinisher` has real cases for `cycling`/`hiit`/`jump_rope`; none
   falls through to the mini-HIIT `default` arm.
2. **Goal reachability** — exactly 3 `cardio: true` goals (lose_fat/general_fitness/recompose); no
   4th (no `endurance`). `_defaultForGoal`'s 3 cases cover them; the `default→'hate_cardio'` arm is
   byte-identical to pre-④ and only reachable by an unknown token.
3. **Kill-switch** — `cardioGoalDefaultEnabled` is character-for-character the sibling pattern
   (absent/false→ON, true→OFF, Hive-throws→ON); OFF reverts to the verbatim pre-④ `'hate_cardio'`.
4. **Purity/threading** — reading `PlanEngineFlags` inside the plan-engine module matches the
   `warmup_cooldown.dart` precedent; `??` means `_defaultForGoal` runs only when `cardioPreference`
   is null; full-repo grep confirms NO `lib/` caller passes a non-null preference. The subtle hinge
   — `plan_generator.dart:170` passes the ORIGINAL `goal` (not `planGoal`) — is correct, so
   `recompose→jump_rope` (not routed through the default arm).
5. **Test non-vacuous** — each positive test fails on old code (all 3 goals defaulted to mini-HIIT);
   `Jump Squats` is a HIIT-only discriminator; `High Knees` is the mini-HIIT first move; cycling
   assertion is equipment-deterministic (`['full_gym']`→`Stationary Bike Sprints`); the kill-switch
   test forces a real Hive `configBox` flag; `build_muscle/strength → isEmpty` is safe (finisher
   defaults to `const []`).
6. **No scorecard regression** — the Batch-0 `generator_matrix` mirror never calls
   `CardioFinisher.attach` and its personaMatrix excludes recompose/cardio-pref personas; finishers
   are structurally invisible to the scorecard. SoT `cardio_goal_default` complete (Gate 42).

## Findings

**P0/P1/P2: none.**

**P3:**
1. Stale class docstring ("shape is driven by cardioPreference, not the goal") — **FIXED in-batch**
   (§4.2): amended to note the goal-keyed default + kill-switch.
2. Kill-switch OFF path tested for only `lose_fat`. **Left as-is** — the reviewer confirmed the
   revert is goal-independent (`_defaultForGoal` returns `'hate_cardio'` before the switch), so one
   goal is sufficient proof.

VERDICT: accepted
