---
bug_id: e1a7c4
date: 2026-07-19
batch: exercise-lib-13a
blast_radius: platform
status: fixed
symptom: >
  9 exercises E252-E260 (Wall Sit, Bodyweight Good Morning, Doorframe Curl, Towel
  Row, Negative Pull Up, Glute Kickback, Dumbbell Calf Raise, Split Squat, Incline
  Dumbbell Press) used a DIFFERENT malformed schema — `muscle_primary`/
  `muscle_secondary` (not `primary_muscles`), `is_compound`/`sets_default`/
  `rest_seconds`/`difficulty`, and were MISSING `injury_contraindications` +
  `primary_muscles` entirely. Two live consequences: (1) SAFETY — the queryV4
  injury filter guards `contra is List && contra.isNotEmpty`, so a MISSING field
  is never excluded → E252 Wall Sit (knee_dominant) was served to knee-injured
  users; (2) the rows were invisible to muscle-based selection + volume titration
  (which read `primary_muscles`), so useful bodyweight moves (E253 hip-hinge, E254
  biceps, E255 row, E256 pull) were half-dead. Kin of e9d1c7 (which fixed only the
  `equipment_needed` bare-String shape on the same 9 rows).
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
writers:
  - { file: assets/data/exercise_library.json, line: 16630, source: "E252-E260 normalized to the 38-key canonical schema (muscle_primary->primary_muscles etc.; + injury_contraindications per movement_pattern; dropped 13 stub-only keys)" }
  - { file: lib/core/services/seed_service.dart, line: 85, source: "_exerciseLibraryVersion 7->8 re-seeds — putAll replaces each stub's whole map (no stale keys linger)" }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, line: 340, source: "queryV4 injury filter (:335-345) — `contra is List && contra.isNotEmpty`; a missing injury_contraindications was NEVER excluded (the E252 hole)" }
  - { file: lib/shared/repositories/exercise_repository.dart, line: 272, source: "queryV4 reads `primary_muscles` (:270-282) — the stubs' `muscle_primary` was invisible to muscle-target selection + volume titration" }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: exercise_library
cloud_columns: primary_muscles, secondary_muscles, difficulty_level, logging_type
contract_test_path: test/contracts/exercise_library_schema_contract_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: >
  n/a — exerciseBox is a global bundled-asset seed, not user-scoped. Re-seed on
  version bump replaces the malformed maps; `is_custom` (dropped) is read by no
  library-row reader (only the custom-exercise box carries it — Round-2 verified).
forbidden_patterns_checked: >
  Verified NO reader (lib/ + supabase/functions/ + test/ + scripts/) of any dropped
  stub key: muscle_primary, muscle_secondary, is_compound, sets_default,
  rest_seconds, difficulty, sub_focus, tags, regression, progression, is_custom,
  image_url, video_url (Round-2 grep). Canonical rows use image_start_url/
  image_end_url/gif_url/difficulty_level — the stub keys were dead data. Re-parse
  confirmed the 9 stubs now carry EXACTLY the 38 canonical keys, 0 stub-only keys
  remain, and non-stub rows are byte-unchanged.
proposed_fix: >
  Normalize E252-E260 to the 38-key canonical schema (rename muscle_primary->
  primary_muscles / difficulty->difficulty_level / sets_default->default_sets /
  rest_seconds->default_rest_secs; add is_active/default_reps/tempo/cal_per_set_est/
  cns_demand/is_bilateral/standard_swap/image_*; drop is_compound (exercise_type
  present) + is_custom + sub_focus/tags/regression/progression). Inject
  `injury_contraindications` per the movement_pattern methodology (E252 Wall Sit ->
  ["knee"], closing the safety hole; E258 calf stays knee_dominant per library
  convention -> ["ankle"]). _exerciseLibraryVersion 7->8; migration 074 regen
  propagates primary_muscles/difficulty_level to the coach's cloud copy.
regression_test_planned: >
  test/contracts/exercise_library_schema_contract_test.dart — every row carries
  EXACTLY the 38 canonical keys (blocks stub-shaped rows), no row is MISSING a List
  injury_contraindications (the E252 hole), primary_muscles non-empty on every row,
  259 rows + ids unique.
impact_analysis: >
  Live SAFETY hole: a knee-injured user with injuries set was served Wall Sit (and
  the other stubs were un-excludable for their real joints) because a missing
  injury_contraindications field bypasses the always-on injury filter. Also a
  quality gap — 4 useful bodyweight moves (hip-hinge / biceps / row / pull) were
  invisible to muscle-based selection. Fix closes both; the coach's cloud copy
  (getFormCues) gets real primary_muscles via the 074 re-apply (was NULL). Blast
  radius platform (plan engine + a prod seed re-apply).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "9 stubs -> 38-key schema + injury tags; flutter analyze clean; exercise_library_schema_contract_test 5/5 green" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "exerciseBox re-seeds normalized stubs (_exerciseLibraryVersion 8); primary_muscles/injury_contraindications now present + read" }
  - { layer: postgres_data, status: fixed_in_this_batch, evidence: "migration 074 regen (259 tuples) heals the cloud stubs' NULL primary_muscles/difficulty_level that getFormCues reads (H4) — re-applied to prod (idempotent ON CONFLICT DO UPDATE)" }
  - { layer: migrations_applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json 074 hash + applied_at updated (paired, sec 4.5); count-parity test 259==259" }
---

## Root cause

The 9 stubs predate the canonical schema and were authored with a different key set
(`muscle_primary`, `is_compound`, `sets_default`, …) and NO `injury_contraindications`.
The always-on queryV4 injury filter (`exercise_repository.dart:335-345`) guards
`contra is List && contra.isNotEmpty` — so a **missing** field is silently treated as
"no contraindication" and the row is never excluded. E252 Wall Sit (`knee_dominant`) was
thus served to knee-injured users. The rows were also muscle-invisible (`muscle_primary`
≠ the `primary_muscles` reader), so useful bodyweight moves half-worked. `e9d1c7` earlier
fixed only the `equipment_needed` bare-String shape on these same rows.

## Fix

Normalize all 9 to the 38-key canonical schema (key renames + net-new canonical fields +
injury tags per movement_pattern + drop the 13 dead stub-only keys). `putAll` on re-seed
replaces each map wholesale. Migration 074 regen propagates the healed `primary_muscles`/
`difficulty_level` to the cloud copy the AI coach reads.

## Verification

`exercise_library_schema_contract_test` 5/5 (38-key uniformity, injury completeness,
primary_muscles non-empty, 259 unique). Re-parse verified only the 9 stubs changed. Kin
of `e9d1c7` (same 9 rows, different field).
