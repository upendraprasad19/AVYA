---
branch: workout-equipment-community-seam
scope: ⑥ slice B2 — community-download equipment_needed write-normalize (consistency, ship-live default-ON, kill-switch)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-equipment-community-seam-bpass.md
---

# Plan-review record — ⑥ slice B2 (community-download equipment_needed write-normalize)

Plan: [`docs/plans/equipment-community-seam-batch.md`](../plans/equipment-community-seam-batch.md).
§4.12 ×2 context-blind review of the pre-implementation plan; review #2 on the hardened plan. Every
load-bearing claim verified against `exercise_selector.dart` / `exercise_repository.dart` /
`plan_generator.dart` / `sync_community.dart` / `equipment_vocab.dart` (never subagent prose).
**Converged — implemented.** PLATFORM tier (`lib/core/services/sync/**`); `bpass: accepted` added after the
pre-merge B-pass on the implemented diff.

## Ground-truth verified (self + reviewers, against actual code)
- **B2 is CONSISTENCY-ONLY, not load-bearing correctness.** The V3 `ExerciseRepository.query()` equipment
  filter (`exercise_repository.dart:129-140`, reads RAW `equipment_needed`) has 3 callers
  (`exercise_selector.dart:265/:345/:442`) ALL inside `ExerciseSelector.pick()` (`:61`) — and `pick()` has 0
  callers (SELF-grep `.pick(` in lib/ = empty; the live path is `plan_generator.dart:124 → pickV4 →
  _fillSlots/_applyHistoryAdjustments → _cascadeFill → queryV4`). So `query()` is transitively DEAD. The ONE
  live selection reader (queryV4) already `fromProfile`-normalizes on read (⑥ B1). One round-1 reviewer's
  "query() is a live reader → load-bearing correctness bug" was REFUTED here and re-confirmed refuted in round-2.
- **Community rows never reach SELECTION.** They lack `movement_pattern`, so queryV4's movement-pattern filter
  excludes them entirely; they reach the user only via shape-tolerant swap/display paths — so B2 guards only
  the STORED representation (matching the seed), not plan generation.
- **The seam** is `sync_community.dart:499-518` `syncCommunityItems` — approved `user_custom_exercises` rows
  → `exerciseBox.put`. B2 normalizes `equipment_needed` INSIDE the `get(id)==null` id-guard, AFTER
  `map['source']='community'`, BEFORE the put (only NEW downloads; existing local rows untouched).
- **`EquipmentVocab.normalizedEquipmentRow(map, {enabled})`** (public static, `equipment_vocab.dart`) delegates
  to `fromProfile` — crash-safe on List / bare-String / null / absent (the e9d1c7 class), idempotent
  (canonical in → canonical out), mutates+returns the fresh per-row `Map.from(row)`. Public so the rule-21
  behavioral test is genuinely reachable (a private `part of` helper would force source-grep-only).
- **Kill-switch** `disable_community_equipment_normalize`, read at the call site as `_hive.configBox.get(...)
  != true` — the house sync `disable_*` idiom (`sync_service.dart:217/240/274`, `sync_nutrition.dart:211`).
  Default (unset) → normalize ON. Ships LIVE (§4.6 verify owed on the test account).
- **Heals forward on reinstall** — a fresh install has an empty `syncBox` → `since='2020-01-01'`
  (`sync_community.dart:456-460`) → all approved community exercises re-download → fresh box means
  `get(id)==null` true → re-stored canonical. Legacy raw rows on non-reinstalled devices stay raw but are
  covered by B1's read-normalize (SoT `equipment_exclusion_filter` note). B2 adds NO new box/field/sync/restore
  surface → no restore-completeness entry needed.
- **No live reader breaks** — all `equipment_needed` community readers are verbatim swap/template copies,
  shape-tolerant `parseEquipmentNeeded`, `fromProfile`, and the AI snapshot (SoT already flags canonical as
  benign). No exact-string compare on the raw capitalized value except the DEAD `query():133-138`.

## Round 1 (×2 context-blind, on the initial plan)
Both reviewers verified the change CORRECT, crash-safe, idempotent, safe against every live reader —
needs-revision only on wording / flag-commitment / test-seam precision, NO redesign. One reviewer's
"query() live → load-bearing correctness bug" was refuted by a first-hand `.pick(`-grep (0 callers) + the
other reviewer's independent seam trace. All folded: precise query()/pick() dead-chain wording; kill-switch
COMMITTED (default-ON, deleting the "decide in review" hedge); path label fixed to
`lib/core/services/sync/sync_community.dart`; a testable extracted seam; placement precision.

## Round 2 (context-blind, on the HARDENED plan)
**Verdict `converged`.** The dead-chain claim verified TRUE against code; crash-safe; idempotent; no live
reader breaks; heals forward. 3 P2 implementation-refinements, ALL folded, NO redesign:
- **P2-1** the transform must be genuinely test-reachable (`@visibleForTesting`/public), not a private
  `part of` helper → homed as PUBLIC `EquipmentVocab.normalizedEquipmentRow` (mirrors public
  `floorSanitizedExclusions`).
- **P2-2** default-ON deviates from B1's ship-dark default-OFF, but is justified (B2 changes only the stored
  representation; every live reader tolerates canonical; default-OFF would be a permanent no-op) — keep §4.6
  verify since it ships live.
- **P2-3** `normalize` DROPS unmappable tokens (stores `[]`) — lossy on that one field, consistent with the
  seed + B1 read-drop — documented in the SoT writer note.
Corroborating: community rows lack `movement_pattern` → never selected; cloud `equipment_needed` is `text[]`
so the bare-String branch is defensive-only; community rows are never re-uploaded → zero cloud impact.

## Verdict: converged
The write-seam normalize (public crash-safe idempotent transform, flag-gated `!= true` default-ON at the
call site, inside the id-guard, exercises-only, heals-forward) is correct and implemented as specified.
Behavioral test `test/contracts/community_equipment_normalize_behavioral_test.dart` (both flag branches ×
every shape) + SoT `equipment_vocab` writer extension. B-pass runs on the implemented diff before the
`--no-ff` merge (§4.3 / platform `requires: bpass`).
