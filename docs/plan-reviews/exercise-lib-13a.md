---
branch: exercise-lib-13a
plan: .claude/plans/ok-lock-1a-and-atomic-balloon.md
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan Review — Batch 13-A (exercise-library quality: gains-only tier deepening + stub repair + E261 + universalPool)

- **Batch:** 13-A — founder-directed post-overhaul library-quality batch. Client JSON edits + a founder-authorized cloud migration re-apply.
- **Branch:** `exercise-lib-13a` (off `dd51a40a`).
- **Blast radius:** `platform` — `lib/shared/repositories/plan_engine/**` (`blast_radius.yaml:67`) + `supabase/migrations/**` (`:62`, platform — a seed re-apply matches none of the catastrophic migration globs `:46-49`). Full ceremony: behavioral tests + B-pass + this converged record. NOT catastrophic → no Hermes.
- **Ships LIVE** (no kill-switch): the injury filter + equipment filter are always-on; this corrects their input DATA. Byte-identical for non-injured users (injury filter skipped with no injuries); gains-only tier ADDs cannot regress the fallback gate. Client deploy = `_exerciseLibraryVersion` bump; cloud = migration 074 re-apply (founder-authorized 2026-07-19, **explicit confirm at the apply step** per §4.3).

## 0. Scope + founder decisions (locked 2026-07-19)

Founder re-scoped after the Round-1 ×2 review found P0/P1 in the original "full bidirectional sweep":
1. **Tier depth = GAINS-ONLY** — `equipment_tier ← current ∪ derive(equipment_needed)` (ADD tiers only). Removes the
   H2 vertical_pull regression entirely (no drops → pull-ups keep their tags → vertical_pull depth unchanged).
   Over-tag correction (kettlebell rows at home; Standing Calf Raise's phantom barbell) is an **explicit
   founder-approved separate later pass** (a drop-side change needing its own scorecard validation) — NOT a §4.2 deferral.
2. **Cloud re-apply AUTHORIZED** — E261 + healing the coach's stale cloud stub copies both need migration 074
   regenerated + re-applied to prod (a CI count-parity test pins JSON-count == migration-tuple-count).

## 1. GROUND TRUTH (verified against files this session; every subagent numeric claim re-checked)

- **Injury reader** `exercise_repository.dart:335-345` (exact-lowercase eq at :340), always-on, skipped when the
  user injury list is empty (→ byte-identical for non-injured). **Equipment reader** `:298-307` matches the
  exercise's own `equipment_tier` array; an EMPTY equipment_tier passes for EVERY tier (`:301-303`).
- **`EquipmentVocab.tierItems`** (`equipment_vocab.dart:249-261`): bw=[none,bodyweight]; home=+dumbbells,resistance band;
  basic=+barbell,bench,pull-up bar,cables,cardio machine; full=+machines,smith machine,kettlebell,ez-bar. The
  derivation `{T : tierItems[T] ⊇ normalize(equipment_needed)}` is cumulative-up and **never empty** (full_gym ⊇ all canonical tokens).
- **Seed deploy** `seed_service.dart:82` `_exerciseLibraryVersion=7`; re-seed on `stored<version` via idempotent `putAll` (`:111-115,177`). No test pins ==7 (verified).
- **Key distribution (verified via a full tally — corrects the Round-2 reviewer's hallucinated `name_aliases`/~199 counts):**
  the corpus is 258 rows; **38 canonical keys** on all 249 canonical rows; the **9 stubs (E252-E260)** carry 32 keys
  (19 shared + 13 stub-only: `muscle_primary/muscle_secondary/is_compound/sets_default/rest_seconds/difficulty/sub_focus/tags/regression/progression/is_custom/image_url/video_url`) and are MISSING `injury_contraindications` +
  `primary_muscles` etc. → E252 Wall Sit (knee_dominant, no injury field) served to knee-injured users today.
  After normalizing the 9 stubs + authoring E261 to the 38-key schema, all 259 rows are uniform at 38 keys.
- **Gains-only dry-run** (scratchpad, integrity-checked): only `equipment_tier` changes, 0 under-tags remain, 0 empty tiers.
- **1 content hole** (verified): bodyweight `shoulder_isolation` — all 8 rear/side-delt isolations need equipment → E261.
- **universalPoolV4** `exercise_selector.dart:497-509` dups (Inverted Row ×2, Glute Bridge ×2) + wrong-pattern (Dead Bug/Side Plank). Sole other copy = `cascade_tracer.dart:52-64` (verified — `query_v4_mirror.dart` has none).
- **Cloud** `exercise_library` table read by `beat-my-coach/index.ts:193` + `getFormCues.ts:65` (name/coaching_cues/primary_muscles… NOT equipment_tier/injury). Hive exerciseBox is NOT restored from cloud (no restore collision). Prior bug **40a426** (shallow-pool fallbacks) = D-4 recurrence; **e9d1c7** (stub equipment_needed shape) = D-1 kin.

## 2. IMPLEMENTATION SPEC

1. **Gains-only `equipment_tier`** on all changed rows (scratchpad `tier_gains.js --write`, targeted text edits preserving `.0` floats; re-parse asserts only equipment_tier changed).
2. **Normalize 9 stubs E252-E260** → 38-key schema (rename muscle_primary→primary_muscles etc.; add is_active/default_reps/injury_contraindications/… per §3; drop the 13 stub-only keys). E258 calf stays `knee_dominant` (convention — Standing/Seated/Donkey all knee_dominant) → injury `ankle`.
3. **Add E261** Bodyweight Rear-Delt Raise (shoulder_isolation, bw, all-4 tiers, foundational, Beginner, injury `[]`, 38 keys). universalPool shoulder_isolation → E261.
4. **Clean universalPoolV4** + `cascade_tracer.dart` lockstep + a new EQUALITY test (H5).
5. **Bump `_exerciseLibraryVersion` 7→8.**
6. **Regen migration 074** (`scripts/seed_exercise_library.js`, 259 tuples, normalized stub fields) + update `backups/applied_migrations.json` (074 hash + applied_at). **[PAUSE: founder confirm] re-apply to prod** + verify count==259 + spot-check a stub's primary_muscles.
7. Tests (§3) + regen baseline + **per-persona pick-diff review** (P1).

## 3. Tests + validation

- **`equipment_tier_consistency_test.dart`** (P2 — `derive` pinned to real `EquipmentVocab.normalize` + `tierItems`): for all rows `derive(equipment_needed) ⊆ equipment_tier` (no under-tag) + every listed tier canonical + non-empty. Tolerates over-tags by design.
- **`exercise_library_schema_contract_test.dart`**: all 259 rows carry exactly the 38 canonical keys (the tally-verified uniform set). Explicitly lists the coach/plan reader keys the 9 stubs must gain: primary_muscles/secondary_muscles/difficulty_level/default_sets/default_reps/default_rest_secs/logging_type/is_active/injury_contraindications.
- **`exercise_library_injury_completeness_test.dart`**: no row missing `injury_contraindications`.
- **universalPool equality test** (H5): `exercise_selector.universalPoolV4` == `cascade_tracer` copy.
- **Baseline regen (P1 — the load-bearing review step):** re-freezing in-batch defangs the aggregate `meanOverall ≥ baseline−0.05` gate, so the diff is reviewed at the **per-persona pick level** — enumerate every `progression`-family flip (binary 100/0) + every group crossing [MEV=8,MRV=20], separating INTENDED (stub revival + tier gains → fewer fallbacks) from any unintended displacement (a newly-tier-tagged compound sorting above the prior attempt-1 pick). `missing/(none)==0` + `fallback ≤ baseline` are the hard gates.

## 4. REVIEW ROUNDS

### Round 1 — two context-blind reviewers (COMPLETE)
- **Correctness reviewer:** all 8 claims CONFIRMED (readers, tierItems, seed v7, stub schema, "only shoulder_isolation is a bodyweight hole," universalPool dups). One doc-prose overstatement — "whole vertical-pull column `[]`" is wrong (E069/E105/E171/E247 already carry `shoulder`) → **13-B retag must RECONCILE existing tags** (folded into §3 of the plan).
- **Risk reviewer:** H1 (P0) E261 breaks the cloud count-parity test + needs migration 074 re-apply → **RESOLVED (founder authorized)**. H2 (P1) full sweep thins vertical_pull (split_resolver.dart:606-608 = 2 tier-agnostic slots) → **RESOLVED (gains-only, no drops)**. H3 (P1) eq_needed-fix scope + consistency-test-ratifies-mis-tag → **MOOT under gains-only**. H4 (P2) cloud stub NULLs → **RESOLVED (migration regen heals them)**. H5 (P2) cascade_tracer manual copy untested → **fix: lockstep + equality test**. Verified-SAFE: is_custom drop, no stale cache, one equipment_tier reader, no restore collision.

### Round 2 — one reviewer on the hardened (gains-only) plan (COMPLETE)
Verdict: **no P0; design sound; H1-H5 resolutions hold.** Confirmed gains-only cannot regress the HARD gates (adding tiers only adds candidates → fallbacks drop, no new equip-violators); confirmed the consistency `derive` is never empty (structural); confirmed migration 074 regen serializes E261 + heals the stub cloud copies (primary_muscles/difficulty_level in the SET clause) with `instructions` correctly status-quo-NULL; confirmed ledger + count-parity pass at 259; confirmed cascade_tracer is the only pool copy; confirmed NO reader of any dropped stub key; confirmed no version-pin. Three hardening items, all folded in:
- **P1 (baseline re-freeze masking):** the in-batch re-freeze makes the aggregate gate non-protective → §3 now mandates a per-persona pick-diff + progression-flip + MEV/MRV enumeration.
- **P2 (schema test scoping):** its specific counts were HALLUCINATED (verified: no `name_aliases`; the "~199" keys are 249/258) — the real picture is 38 uniform keys after stub normalization, so the schema test is correctly "all rows have the 38 canonical keys" + an explicit stub-required-key list (§3).
- **P2 (consistency `derive`):** pinned to `EquipmentVocab.normalize` + `tierItems` (§3).

### Convergence — CONVERGED
Round-1 ×2 surfaced real P0/P1 → founder re-scope (gains-only + cloud-authorized) resolved them. Round-2 on the hardened plan found **no new material design defect** — only test/review-rigor items, all folded in. Per §4.12 the absence of a new material issue on the hardened plan IS the convergence signal. `verdict: converged` → implement. `bpass` is set to accepted at the self-B-pass step (with the real `docs/reviews/<sha>-review.md`) BEFORE the merge the keystone gate checks.
