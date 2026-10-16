# Focused plan — ⑥ slice B1: queryV4 equipment item-level exclusion filter

> **STATUS (2026-07-16): ×2 review COMPLETE → CONVERGED. Ready to implement.** Round-1 = a multi-lens
> context-blind workflow (4 lenses × adversarial verify — 22/23 findings survived) that rejected the original
> "effective-availability intersection" design (regressed 41 exercises) → PURE EXCLUSION, then hardened it
> (exclusion at ALL pick paths; crash-safe normalizing read; flag-ON tests). Round-2 (context-blind, on the
> hardened plan) = **no P0/P1**, verdict CONVERGED, "do NOT run a 5th review or split"; its 5 P2 clarifications
> (test-harness naming, scorecard threading, drop the redundant apply-bool, cardio/warmup scope→WU-2/C,
> leaf-required wording) are ALL folded below. Base off main @ `1e34e5f5` (incl. slice A, CI-green). Record:
> `docs/plan-reviews/workout-equipment-filter.md`.

**Tier: PLATFORM** (`exercise_selector.dart` / `plan_generator.dart` / `plan_engine_flags.dart` →
`lib/shared/repositories/plan_engine/**`). `requires: [regression_test, behavioral_test_path,
code_review_b_pass, feature_flag]` + §4.12 record with `bpass: accepted`. **Rule #14** (never modify
plan_generator.dart without explicit instruction) is satisfied by the founder-approved 13-batch overhaul,
under which prior batches ④ (cardio_finisher) + ⑤ (physique-focus, plan_generator.dart:148-155) already
edited the engine — B1's generateV4 exclusions-threading is the same standing authorization (R1 P2-3).

## Scope — B1 (read-side filter). B2 (community write-seam normalize) + C (profile field + Customize UI + WU-2) separate.
Add an item-level equipment EXCLUSION filter across the **MAIN exercise selection — ALL FOUR pick paths**
(queryV4 attempts 1-4 + the attempt-5 universal pool + the phase≥2 L2 custom-append + L6 demote-swap) so a
user can subtract canonical items from their tier. Ships DARK behind `enable_equipment_exclusions` (default
OFF). **B1 is self-contained re: community rows** — the predicate reads via `EquipmentVocab.fromProfile`
(normalizes on read), so B1 is correct even before B2 write-normalizes the seam (R1 P1-1 dissolved).
**Scope boundary (P2-D — conscious, NOT "whole V4"):** the post-selection Stage-7 `CardioFinisher.attach`
(`plan_generator.dart:177-184`, picks from `_getEquipmentList` tier expansion) + Stage-8 `WarmupCooldownSelector`
(`:187`, hardcoded dayType lists) do NOT go through queryV4/pickV4, so B1 does NOT exclusion-filter them — a
user excluding `cardio machine`/`machines` could still be offered a treadmill finisher / machine warmup. That
is **slice C's WU-2** (the original ⑥ plan already scopes "feed the same effective equipment set to
CardioFinisher + WarmupCooldownSelector" to WU-2 — its consumer), NOT a §4.2 deferral. Testable via DIRECT
`generateV4(equipmentExclusions:[...])` with the flag flipped ON in a Hive configBox.

## Ground-truth (SELF-VERIFIED; ⚑ re-open line numbers at edit-time — main may advance)
- **Live V4 filter reads `equipment_tier`, NOT `equipment_needed`** — `queryV4` (`exercise_repository.dart:270`)
  filters `equipment_tier`; the `equipment_needed` filter at `:127-140` is the DEAD V3 `query()` (0 callers).
  The exclusion filter is NET-NEW (do NOT port the V3 `.every(...|| none || bodyweight)` SUBSET predicate — that
  is the REJECTED intersection design; use the pure-exclusion `.any` drop below).
- **queryV4 no-tier `:272 return true`** short-circuits later filters → place the exclusion drop BEFORE :268.
  All 258 asset rows are tiered, so the short-circuit is only reachable via un-tiered COMMUNITY rows (which the
  before-:268 placement + fromProfile read handle).
- **5 queryV4 call sites** (`exercise_selector.dart` :792/808/820/830 cascade att1-4 + :633 `_applyHistoryAdjustments`
  L6), threaded from generateV4(:65)→pickV4(:514)→_fillSlots(:753)→_cascadeFill(:784)→queryV4; and pickV4→
  _applyHistoryAdjustments(:611)→queryV4(:633). att4 (:830) passes NO equipmentTier (tier dropped).
- **TWO queryV4-BYPASSING pick paths** (R1 P1/P2 — the exclusion filter must reach these too):
  (a) **attempt-5 universal pool** (`exercise_selector.dart:847-873`): fills from `universalPoolV4` via
  `repo.search` (name substring, no equipment filter). U2 injury already skips it via `_isContraindicated`
  (:862-865) — the exact precedent to mirror. Pool lists Pull Up / Chin Up (`['pull-up bar']`) FIRST for
  vertical_pull / elbow_flexion, before the bodyweight fallback (Inverted Row) → a pull-up-bar-excluding user
  is handed Pull Up unless att5 is filtered.
  (b) **L2 custom-append** (`_applyHistoryAdjustments:653-671`, phase≥2 + has-customs): appends the user's
  custom exercises via `_buildCustomExercise` (equipment_needed carried raw), no queryV4.
- **`EquipmentVocab.fromProfile`** (`equipment_vocab.dart:201-205`): crash-safe (List / bare-String / null →
  never throws — the e9d1c7 class) AND returns the NORMALIZED canonical list. THIS is the read for every
  exclusion check (not `as List`).
- **Ship-dark flag pattern** (`plan_engine_flags.dart`): `enable_*` reads `HiveService…get(key) == true` with
  `catch(_) => false` ⇒ DEFAULT OFF, and OFF without an open Hive box (pure unit test) — so behavioral ON-path
  tests MUST open configBox + set the flag true (sibling precedent: physique_focus_bringup_test:148,
  progression_resolver_graded_test:98, session_detraining_cut_test:133).
- **Parallel re-implementations** `test/plan_generator/v4_diagnostic/query_v4_mirror.dart` (mirrors queryV4
  filters 1-8) + `cascade_tracer.dart` (mirrors _cascadeFill incl. the att5 pool + `_isContraindicated`) —
  neither reads PlanEngineFlags. The scorecard gate + frozen baseline run on the MIRROR over the canonical
  asset (`generator_matrix.dart:245`), so they structurally never see community/non-canonical/att5-under-
  exclusion rows → the direct-call behavioral tests are the real proof.

## Design (R1-HARDENED — PURE EXCLUSION applied at EVERY pick path)
1. **Exclusions set — computed ONCE at `generateV4`, mirroring the injury seam (`plan_generator.dart:90`).**
   The injury filter is the EXACT precedent: `:90` `final normalizedInjuries = InjuryVocab.normalize(injuries)`
   → `:119-120` `pickV4(injuries: normalizedInjuries, applyInjuryUniversalFilter: PlanEngineFlags.injuryUniversalFilterEnabled)`.
   Mirror it: new `generateV4` param `List<String> equipmentExclusions = const []`; centrally
   `final exclusions = PlanEngineFlags.equipmentExclusionsEnabled ? (EquipmentVocab.normalize(equipmentExclusions).toSet()..removeAll({'none','bodyweight'})) : const <String>{};`
   (flag-gated + normalized + floor-sanitized in ONE place — so OFF or empty ⇒ `{}` ⇒ every downstream guard
   inert). Thread the **`Set<String> exclusions` — ONE signal, NO apply-bool** (P2-C: unlike injuries'
   `applyInjuryUniversalFilter`, a genuine orthogonal att5 kill-switch at `exercise_selector.dart:523`, an
   equipment bool would be `== exclusions.isNotEmpty` and never diverge → carries no info; the EMPTY SET is the
   single no-op signal) through pickV4 → _fillSlots → _cascadeFill → queryV4 (att1-4) AND
   _applyHistoryAdjustments → queryV4 (L6) + the att5 skip + the L2 custom filter. **Threading asymmetry (P2-E,
   deliberate — not a contradiction):** the queryV4 LEAF `exclusions` param is **REQUIRED** (compile-time thread
   enforcement — a missed call site fails to compile, closing the silent-skip gap R1 P2-optional); the
   INTERMEDIATE params (pickV4/_fillSlots/_cascadeFill/_applyHistoryAdjustments) **default `const <String>{}`**
   so unset/mirror callers stay byte-identical (R1-R1-06). Empty set → every `.isNotEmpty`-guarded drop inert →
   byte-identical no-op.
2. **queryV4 drop (BEFORE the :268 tier block; crash-safe + normalizing read):**
   `if (exclusions.isNotEmpty) { final need = EquipmentVocab.fromProfile(e['equipment_needed']); if (need.any(exclusions.contains)) return false; }`
   — `fromProfile` is shape-tolerant (no `as List` crash — R1 P1) AND normalizes to canonical lowercase
   (community/mixed-case rows are correctly excluded — R1 P1-1/P2-4, and B1 no longer depends on B2). The
   `equipment_tier` filter (:268-277) stays UNTOUCHED → the 41-exercise intersection regression is gone. Empty
   exclusions → the `.isNotEmpty` guard skips everything → EXACT no-op.
3. **Attempt 4 (`:830`, tier dropped) KEEPS the exclusion drop.** Equipment exclusion is a HARD physical
   constraint (the user lacks the gear); only the SOFT tier heuristic is relaxed at att4. (R1 P1-attempt4 — do
   NOT drop exclusions at att4; att5's floor pool is the safe catch.)
4. **Attempt 5 (universal pool) exclusion skip** — mirror U2: in the `:847-873` loop, `continue` past a pool
   move whose `EquipmentVocab.fromProfile(resolved['equipment_needed'])` intersects `exclusions` (gate it on
   the same flag / non-empty set). Floor-sanitize guarantees ≥1 bodyweight move per movement_pattern in the
   pool, so a skip never empties the slot — it just prefers the bodyweight fallback (Inverted Row over Pull
   Up). (R1 P1-attempt5.)
5. **L2 custom-append exclusion filter** (`:653-671`): skip appending a custom exercise whose
   `fromProfile(equipment_needed)` intersects `exclusions` — a user who says "no barbell" shouldn't get their
   barbell custom auto-appended. (DECISION: filter, not exempt — consistency with "I don't have this now";
   R1 P2-L2 wanted an explicit decision — this is it.)
6. **Kill-switch** `enable_equipment_exclusions` in `plan_engine_flags.dart` (default OFF, `== true`). OFF →
   generateV4 threads `const {}` → every guard above is inert → byte-identical to today (also byte-identical
   when ON but nothing excluded — the `.isNotEmpty` guards, not just the flag).

## Mirror + sweep + baseline (⚠ or the gate passes while prod diverges)
- Add the SAME exclusion drop to `query_v4_mirror.dart` (before its tier short-circuit) + the att5 skip to
  `cascade_tracer.dart` (matching design 4). The mirror reads NO flags → it applies the drop whenever its
  `exclusions` set is non-empty; prod gates on the flag → so the exclusion PERSONAS in the matrix carry
  non-empty exclusions (mirror applies) and the baseline is frozen with the understanding that prod-with-flag-
  ON == mirror (R1-R1-06). Non-exclusion personas carry `{}` → no-op in both → their baseline rows stay
  BYTE-IDENTICAL (append only the new exclusion-persona rows — R1-B1-06).
- **Scorecard threading (P2-B — more than "the earmark"):** add an `equipmentExclusions` field to `Persona`
  (`generator_matrix.dart:29`); `generatePlan` threads it into `CascadeTracer.trace` (`:163`); `trace` gains a
  new `exclusions` param **default `{}`** passed to its 4 `QueryV4Mirror.query` calls (att1-4 `:96/131/157/180`)
  + the att5 skip loop (`:208-244`). The `{}` default is exactly what keeps non-exclusion baseline rows
  byte-identical.
- **Add exclusion personas to `generator_matrix.dart:194-196`** (the earmarked plug-in). ⚠ HARD gates
  (R1-B1-05) — SELF-VERIFIED SATISFIABLE: (a) `missing==0` (scorecard_gate_test.dart:70-73) holds for ANY
  exclusion persona because the att5 bodyweight floor fills every slot (verified all 11 patterns); (b)
  `fullGymEquipViolations==0` (:75-78) only counts personas whose `equipment=='full_gym'` (:44-46) — so place
  exclusion personas at **basic_gym / home_dumbbells** (e.g. "basic_gym minus cables") and they never touch
  that gate; (c) `totalFallback ≤ baseline` (:81+) holds because the re-freeze puts the exclusion personas'
  (higher, expected) fallbacks on BOTH sides. AGGRESSIVE exclude-everything is proven in the DIRECT behavioral
  tests (raised fallback expected), NOT the matrix.
- Regenerate the frozen baseline (`generate_baseline.dart`); confirm non-exclusion rows unchanged.

## Behavioral tests (flag flipped ON via `configBox.put('enable_equipment_exclusions', true)` — else vacuous, R1 P1-test)
**Harness (P2-A — NO generateV4 Hive-boot harness exists today, per `physique_focus_bringup_test.dart:48`): two layers.**
(a) **Unit-pin the central seam** — extract the compute-exclusions logic (flag-gate + `EquipmentVocab.normalize`
+ floor-sanitize `..removeAll({'none','bodyweight'})`) into a testable static helper (mirror the
`resolveBodyFocus` precedent) and unit-test it directly — cheap, proves the flag-read + normalize + floor.
(b) **Build the generateV4 Hive-boot harness** for tests 1-6 — seed the full library (`LibraryLoader.loadFromAssets()`
→ `exerciseBox.putAll`), `HiveService.markInitializedForTests()`, `configBox.put(flag,true)`, call `generateV4`;
compare plans via `Phase.toMap()` (deterministic, zero timestamps — round-2-verified). Proven feasible by
`injury_safe_omission_production_test` (real pickV4 + seeded exerciseBox) + `v4_diagnostic_test.dart:15`
(LibraryLoader in flutter_test). Do NOT fall back to pickV4/queryV4-level tests that BYPASS the generateV4
flag-read+normalize+floor seam (rule 21 / source-grep-false-confidence).
1. **No-op proof:** flag ON + EMPTY exclusions → plan BYTE-IDENTICAL to flag OFF (closes the 41-regression).
2. **Exclude 'cables' @ full_gym** (flag ON) → NO selected exercise's `fromProfile(equipment_needed)` contains
   'cables'; use a persona/slot where attempts 2-4 (not just att1) win, exercising the fallback drop.
3. **Attempt-5 floor:** exclude everything → a valid bodyweight plan IS produced AND no selected exercise
   requires an excluded item (the att5 skip holds — asserts vertical_pull yields Inverted Row not Pull Up).
4. **Phase≥2 L6:** a demoted-exercise persona → the L6 queryV4 swap honors exclusions.
5. **Phase≥2 L2:** a has-customs persona with a barbell custom + exclude 'barbell' → the custom is NOT appended.
6. **Community/bare-String row:** a synthetic un-normalized `['Cable Machine']` (+ a bare-String) exerciseBox
   row → excluded when the user excludes 'cables' (fromProfile normalizes) AND no crash (shape-tolerant).

## SoT
`equipment_exclusion_filter` concept — writer = generateV4 exclusions-set + queryV4/att5/L2 drops; reader =
plan output. **`behavioral_test_path: test/contracts/equipment_exclusion_filter_behavioral_test.dart`** (named
per rule 21 / Gate 42, R1 P2-5).

## Review focus (round-2 — verify the HARDENED plan)
1. The drop reaches ALL FOUR pick paths (queryV4 att1-4, att5 pool, L2 custom, L6 swap); att4 KEEPS exclusions.
2. `EquipmentVocab.fromProfile` used at every read (crash-safe + normalize) — no `as List`; no case-sensitivity.
3. No-op proof: flag OFF / ON+empty → byte-identical (const {} defaults; required queryV4 param; .isNotEmpty guards).
4. Floor: none/bodyweight stripped from exclusions → bodyweight exercises never dropped; att5 skip never empties a slot.
5. Mirror + cascade_tracer match prod (incl. att5 skip); baseline: non-exclusion rows byte-identical, mild personas keep missing==0; aggressive exclusions in direct tests only.
6. Behavioral tests flip the flag ON; cover att2-4, att5, L6, L2, community/bare-String.
7. Tier=platform; rule-#14 authorized; B2 (community write-seam) + C (profile-read + UI + WU-2) deferred to their consumers (B1 self-contained via read-normalize).

## Load-bearing (re-verify at edit-time)
Intersection would regress 41 (4/25/12) vs pure-exclusion 0 at empty ✓VERIFIED. cardio machine=6 / smith machine=0 / 258 tiered ✓. **att5 skip is SAFE ✓VERIFIED — all 11 movement patterns' `universalPoolV4` have ≥1 pure-bodyweight exact-name move that survives exclude-everything (vertical_pull + elbow_flexion rely on Inverted Row['bodyweight'], present); so the skip never empties a slot, just prefers the bodyweight fallback.** Line numbers may drift — re-open. Mirror parity + the att5/L2 bypass paths are the silent-failure risks.
