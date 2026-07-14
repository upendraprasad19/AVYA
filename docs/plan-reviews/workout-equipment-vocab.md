---
branch: workout-equipment-vocab
scope: ⑥ slice A — equipment_needed vocabulary normalization (EquipmentVocab + gate + owned-write normalize)
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-equipment-vocab-bpass.md
---

# Plan-review record — ⑥ slice A (equipment_needed vocabulary normalization)

Plan: [`docs/plans/equipment-vocab-batch.md`](../plans/equipment-vocab-batch.md). §4.12 ×2 context-blind
review of the pre-implementation plan; review #2 on the hardened plan. Every load-bearing claim
independently verified against `assets/data/exercise_library.json` + the reader/writer code (never subagent
prose). **Converged — ready to implement.**

## Ground-truth verified (self + both reviewers, against actual files)
- **Live V4 selection filters on `equipment_tier`, NOT `equipment_needed`** — `plan_generator.dart:112`
  (sole `pickV4` caller) → `queryV4` reads `e['equipment_tier']` at `exercise_repository.dart:270`. The
  `equipment_needed` read (`exercise_repository.dart:129`) is inside V3 `query()`, reached only via
  `ExerciseSelector.pick` = **ZERO live callers** (dead; revived by slice B). ⇒ normalization is
  prerequisite-only, no live plan-generation change.
- **258 rows, 87 distinct tokens (61 non-OR + 26 OR-compound), 0 bare Strings** (node enum). Row partition
  170 plain-single + 52 plain-multi + 36 OR (33 single-OR + 3 OR-mixed-AND) = 258; single=203, multi=55.
- **`equipment_tier` clean on all 258 rows**; seed `_exerciseLibraryVersion=6` (`seed_service.dart:81`),
  reseed on `storedExVersion < const`, `putAll` by id (:176) → bump 6→7 re-seeds existing installs.
- **No live UI reader of the seed `equipment_needed`** (R2 P1-1): the swap sheet receives an `equipment`
  param but never renders it; `ai_snapshot_builder.dart:518` reads `customBox` (custom exercises), not the
  seed. The one live delta is the OWNED custom-write (`workout_repository.dart:1375`) → coach snapshot
  (canonical token to Gemini — benign). Slice A is safer than a display-changing batch.

## Round 1 (2 context-blind reviewers on the initial plan)
- **Architecture lens:** confirmed the dead-V3 / `equipment_tier`-live claim + seed mechanics + the
  InjuryVocab template. **P0: mis-tiered.** As drafted it was PLATFORM (via `sync_community.dart` under
  `sync/**` + the `plan_generator.dart` `_getEquipmentList` move under `plan_engine/**`) and tripped
  coding-rule #14. "No live behavior change" overstated.
- **Vocab-design lens:** re-enumerated all 87 tokens; confirmed counts. **P0/P1:** the niche rule was
  non-deterministic; Box/Medicine Ball/Weight Plate/Sandbag mis-bucketed into gym canonicals; the 7-item
  OR-precedence couldn't resolve 6 of 26 compounds; and a naïve `normalize()` mirroring `InjuryVocab`'s
  `\s+` split would flip OR→AND and explode "cable machine"→cable+machine. Provided a full mapping table +
  a 12-item total precedence + the Rope×3→cables verification (all co-occur with Cable Machine).

## Hardening (between rounds)
Re-tiered to **ACCOUNT** by shipping the smallest converged piece (§4.12): dropped the `sync_community.dart`
seam (→ slice B, its only reader is slice B's filter) and the `plan_generator.dart` `_getEquipmentList` move
(→ slice C, rule #14) — legitimate scoping to their consumers, not deferrals (no reader exists now). Adopted
the exhaustive 87-token `_aliases` + the 12-item total precedence; fixed the 4 mis-bucketings; corrected
E044 `["Dumbbell","Box or Bench"]`→`[dumbbells,bodyweight]` (Box→bodyweight outranks bench). Redesigned
`normalize()` (whole-token alias, explicit `" or "` split → min-by-precedence, NO `\s+` split, drop→`[]`).

## Round 2 (1 comprehensive reviewer on the HARDENED plan)
Independently transcribed the plan's `_aliases` + `normalizeToken` into code and ran all 87 tokens:
**0 unmapped, 0 non-canonical; all 26 OR-collapses correct; E044 correction confirmed right; the 3
OR-mixed-AND rows keep their AND sibling.** Verified drop→`[]` safe for every reader, the SUBSET gate
fails-without-fix, the owned-seam behavioral test genuinely exercises `workout_repository.dart:1375`, and
ACCOUNT tier holds (no `sync/**`/`plan_engine/**` staged; the two dropped items have no live reader now =
legitimate scoping, not a §4.2 deferral). **No P0.** Corrections applied to the plan text: the phantom
"swap-display" live consumer removed (P1-1 → drop `label()`, fix SoT readers); community-download seam
re-cited to `sync_community.dart:504` (P2-1); slice-B tier wording softened (P2-2); `:176` putAll nit (P2-3).

## Verdict: converged
The verified technical design — 12-token vocabulary, 87-token `_aliases`, 12-item total precedence,
`normalize` (no `\s+` split), SUBSET gate, owned-write normalize, seed v7, ACCOUNT tier — is correct and
implementable as specified. Remaining were mechanical plan-text accuracy fixes (applied). B-pass runs on the
implemented diff before the `--no-ff` merge (§4.3).
