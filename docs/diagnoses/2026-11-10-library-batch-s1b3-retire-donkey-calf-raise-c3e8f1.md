---
bug_id: c3e8f1
date: 2026-11-10
batch: library-batch-s1b3
status: fixed
blast_radius: platform
symptom: >-
  OI-147: E053 Donkey Calf Raise ("not feasible generally", founder, exercise-plates brainstorm) was still in the library
  and still picked for bodyweight Calves slots. Removing one row touched the importer (the shipped library must equal
  a fresh import byte for byte), the media table (every file active and referenced), the seed (an install keeps a row
  putAll never deletes), the cloud seed generator (its rollback could not reactivate a row retired through merged_ids,
  and its header called every retire UPDATE "already inactive") and the injury builder's frozen sibling pool.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
writers:
  - file: scripts/data/library_s1b3_merges.json
    method: the merges record {id E053, name Donkey Calf Raise, into G1373, merged_in s1b3}
    line: 1
  - file: scripts/add_library_batch_c_v15.js
    method: the MERGE STAGE (readMerges / applyMerges) after the standard_swap repoint, before the media stage (applyMerges)
    line: 348
  - file: scripts/build_library_media_v16.js
    method: buildPrune --drop-unmapped / --stills-dir (a slug that lost its last row leaves with its still)
    line: 196
  - file: scripts/seed_exercise_library.js
    method: BATCH S1b-3 (mergesFile, name_aliases kept-row record, previous 174), ownMerged, arrayLiterals, mergedReactivateLines, computed header sentences
    line: 46
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 23 to 24 (a v24 comment block above it); the merged_ids prune deletes E053 from every install
    line: 172
readers:
  - file: lib/core/services/seed_service.dart
    method_or_widget: SeedService.retiredLibraryIds / pruneRetired (merged_ids not shipped, deleted from exerciseBox)
    line: 271
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: getByExactName / search match name_aliases, so a plan row or template holding "Donkey Calf Raise" resolves to G1373
    line: 49
  - file: supabase/functions/_shared/tools/exercise/getFormCues.ts
    method_or_widget: exact / partial name match with no is_active filter (inactive E053 answers with the cues copied from G1373)
    line: 67
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (SeedService v24: putAll by id, then the merged_ids prune deletes E053; a community row of the same name has a UUID key and is never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: [name_aliases, is_active, coaching_cues, common_mistakes]
contract_test_path: test/contracts/library_seed_v24_upgrade_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "hand-edit of the shipped library", absent: true }
  - { pattern: "hand-edit of the media table old_rows sha256 without the recomputing test", absent: true }
proposed_fix: >-
  Library Batch S1b-3 (plan docs/plans/2026-11-10-library-batch-s1b3-retire-donkey-calf-raise.md v5, five review
  rounds): E053 merged into G1373 Bodyweight Standing Calf Raise (same muscle, pattern, tiers and levels; the nearest
  bodyweight version) through a new importer merge stage driven by a record; G1373 gains merged_ids [E053] and
  name_aliases [Donkey Calf Raise]; the media table drops E053's row and its 0284 file entry with the bundled still
  (--drop-unmapped); seed v24; the cloud migration 175 deactivates E053 for the first time and its inline rollback
  reactivates it with its own cues spliced verbatim from migration 174.
regression_test_planned:
  - test/contracts/library_seed_v24_upgrade_behavioral_test.dart
  - test/scripts/library_media_importer_test.dart
  - test/scripts/library_media_builder_test.dart
  - test/contracts/exercise_library_cloud_seeded_test.dart
  - test/contracts/library_batch_c_rows_contract_test.dart
  - test/contracts/exercise_library_merge_contract_test.dart
  - test/contracts/library_batch_c_injury_coverage_test.dart
related_bugs:
  - b7e2c4  # Library Batch S1b-2, the batch before (seed v23, migration 174); split E053 out to this batch
  - ada3fb  # the cloud seed contract the generator and its tests extend
recurrence: |
  Not a recurrence of a bug class. The removal mechanism (merged_ids and the seed prune) is Batch A's (library v12,
  seven pairs); this is its first use on a SOURCE-built kept row, which the importer rebuilds every run, hence the
  record-driven stage. The self-inclusion lens (code-review SKILL lens 6) applied twice: the injury builder reads its
  original-sibling pool from the library this batch shrinks (E053 frozen as an original, mirrored against the base
  fixture), and the generator reads the previous migration it extends.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Importer merge stage, builder --drop-unmapped, generator S1b-3, seed v24; mutations below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v24_upgrade_behavioral_test.dart drives the real SeedService.seedIfNeeded: a v23 box loses E053, G1373 is written as bundled, a community row named Donkey Calf Raise and every other row are unchanged; a v24 box is not rewritten." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "name_aliases is an existing cloud column (backups/live_schema_columns.json); merged_ids is JSON-only, as in Batch A." }
  - { tier: 4, name: postgres_data, status: fixed_in_this_batch, evidence: "Migration 175 applied live 2026-11-10 after the founder go: 934 / 871 / 63 (md5 fd91c822) became 934 / 870 / 64 (md5 3170849a, equal to the local rehearsal); E053 inactive with G1373's cues, G1373 name_aliases [Donkey Calf Raise]." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json entry 175 (sha256 3ff320a2…), written in the same commit as the file." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function code changes; getFormCues reads exercise_library by name." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy is touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: verified, evidence: "The 0284-donkey-calf-raise object stays in the private exercise-media bucket, mapped by nothing (a known orphan, docs/operations/EXERCISE_MEDIA.md); nothing deletes storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret is touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service is touched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The library reaches the client through the bundled asset and the seed; the cloud copy serves getFormCues by name." }
impact_analysis: >-
  OFF (every user today): E053 leaves queryV4 pools (bodyweight and home Calves slots); the golden is re-recorded with
  every changed key attributed by counterfactual (plan Results). ON (dark): G1373 was already the core-list calf row and
  E053 had core_levels [], so the core-list pool is unchanged.
---

# Library Batch S1b-3: E053 Donkey Calf Raise merged into G1373 (c3e8f1)

## What changed
- E053 leaves the bundle through a new importer merge stage (record `scripts/data/library_s1b3_merges.json`); G1373
  gains `merged_ids: [E053]` and `name_aliases: [Donkey Calf Raise]`.
- The media table drops E053's row and the `0284` file entry; the bundled still is deleted (builder `--drop-unmapped`).
- Seed v24: every install prunes E053 on its next launch.
- Migration 175: E053 deactivated (first time) with G1373's cues; G1373 `name_aliases` set; inline rollback restores
  both, E053 with its own cues from migration 174.
- The injury builder keeps E053 as a FROZEN original calf_raise sibling, so the founder-approved table still rebuilds.

## Mutation evidence (rule 21)
| mutation | red |
|---|---|
| importer: merge stage skipped | 11 (importer, rows contract) |
| importer: drop skipped | 1 |
| importer: alias not appended | 8 |
| importer: source-row refusal off | 1 |
| importer: merge only when the row is present | 8 |
| importer: chain refusal off (B-pass) | 1 |
| builder: --drop-unmapped ignored | 1 |
| builder: a taken_down slug dropped | 1 |
| builder: a pre-existing unmapped file dropped | 1 |
| builder: still-present refusal off | 1 |
| builder: a pruned row's slug dropped though a twin still maps it (B-pass) | 1 |
| injury builder: frozen E053 original removed | 2 |
| seed: version back to 23 | 1 (v24 test; the older version pins also move) |
| library: G1373 merged_ids dropped | 2 |
| generator: six-array refusal off | 1 |
| generator: merged reactivation dropped | 3 |
| generator: still-in-library refusal off | 1 |
| generator: batch-tag filter off | 1 |
| blast radius: the merges rule removed | 2 |

Every mutation was applied by exact-count replacement (count 1 asserted) and restored; the generator output was re-run
and compared byte for byte with migration 175 after the generator mutants.
