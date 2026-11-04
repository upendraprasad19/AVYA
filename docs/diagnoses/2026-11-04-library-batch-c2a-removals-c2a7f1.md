---
bug_id: c2a7f1
date: 2026-11-04
batch: library-batch-c2a
status: fixed
blast_radius: account
symptom: >-
  The 914-row library carries 66 "sheet-drop" rows that the founder's review
  sheet says to remove: duplicates of a row that already ships, or rows the
  plan generator does not need. They still ship to every install and still sit
  active in the cloud copy of the library, and production code still quotes some
  of them by name (the universal pool, the injury substitutes, the warm-up and
  cool-down lists), so a later removal would silently empty those slots. Batch
  C2a removes the 50 whose removal is safe now and keeps 16, each with a reason.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
writers:
  - file: scripts/library_batch_c2_removals_gen.js
    method: builds scripts/data/library_batch_c2_removals.json (decision, reason, replacement and alias per id; the depth rule decides keep versus remove)
    line: 1
  - file: scripts/add_library_batch_c_v15.js
    method: importer --removals pass drops the removed rows and applies name aliases to the replacement rows
    line: 1
  - file: lib/core/services/library_retired_ids.dart
    method: kRetiredLibraryIdsNoTwin (the 50 removed ids with no merged_ids twin)
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 17 to 18, second pruneRetired call after putAll
    line: 139
  - file: scripts/seed_exercise_library.js
    method: cloud seed generator emits is_active=false for every removed id after the upsert, never upserting them, with an inline reactivation rollback
    line: 1
readers:
  - file: lib/core/services/seed_service.dart
    method_or_widget: seedIfNeeded re-seeds exerciseBox by id when the stored version is below 18 and prunes the removed ids
    line: 178
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: universalPoolV4 and _universalPool resolve pool names through the repository by name or alias
    line: 502
  - file: lib/shared/repositories/plan_engine/injury_substitutes.dart
    method_or_widget: preferredFor reads the curated substitute names
    line: 77
  - file: lib/shared/repositories/plan_engine/warmup_cooldown.dart
    method_or_widget: warm-up and cool-down lists, injury map and duration map by name
    line: 29
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (re-seeded by SeedService v18 putAll; the 50 removed ids are pruned; UUID-keyed custom and community rows are never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns:
  - is_active
contract_test_path: test/contracts/library_batch_c2_removals_file_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Decide each of the 66 sheet-drop rows once, in a committed file built by a
  generator that applies a depth rule (after a removal every injury cell, slot
  pattern and equipment tier keeps at least min(before, 3) strength, prehab or
  mobility rows, under both movement_pattern and slot_pattern). Remove 50,
  keep 16 (4 forced by the full-library checks, 12 by the depth rule or because
  their replacement is a C2b twin that does not ship yet). Repoint every
  hard-coded name, give a removed name that differs from its replacement an
  alias on the replacement row, prune the ids from every install in a seed v18
  pass that never feeds retiredLibraryIds, and deactivate them in the cloud.
regression_test_planned:
  - test/contracts/library_batch_c2_removals_file_test.dart
  - test/contracts/library_depth_rule_test.dart
  - test/contracts/library_seed_v18_upgrade_behavioral_test.dart
  - test/contracts/library_batch_c2_name_readers_test.dart
  - test/contracts/library_batch_c2_removed_pin_behavioral_test.dart
  - test/contracts/exercise_library_cloud_seeded_test.dart
related_bugs:
  - c1d7a4  # Batch C1: the 629 rows whose arrival made these removals safe
recurrence: |
  Recurrence class feedback_injury_tag_per_injury_no_kept_safe (injury coverage
  thins when rows go). The depth rule is the answer to it: no cell may fall
  below min(before, 3) after a removal. It did not see the uninjured cell, which
  is how E254 and E281 were found (see the findings below).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "importer removals pass, seed v18 prune, name repoints in exercise_selector, injury_substitutes and warmup_cooldown, with the tests listed in regression_test_planned" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v18_upgrade_behavioral_test.dart drives the real SeedService.seedIfNeeded on a v17 box: the 50 removed ids are gone, every other row and the UUID custom and community rows stay" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change: the removed rows are deactivated through the existing is_active column." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Live data is touched only by the seed migration applied at the end of this batch; its live results are recorded in the amendment commit." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "The seed migration is minted and applied in the last step of this batch (own explicit go); this entry is amended with the number and hash." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function is touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is added or changed." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy is touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No bucket or object is touched; the 8 plate SVGs of removed rows are deleted from the app assets only." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret is touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No Razorpay, OneSignal or Firebase surface is touched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Client side: a repeat plan pinned to a removed name drops it and refills (library_batch_c2_removed_pin_behavioral_test.dart, mutated). Server side: the generated seed SQL is compared to the committed library by exercise_library_cloud_tuples_match_test.dart once the migration exists." }
impact_analysis: >-
  The shipped library goes from 914 to 864 rows. Installs re-seed once on the
  next launch (v18) and lose the 50 ids; stored plans that name a removed row
  fall through the existing read paths (null-safe, listed below). Removed names
  that differ from their replacement now resolve through name_aliases, so a
  stored Reverse Lunge becomes a Forward Lunge (G3470). The plan generator's
  output changes for some personas (golden re-recorded). Cloud rows are
  deactivated, not deleted.
---

# Batch C2a: library removals

Plan: `docs/plans/2026-11-04-library-batch-c2a-removals.md` (r4, three review rounds, the last mechanical only). The twins, the E230 retag and the media are C2b (OI-462).

## What changed

- 50 rows removed from `assets/data/exercise_library.json` (864 left), decided in `scripts/data/library_batch_c2_removals.json`. Replacements: E293 to E291 (founder), E144 to G3470 (alias), E075 to E008 (alias), E265 to E280, E210 to G1428 (alias), E218 to G0794 (alias); G1429 `progression_to` points at G3418 (founder).
- 16 rows kept. Forced (the full-library checks needed them): E208, E221, E254, E281. Depth: E111, E119, E148, E234, E261, E263, E271. Twin pending (C2b, OI-462): E084, E162, E169, E179, E211; E111 also has a C2b twin (G1489) but the depth rule holds it first, so C2b re-checks it once G1489 ships.
- Seed v18 prunes the removed ids through a new `kRetiredLibraryIdsNoTwin` set (no `merged_ids` twin), a second `pruneRetired` call that never feeds `retiredLibraryIds`.
- Repointed names: universal pool and `_universalPool`, the cascade tracer mirror, injury substitutes, the safe pool, warm-up and cool-down lists. Eight plate SVGs of removed rows deleted.
- Cloud: the seed generator emits `is_active = false` for the removed ids (after the upsert, never upserting them) and a reactivation rollback. The migration itself is the last step of the batch.

## Findings worth keeping

- **E254 and E281.** The depth rule cannot see the uninjured cell. Removing them left a push/pull slot with no pick in the generator's own sweeps (hard zero), so they became forced keeps. Lesson: a depth rule over injury cells needs the uninjured cell as a row too.
- **Accepted regression.** Repeat home_dumbbells thin days for an ankle injury go 110 to 112; net improvement elsewhere (golden re-recorded, sweeps and scorecard green).
- **Orphaned animations (OI-443).** Old-row animations of held E146 and of removal-slated E075 E101 E210 E243 E256 have no row to show on; recorded on OI-443.
- **`standard_swap` is dead.** Eight kept rows name removed rows in `standard_swap`; nothing reads that field. Left as is.
- **Alias.** "Reverse Lunge" is an alias on G3470 Forward Lunge, so a stored Reverse Lunge turns into a Forward Lunge. The founder is told at the end of the batch.
- **Read paths checked null-safe** for an id that no longer exists: coaching content panel, plate resolver, train provider, session estimate, plateau scan, volume titration, quote picker, swap service.

## Mutation evidence (rule 21)

Each mutant applied to the real file, the targeted test run, the file restored (`git diff` empty):

- `library_batch_c2_name_readers_test.dart`: a removed name ("Z Press") added to `_universalPool`: red (names a removed row and resolves to 0 rows). An alias carried by two rows: red.
- `library_batch_c2_removed_pin_behavioral_test.dart`: the removed rows seeded back into the Hive box: red (a removed row emitted).
- `equipment_exclusion_filter_behavioral_test.dart` (the new resolving-survivor assertion): the `elbow_flexion` pool replaced by removed names: red for `elbow_flexion`; the old assertion stayed green on the same mutant (it passes vacuously for a missing name).
- The depth helper, the removals file test, the seed v18 test and the cloud tests carry their own mutations in their files.
