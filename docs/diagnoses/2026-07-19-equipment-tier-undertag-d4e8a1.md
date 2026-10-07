---
bug_id: d4e8a1
date: 2026-07-19
batch: exercise-lib-13a
blast_radius: platform
status: fixed
symptom: >
  Exercises doable with little/no equipment were HIDDEN from the tiers they belong
  to because their `equipment_tier` array skipped the middle tiers: Glute Bridge
  tagged ["bodyweight","full_gym"] (invisible to every home_dumbbells + basic_gym
  user though it needs zero equipment); Reverse Fly / Shrug / Romanian Deadlift
  tagged full_gym-only though they need only dumbbells; Inverted Row / TRX Row not
  reaching the middle tiers. This starved the V4 cascade's per-(pattern x tier)
  pool → attempt-3/universalPool fallbacks + over-tier equipment-violation picks
  for equipment-light users. A recurrence of the shallow-pool fallback class
  (40a426, 2026-05-04, "38 universalPool cascade failures — pool too shallow").
concept: exercise_equipment_tier
sot_registry_entry: exercise_equipment_tier
writers:
  - { file: assets/data/exercise_library.json, line: 3062, source: "equipment_tier arrays — gains-only deepened on 90 rows so derive(equipment_needed) is a subset of equipment_tier (ADD-only, no drops)" }
  - { file: lib/core/services/seed_service.dart, line: 85, source: "_exerciseLibraryVersion 7->8 re-seeds the corrected equipment_tier into exerciseBox (idempotent putAll)" }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, line: 300, source: "queryV4 equipment filter — an exercise passes a tier iff its equipment_tier array contains that tier string (:298-307)" }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: exercise_library
cloud_columns: n/a
contract_test_path: test/contracts/equipment_tier_consistency_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: >
  n/a — the exercise library (exerciseBox) is a global bundled-asset seed, not
  user-scoped. equipment_tier is not synced or restored; a re-seed on version bump
  is the only writer.
forbidden_patterns_checked: >
  Verified the fix is GAINS-ONLY: for all 259 rows the new equipment_tier is
  (current union derive(equipment_needed)) — tiers are only ADDED, never removed,
  so no persona loses an exercise (byte-verified via re-parse: only equipment_tier
  changed). The equipment_needed-shape gate (e9d1c7) stays green (no bare Strings
  reintroduced). The scorecard equipment_violation_plan_count DROPPED 290->201,
  confirming the direction.
proposed_fix: >
  Library-wide gains-only equipment_tier normalization: equipment_tier <-
  equipment_tier union {T : EquipmentVocab.tierItems[T] superset-of
  normalize(equipment_needed)} on the 90 under-tagged rows (targeted text edits
  preserving .0 formatting). _exerciseLibraryVersion 7->8 re-seeds. Over-tag
  correction (a DROP-side change removing a tier an exercise cannot do) is a
  separate later pass — gains-only cannot regress the fallback gate.
regression_test_planned: >
  test/contracts/equipment_tier_consistency_test.dart — asserts, for every row,
  derive(equipment_needed) subset-of equipment_tier (no under-tag) using the REAL
  EquipmentVocab.normalize + tierItems (not a hardcoded copy) + every tier
  non-empty + canonical. Fails if a future row is under-tagged.
impact_analysis: >
  Live, pre-existing: every equipment-light user (bodyweight / home_dumbbells) got
  shallow pools → over-tier equipment-violation picks + attempt-3 fallbacks. Fix
  improved the frozen scorecard: coverage 88.6->92.3, overall 86.7->87.0,
  equipment_violation_plan_count 290->201, plans_with_fallback 370->281, 0
  progression/safety flips. Volume proxy dipped 70.4->68.0 (broader exercise
  variety spreads the default_sets SELECTION proxy — the scorecard's known
  limitation, not real undertraining; no muscle drops to zero, coverage rose in
  lockstep). Blast radius platform (plan engine + a prod seed re-apply).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "gains-only equipment_tier on 90 rows; flutter analyze clean; equipment_tier_consistency_test 2/2 green" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "exerciseBox re-seeds the corrected equipment_tier on next boot (_exerciseLibraryVersion 8)" }
  - { layer: postgres_data, status: verified, evidence: "cloud exercise_library re-seeded via migration 074 regen (259 rows); equipment_tier is NOT a coach-read column (getFormCues reads name/coaching_cues/primary_muscles) so cloud tier is inert for the coach — client Hive is the plan-selection source" }
  - { layer: client_server_contract, status: verified, evidence: "equipment_tier has one production reader (queryV4); swap/community/coach/warmup do not read it (Round-1 risk review)" }
---

## Root cause

The V4 equipment filter (`exercise_repository.dart:298-307`) keeps an exercise for a
user's tier **iff its own `equipment_tier` array literally contains that tier string**
(exact, non-cumulative). The bundled library repeatedly tagged bodyweight/dumbbell moves
at `["bodyweight","full_gym"]` or `["full_gym"]` only — skipping the middle tiers they
trivially satisfy. So a home_dumbbells or basic_gym user's `queryV4` returned a shallow
pool for those patterns, and the cascade dropped to attempt-3 (on-pattern, off-target) or
attempt-4 (over-tier, an equipment violation — an exercise the user can't actually do).
This is the shallow-pool fallback class first diagnosed as `40a426`.

## Fix

Gains-only, principled: for every row, `equipment_tier ← equipment_tier ∪ {tiers the row
is doable at}`, derived from `EquipmentVocab.tierItems` ⊇ `normalize(equipment_needed)`.
ADD-only (never remove a tier), so a) no persona loses an exercise and b) it can only
reduce fallbacks. 90 rows deepened. `_exerciseLibraryVersion` 7→8 re-seeds Hive; migration
074 regen re-seeds cloud.

## Verification

`equipment_tier_consistency_test` (derive ⊆ tier, real EquipmentVocab) 2/2 green; the
regenerated scorecard shows coverage +3.7, overall +0.3, equipment violations −89, 0
progression/safety flips (per-persona diff). Recurrence of `40a426` (shallow pool) — same
root cause (pool depth), different mechanism (tier tagging vs library size).
