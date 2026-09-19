---
branch: workout-wu2-cardio-gate
scope: ⑥ C2 — WU-2 gym-cardio gate (fix hasGymEquipment always-false + honor exclusions, platform)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
---

# B-pass — ⑥ C2 WU-2 gym-cardio gate (diagnose b7a4e2)

Context-blind adversarial review of the implemented diff (11 staged files, platform tier). Every load-bearing
claim traced against the actual code. **No P0/P1 defects.**

## Verified-clean (by crux)
- **Byte-identical flag-OFF — CONFIRMED at the substring level.** `equipmentExclusionsEnabled` defaults false;
  flag OFF → `hasGymOverride = null` (`plan_generator.dart:208`) → both `attach` use `override ?? <old predicate>`
  (`warmup_cooldown.dart:146`, `cardio_finisher.dart:31`). Adding `'cardio machine'` to `tierItems` does NOT flip
  the old predicate (it contains neither 'gym' nor 'full'; equipmentList is item tokens) → always-false preserved
  verbatim. Effective-equipment subtraction correct + floor-sanitized (none/bodyweight survive).
- **No tier-string regression — CONFIRMED.** `shared_contracts_test.dart:826` (`['full_gym']`, no override) +
  `template_service.dart:169` (tier string, no override) → old predicate TRUE → unchanged. Optional named params
  → no signature break; all 31 generate callers unaffected (override is internal to generateV4). No `skip:` hiding
  the 126/126.
- **Null-safety / sense — CONFIRMED.** `bool? ?? bool` valid (not dead_null_aware); definite-assignment on both
  if/else paths; gym tier + flag-ON + not-excluded → gym cardio, exclude cardio machine → bodyweight.
- **Fallout — CONFIRMED.** chip-vocab 10→11 (full_gym) + 7 (basic_gym, added this commit); siblings pass
  (`cardio machine` was already canonical pre-C2; `_chipLabels` has it). The behavioral test genuinely hits the
  FINISHER hasGym branch (general_fitness→cycling→Stationary Bike Sprints) AND spans 5 days for the warmup pool
  rotation (day-index 2/3/4) — reverting the generateV4 override → red (rule 21). Stale `equipment_vocab.dart:24-26`
  comment updated. `generator_matrix.dart` mirror confirmed 0 call sites + commented dead.
- **Interactions — CONFIRMED clean.** Override × injury filter orthogonal (override sets `_gymCardio` pool
  membership; the injury drop + Slow Walking floor run AFTER → more safe options, never fewer). B1 × cardio
  machine: main selection uses `equipmentTier` + the exclusion set in pickV4, NOT `tierItems` → adding the token
  can't drop a main exercise; excluding it dropping a main is pre-existing B1 behavior (already tested green).
  Diagnose b7a4e2 accurate; plan-review record well-formed (review_rounds 2, converged, bpass accepted).

## Post-B-pass adaptation — shared-flag no-op (caught by the pre-commit full suite)
The B-pass confirmed "flag ON → gym cardio in warmup/finisher; flag OFF → byte-identical." The direct
consequence — which the pre-commit full `flutter test` surfaced — is that B1's + C1's shipped NO-OP tests
(`equipment_exclusion_filter_behavioral_test` + `equipment_exclusions_activation_behavioral_test`) assert
**flag ON + empty exclusions == flag OFF, byte-identical on the WHOLE Phase** for `full_gym`. WU-2, on the SAME
flag, intentionally adds gym cardio to the gym-tier warmup/finisher when the flag is ON → the full-Phase
assertion legitimately breaks. **Founder-relevant:** flipping `enable_equipment_exclusions` is therefore no
longer a pure no-op — it also activates the WU-2 gym-cardio FIX for every gym user (even with no exclusions
set). That is the intended fix (gym users were wrongly denied gym cardio), verified at flip time; but it
weakens the old "flip = nothing changes until a user sets exclusions" guarantee for gym tiers.

Adaptation (test-only, no production-logic change): both NO-OP tests now assert the exclusion filter's no-op on
the plan MINUS the two WU-2-owned fields (`warmup` + `finisher`, stripped from BOTH the `workouts` compat list
AND `week_plans[].workout_days[]`) — main selection + cooldown + structure stay byte-identical. This is a
direct consequence of the B-pass's own confirmed finding (WU-2 changes exactly warmup+finisher) and reduces NO
coverage: the warmup/finisher behavior is covered more precisely by `wu2_gym_cardio_gate_behavioral_test`
(gym-cardio offered on the gym tier; excluding cardio machine removes it; flag OFF → none). Self-reviewed;
proportionate (no production logic touched). All 11 tests across the three files green.

## P2 / informational (non-blocking)
- `basic_gym` excludable count was unpinned — CLOSED this commit (added the assertion).
- The C1 Customize UI gains one inert `'Cardio Machine'` excludable chip on gym tiers regardless of flag state
  (`tierItems` isn't flag-gated) — the SAME ship-dark inertness as every other exclusion chip when
  `enable_equipment_exclusions` is OFF; a pre-existing C1 property (acknowledged in the diagnose), not a C2 defect.

**Layers checked:** client code (generateV4 override, the two attach methods, EquipmentVocab tiers), Hive write
shape (warmup/finisher arrays), the scorecard baseline (7/7, no move), tests. B-pass ACCEPTED.
