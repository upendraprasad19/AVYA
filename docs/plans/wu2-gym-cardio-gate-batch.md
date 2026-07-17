# Focused plan — ⑥ C2: WU-2 gym-cardio gate (fix hasGymEquipment always-false + honor exclusions)

> **STATUS: ×2 review CONVERGED (round-1 + round-2 on the hardened plan).** Round-2 verified all 4 folds correct
> + core design sound + new-defect hunt clean (override × injury-filter orthogonal; B1 × cardio-machine main
> exclusion already tested green). 4 non-blocking polish items folded: (1) **the WARMUP test MUST span ≥3 days**
> — `_gymCardio` moves surface at `cardioLead[dayIndex % pool.length]` index 2, NOT "every day"; build a
> `List.generate(5,…)` week + assert on the SET of cardio names across days (mirror `shared_contracts_test.dart:821`);
> (2) contract-test comment "12 items"→"13 items"; (3) a `// intentionally omits cardio machine (dead mirror)`
> note on `generator_matrix.dart:112`; (4) **COMMIT `fix(plan_engine):` + a DIAGNOSE-DOC** — WU-2 fixes a genuine
> writer/reader-drift bug (`hasGymEquipment` reads the item list expecting the tier string → always-false), so
> the honest framing is `fix` per rule 22, NOT `feat` to dodge the gate. Core design verified sound (always-false
> bug real, `cardio machine` right token+tiers, template_service + `shared_contracts_test:825` stay green via the
> null-default override, flag-OFF byte-identical, generateV4 signal correct). P2s folded: (P2-1) `generator_matrix.
> dart:112 equipmentItemsForTier` is DEAD CODE (0 call sites; scorecard keys off `equipment_tier`) → NO baseline
> move, NO regen, NO matrix edit; (P2-2) update the stale `equipment_vocab.dart:22-27` comment (full_gym no longer
> "the 11 non-cardio-machine tokens"); (P2-3) precise wording — the GENERATED PLAN is byte-identical flag-OFF, the
> Customize UI gains ONE inert "Cardio Machine" chip on gym tiers (consistent with C1's ship-dark Customize UI);
> (P2-4) the FINISHER behavioral test MUST use `goal:'general_fitness'` (→cycling→`_cyclingFinisher(hasGym)`) or a
> `cardioPreference:'running'/'cycling'` — lose_fat→hiit/recompose→jump_rope are bodyweight (no hasGym branch);
> the warmup test via `_gymCardio` is goal-robust. The founder-split
> distinct unit from C1 (2026-07-17). Base off main @ `8f460bc7` (⑥ A+B1+B2+C1 shipped). Worktree
> `workout-wu2-cardio-gate`. NO migration (local-only) → runs straight through. Blast radius: **PLATFORM**
> (`plan_engine/**`).

## Problem (self-verified)
`WarmupCooldownSelector.attach` (`warmup_cooldown.dart:141`) + `CardioFinisher.attach` (`cardio_finisher.dart:28`)
compute `hasGymEquipment = equipmentList.any((e) => e.toLowerCase().contains('gym') || contains('full'))`. On a
GENERATED plan, `equipmentList = _getEquipmentList(tier)` = item tokens (`none`/`bodyweight`/`dumbbells`/…) which
contain neither 'gym' nor 'full' → **hasGymEquipment is ALWAYS FALSE** → gym users NEVER get gym-cardio warmup
(`_gymCardio` `:93`: Jump Rope / Cycling / Treadmill) or finisher variants (`_runningFinisher`/`_cyclingFinisher`
`:116/:131`: Treadmill Intervals / Bike Sprints). **Path-scoped:** `template_service` passes the tier STRING
`['full_gym']` to attach → the old predicate is correctly TRUE there (`'full_gym'.contains('gym')`), so the
template path works today + must NOT regress. Founder decision: fix-and-honor (gym users get gym cardio AND an
exclusion of the gym-cardio equipment removes it).

## Ground-truth (self-verified vs 8f460bc7)
- **Gym-cardio token = `cardio machine`** (reviewer A, re-verified): the pools normalize to it — `treadmill →
  cardio machine`, `stationary bike → cardio machine` (`equipment_vocab.dart:94-95`); `jump rope → bodyweight`
  (`:135`, doesn't justify a gym gate). **`cardio machine` is in NO tier** (`EquipmentVocab.tierItems`, C1 —
  bodyweight/home_dumbbells/basic_gym/full_gym), so gating on it is always-false EVEN flag-ON unless it's ADDED
  to the gym tiers. The old predicate's intent qualified BOTH basic_gym + full_gym (both tier strings contain
  'gym') → add `cardio machine` to BOTH.
- **attach call sites (generateV4):** `CardioFinisher.attach` (`plan_generator.dart:196`, passes `equipmentList`),
  `WarmupCooldownSelector.attach` (`:205`, passes `equipmentList`). `equipmentList` = `_getEquipmentList(tier)` =
  `EquipmentVocab.tierItems[tier]` (C1 delegation).
- **The 3rd attach caller — `template_service`** (passes the tier string, old predicate TRUE) MUST NOT regress.
- **Tier-string tests** `shared_contracts_test.dart:825-835` assert `attach(…, ['full_gym'])` yields MORE
  gym-cardio than `['bodyweight']` — they rely on the tier-string path → an in-`attach` predicate change breaks
  them. So DON'T change the in-`attach` predicate.
- **Batch-0 matrix does NOT measure warmup/cardio** (the CLAUDE.md: "scorecard doesn't measure the finisher" +
  "warmup isn't in plan.allExercises") → the WU-2 change does NOT move the baseline. `generator_matrix` mirror
  references `_getEquipmentList`/`tierItems` — adding `cardio machine` to the tiers must be reflected there IF it
  hardcodes a copy (verify; it likely uses tierItems now, auto-updated); no SCORE change either way (main plan
  uses `equipment_tier`, not the item list).
- **C1 contract test** `equipment_chip_vocab_contract_test.dart` asserts `tierExcludableItems('full_gym').length
  == 10` — adding `cardio machine` to full_gym makes it 11 (+1 excludable chip on gym tiers). MUST update.

## Design (reviewer A's clean approach — generateV4 computes the signal, attach default = old predicate)
1. **`EquipmentVocab.tierItems`:** add `'cardio machine'` to `basic_gym` + `full_gym` (NOT bodyweight/home_dumbbells).
   `_getEquipmentList` auto-picks it up (C1 delegation). Consequence: `cardio machine` becomes an excludable chip
   on the gym tiers (correct + consistent — a user without a treadmill excludes it). **P2-2: also update the stale
   `equipment_vocab.dart:22-27` `canonicalTokens` doc** (full_gym is no longer "the 11 non-`cardio machine` tokens"
   — it now includes it) in the same commit. `_chipLabels` already has `'cardio machine'` (`:284`) — no chip-label
   change. The dead `generator_matrix.dart:112 equipmentItemsForTier` (0 call sites) need NOT be touched (P2-1).
2. **`WarmupCooldownSelector.attach` + `CardioFinisher.attach`:** add an optional `bool? hasGymEquipmentOverride`
   (default `null`). When null → the EXISTING `contains('gym')||contains('full')` predicate (byte-identical;
   template_service + the tier-string tests untouched). When non-null → use the override.
3. **`generateV4`:** compute a flag-gated override + the effective equipment:
   ```dart
   final effectiveEquipmentList = equipmentExclusionSet.isEmpty
       ? equipmentList
       : equipmentList.where((e) => !equipmentExclusionSet.contains(e)).toList();
   final bool? hasGymOverride = PlanEngineFlags.equipmentExclusionsEnabled
       ? effectiveEquipmentList.contains('cardio machine')
       : null;   // flag OFF → null → attach uses the old predicate → byte-identical
   ```
   Pass `hasGymEquipmentOverride: hasGymOverride` to BOTH attach calls (`:196`/`:205`). `equipmentExclusionSet` is
   already computed at `:100-102` (C1). Flag OFF → `hasGymOverride == null` → old predicate (always-false on the
   generated path — today's behavior). Flag ON → gym users get gym cardio (override true for gym tiers) AND an
   exclusion of `cardio machine` removes it (effective list drops it → override false → bodyweight cardio).
4. **Gate:** the WHOLE WU-2 change activates with `enable_equipment_exclusions` (same flag as C1 — ships DARK
   together; flipped post-APK). Flag OFF → byte-identical to today (gym cardio never on the generated path;
   template path unchanged).

## Tests
- Behavioral `test/contracts/wu2_gym_cardio_gate_behavioral_test.dart` (generateV4 Hive-boot + userBox harness,
  C1's activation test). TWO assertion families:
  - **WARMUP (goal-robust — `_gymCardio` attaches to all days):** flag ON + full_gym → a warmup day includes a
    `_gymCardio` move (Jump Rope / Cycling (Stationary) / Running (Treadmill)); flag ON + full_gym + exclude
    `cardio machine` → NO `_gymCardio` (bodyweight warmup only); flag OFF → NO `_gymCardio` (always-false old
    predicate — byte-identical).
  - **FINISHER (P2-4 — MUST use `goal:'general_fitness'` so `_defaultForGoal→'cycling'→_cyclingFinisher(hasGym)`;
    lose_fat/recompose default to bodyweight hiit/jump_rope and would NOT exercise the hasGym branch):** flag ON +
    full_gym + general_fitness → finisher = "Stationary Bike Sprints" (gym); + exclude `cardio machine` → "High
    Knees Intervals" (bodyweight); flag OFF → "High Knees Intervals" (old predicate always-false). (`cardioGoal
    DefaultEnabled` is default-ON so general_fitness→cycling holds; alternatively pass `cardioPreference:'cycling'`.)
  - Rule 21: reverting the generateV4 override compute → flag ON falls back to the always-false old predicate →
    the "gym variant offered" assertions go red.
- **Update** `equipment_chip_vocab_contract_test.dart`: full_gym excludable 10→11; basic_gym gains `cardio machine`.
- Confirm `shared_contracts_test.dart:825-835` STAYS green (the attach default = old predicate; unchanged).
- Confirm the Batch-0 scorecard gate stays green (WU-2 doesn't touch measured main-plan selection) + regen the
  matrix baseline ONLY if `generator_matrix` scores off the tier item list (verify — expected NO change).

## SoT
Extend `equipment_exclusion_filter` (or a new `wu2_gym_cardio_gate` note): the WU-2 writers
(`warmup_cooldown.dart` + `cardio_finisher.dart` `hasGymEquipmentOverride`) + the generateV4 signal compute +
the `EquipmentVocab.tierItems` `cardio machine` gym-tier addition. Behavioral_test_path.

## Review focus (×2 context-blind)
1. `cardio machine` added to the RIGHT tiers (basic_gym + full_gym, matching the old predicate's both-gym intent);
   the excludable-chip + contract-count updates are complete; the matrix mirror is consistent (no baseline move).
2. attach's `null`-default override keeps template_service + `shared_contracts_test:825` byte-identical (flag OFF
   AND the tier-string path).
3. The generateV4 signal is correct: gym tier → gym cardio (flag ON); exclude cardio machine → bodyweight; the
   effective-list subtraction reaches BOTH attach calls.
4. No main-plan / B1-exclusion / C1 regression; the whole change is inert flag-OFF.
