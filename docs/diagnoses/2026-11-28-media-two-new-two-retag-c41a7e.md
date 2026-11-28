---
bug_id: c41a7e
date: 2026-11-28
batch: media-two-new-two-retag
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Library change, not a defect report. Two rows had an animation waiting that showed different kit from the row (E027 T-Bar Row
  labelled barbell, picture a plate-loaded station; E120 Svend Press labelled barbell, picture a weight plate), and the library had
  no machine preacher curl and no forward band Pallof press although unused animations of both existed. Founder decisions
  2026-11-28 (plan docs/plans/2026-11-28-media-two-new-two-retag.md): add G0592 and G0979, retag E027 to machines with new
  instructions, retag E120 to dumbbells with instructions unchanged, no injury restriction on the Band Pallof Press.
  This is the diagnose doc the cloud seed migration header links, and the one the frozen row reference asks for: it re-records
  the rows E027 and E120 only.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
contract_test_path: test/contracts/library_v30_two_new_two_retag_contract_test.dart
related_bugs: [b4d9e1, d8ac69]
recurrence: |
  Not a recurrence. It follows the retag shape of d8ac69 (Batch C2c, E230) and the kept-row record shape of b4d9e1.
writers:
  - { file: scripts/add_library_batch_c_v15.js, method_or_widget: "RETAG_FILES list (E230, E027, E120) and the source rows G0592 / G0979", line: 225 }
  - { file: scripts/seed_exercise_library.js, method_or_widget: "kept-row records grouped by row id; BATCH v30", line: 57 }
readers:
  - { file: lib/core/services/seed_service.dart, method_or_widget: "_seedExercises (putAll by id at exercise_library_version 30)", line: 358 }
  - { file: supabase/functions/_shared/tools/exercise/getFormCues.ts, method_or_widget: "reads cloud coaching_cues by name or alias", line: 65 }
hive_key_prefix: "exerciseBox (exercise_library rows by id); no per-user key"
hive_key_formula: "exerciseBox.put(row['id'], row) in SeedService._seedExercises (putAll, whole map replaced by id)"
sync_methods:
  - "none: exercise_library is bundle-seeded to Hive and migration-seeded to the cloud; no client sync writes it"
restore_methods:
  - "none: the library is not user data; the next launch re-seeds from the bundle (seed version 30)"
cloud_table: exercise_library
cloud_columns:
  - equipment_needed
  - coaching_cues
ist_handling:
  - { file: supabase/migrations/CLAUDE.md, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: the seed runs at launch before the providers read the library"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: exercise_library is shared reference data (RLS USING true); no user row is written or read by this change."
forbidden_patterns_checked:
  - { pattern: "a hand edit of assets/data/exercise_library.json that the importer --check does not reproduce", absent: true }
proposed_fix: |
  Two new source rows through the importer; the importer's retag stage takes a list of records (E230, E027, E120); the two held
  old-row pairs are released into the media input with a recorded decision; media table, stills and upload for four objects;
  seed version 29 to 30; a cloud re-seed migration (two changed rows, two inserts, inline rollback). The cloud generator now
  compares the previous tuple with every record column of a row reverted at once, because E027 changes two cloud columns.
regression_test_planned: |
  test/contracts/library_v30_two_new_two_retag_contract_test.dart, test/contracts/library_seed_v30_upgrade_behavioral_test.dart,
  the retag-list group in test/scripts/library_media_importer_test.dart, and the v30 checker and generator guard in
  test/contracts/exercise_library_cloud_seeded_test.dart.
impact_analysis: |
  Platform tier. E027 leaves the basic_gym pool (machines is full_gym only), E120 enters home_dumbbells, G0592 enters full_gym and
  G0979 enters home_dumbbells, basic_gym and full_gym; the measured effect on generated plans is recorded in the plan-review
  record. The migration changes the live coach at once (getFormCues): a partial search for "pallof" returns Band Pallof Press
  ahead of Band Vertical Pallof Press, and E027's new cues reach installed apps whose bundled row still says barbell. Nothing
  under lib/ reads the cloud exercise_library table.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "SeedService._exerciseLibraryVersion 29 -> 30; importer --check byte-identical to the shipped library." }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v30_upgrade_behavioral_test.dart: a v29 box ends at v30 with the four rows as bundled and every other row unchanged; a v30 box is not rewritten." }
  - { layer: postgres_schema, status: verified, evidence: "equipment_needed and coaching_cues are existing columns; equipment_tier and gym_availability are not cloud columns (COLUMN_SQL in the seed generator); no schema change." }
  - { layer: postgres_data, status: fixed_in_this_batch, evidence: "the generated draft differs from migration 183 by exactly two changed tuples (E027, E120) and two new ones; the live apply and its per-row read-back are recorded in the apply commit and happen only on the founder's go." }
  - { layer: storage_buckets_objects, status: fixed_in_this_batch, evidence: "four objects (1,487,888 bytes): dry run 4 local files ok, 0 sha mismatch; the upload runs only on the founder's go and is verified with --verify." }
---

## Frozen row reference

`test/fixtures/exercise_library_v12_row_hashes.json` is re-recorded for exactly **E027** (equipment_needed, equipment_tier,
coaching_cues) and **E120** (equipment_needed, equipment_tier, gym_availability).

## Plan review

Two context-blind Sonnet rounds. Round 1 found the planned step order would have left both new rows without injury tags and
media (the builders only see rows that already exist), the unit tests that stay red until the migration is applied, and missed
pins. Round 2 simulated the corrected order on a copy and converged, with wrong script flags and further pins.
