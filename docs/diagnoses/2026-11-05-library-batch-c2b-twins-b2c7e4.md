---
bug_id: b2c7e4
date: 2026-11-05
batch: library-batch-c2b
status: fixed
blast_radius: platform
symptom: >-
  Batch C2a kept six sheet-drop rows (E084 Ankle Circles, E211 Ankle Rotations,
  E111 Sissy Squat, E162 Piriformis Stretch, E169 Seated Piriformis Stretch,
  E179 Toes to Bar) because their replacement rows, the four held-out twins
  G1368, G1489, G2567 and G0474, were not shipped yet. Every install still
  carried six rows that duplicate an animation the founder already picked, the
  cloud still listed them active, and the twins (which carry the finished
  pictures, cues and injury tags) were missing from the library.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
writers:
  - file: scripts/data/library_batch_c_source.json
    method: the four name_collision holds are released (hold deleted, picture_checked and identity_checked filled; G1368 cue 1 rewritten to the standing version the picture shows)
    line: 1
  - file: scripts/build_library_injury_additions_v15.js
    method: TWIN registers G1368 G2567 G1489 G0474 with frozen tags (ankle, hip, knee, lower_back+shoulder) because their source rows leave in the same batch
    line: 37
  - file: scripts/library_batch_c2_removals_gen.js
    method: the six move from TWIN_PENDING to REPLACEMENT; the twin fixture joins the depth rows; every remove entry carries removed_in (c2a frozen list, else c2b)
    line: 1
  - file: scripts/add_library_batch_c_v15.js
    method: repointStandardSwap also matches id-form values (E043 "E111" becomes "G1489"); the importer run writes the 862-row library and the media keys
    line: 218
  - file: lib/core/services/library_retired_ids.dart
    method: kRetiredLibraryIdsNoTwin gains E084 E111 E162 E169 E179 E211
    line: 10
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 18 to 19
    line: 139
  - file: scripts/seed_exercise_library.js
    method: cloud seed generator inserts the four twins, deactivates all 56 removed ids, and scopes its rollback to the six rows of this batch plus the four inserted twins
    line: 1
readers:
  - file: lib/core/services/seed_service.dart
    method_or_widget: seedIfNeeded re-seeds exerciseBox by id below version 19 and prunes the retired ids after putAll
    line: 178
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: getByExactName resolves a retired name by exact name or by name_aliases (the old Ankle Rotations and Piriformis Stretch names live on G1368 and G2567)
    line: 44
  - file: lib/shared/repositories/plan_engine/warmup_cooldown.dart
    method_or_widget: _moveInjuries and durationMap key 'Ankle Circles' (dead entries, never emitted) mirrored against the library by warmup_library_injury_mirror_test
    line: 58
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (re-seeded by SeedService v19 putAll; the six retired ids are pruned; UUID-keyed custom and community rows are never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns:
  - is_active
  - coaching_cues
  - name_aliases
contract_test_path: test/contracts/library_seed_v19_upgrade_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Release the four holds after reading each animation, register the twins in
  the injury builder with their frozen tags, regenerate the removals file with
  the twin rows in the depth rule (so a removal is judged with its twin
  present), turn the six twin_pending rows into ordinary removals with a
  replacement and an alias, repoint E043's id-form swap, prune the six ids in a
  seed v19 pass, and insert the twins and deactivate the six in the cloud in one
  migration whose rollback covers only this batch. History keyed by a retired
  id is NOT remapped (merged_ids is never written by the importer and its only
  reader is the seed prune); the retired names still resolve by name or alias.
regression_test_planned:
  - test/contracts/library_depth_rule_test.dart
  - test/contracts/library_batch_c2_removals_file_test.dart
  - test/contracts/library_seed_v19_upgrade_behavioral_test.dart
  - test/contracts/library_batch_c2_name_readers_test.dart
  - test/contracts/library_batch_c2_removed_pin_behavioral_test.dart
  - test/contracts/library_batch_c_injury_coverage_test.dart
  - test/contracts/exercise_library_cloud_seeded_test.dart
  - test/contracts/warmup_library_injury_mirror_test.dart
related_bugs:
  - c2a7f1  # Batch C2a: kept these six rows as twin_pending
  - c1d7a4  # Batch C1: the 629 rows and the twin machinery
recurrence: |
  Recurrence class feedback_injury_tag_per_injury_no_kept_safe: the twins carry
  their sources' tags frozen as constants (the builder's floor and majority read
  E originals that leave), mirrored by library_batch_c_injury_coverage_test
  against the base fixture, so the tags cannot thin as the sources go. Also the
  guard-without-its-mirror class: the depth rule judged a removal WITHOUT its
  twin (E111 stayed a depth keep); the twin fixture plus a mirror guard against
  the shipped G rows is the other side of that guard.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "importer, seed v19 prune, warm-up map key, removals generator, with the tests listed in regression_test_planned" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v19_upgrade_behavioral_test.dart drives the real SeedService.seedIfNeeded on a v18 box holding the six rows: the six are gone, the four twins arrive, the retired names resolve to the twins by exact name or alias; a fresh install gets the four and none of the six" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change: the twins are rows, the six are deactivated through the existing is_active column." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live SELECT before the apply (2026-11-05, two independent reads): 921 rows, 864 active, 57 inactive, the six ids active, the four twin ids absent. Post-apply read-back (2026-11-05, after migration 171): 925 rows, 862 active, 63 inactive; each of Ankle Circles, Sissy Squat, Seated Piriformis Stretch and Toes to Bar has exactly one active row (the twin) and one inactive row (the old one)." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "One reseed migration, applied with the founder's go on the exact file; backups/applied_migrations.json carries its sha256 in the same commit as the file (Gate 14 forbids the file before the apply)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function is touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is added or changed." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy is touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: fixed_in_this_batch, evidence: "Four animation objects for the twins (slugs 0474 1368 1489 2567) are uploaded to the private exercise-media bucket with the founder's go on the exact command (upload_exercise_media.js --only the four slugs, then --verify --only); DONE 2026-11-05: 4 uploaded, 0 failed (1,586,780 bytes), then --verify --only 4 of 4 match, privacy probe 400. BEFORE that upload no build or release may carry library v19 (B-pass C2b finding 1: the bucket held 755 objects and none for these four). Two plate SVGs of the removed Sissy Squat are deleted from the app assets only." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret is touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No Razorpay, OneSignal or Firebase surface is touched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Client: the v19 test above. Server: exercise_library_cloud_tuples_match_test.dart compares the generated SQL to the committed library line for line once the migration is on disk (green with the file in the no-commit window; red without it by design)." }
impact_analysis: >-
  The shipped library goes from 864 to 862 rows (4 twins in, 6 rows out).
  Installs re-seed once on the next launch (v19). Stored plans or logs that name
  a retired row by ID are not remapped; by NAME they still resolve (Ankle
  Rotations to G1368, Piriformis Stretch to G2567; the four same-name rows now
  resolve to their twin). The plan generator's output changes for 8 of 998
  golden personas (below). Cloud rows are inserted or deactivated, never
  deleted.
---

# Batch C2b: the four twins and the six twin_pending removals

Plan: `docs/plans/2026-11-05-library-batch-c2b-twins.md` (draft 4; review rounds 3 and 4, round 4 mechanical only). E230 moved to OI-474 (Batch C2c) at plan review round 2 under CLAUDE.md section 4.12.1.

## What changed

- **Twins.** G1368 Ankle Circles, G1489 Sissy Squat, G2567 Seated Piriformis Stretch, G0474 Toes to Bar ship (library 862 rows). Each animation was read frame by frame before its hold was released. G0474's gif 0474 is a true toes-to-bar (feet reach the bar with the torso curled; the folder name says Hip Raise but the picture does not). G1368's first cue said "Sit and lift one foot", the picture is standing: rewritten. G1489's picture shows a bench held for balance; the cue says a post, so equipment stays bodyweight (the depth rule needs that tier).
- **Six removals.** E084 E211 to G1368 (E211's name "Ankle Rotations" becomes an alias), E162 E169 to G2567 (E162's "Piriformis Stretch" becomes an alias), E111 to G1489, E179 to G0474. E111 leaves ONLY because the depth rule, judged with G1489 present, lets it go; without the twin it is a computed depth keep (mutation below).
- **Removals file** is regenerated, 56 remove and 10 keep (depth keeps E119 E148 E234 E261 E263 E271, forced E208 E221 E254 E281); every remove entry carries `removed_in` (`c2a` for the frozen 50, `c2b` for the six).
- **E043 Leg Extension** `standard_swap` named "E111" by id; the importer's repoint stage now matches ids and writes "G1489". Nothing reads the field.
- **Seed v19**, the six ids join `kRetiredLibraryIdsNoTwin`. **Plates**: Sissy Squat's two SVGs and its mapping entry are deleted (149 rows carry artwork, 147 slugs, 280 files). **Warm-up map**: the dead `'Ankle Rotations'` keys become `'Ankle Circles'` (a mirror test forces it; no plan changes). **Media**: four rows and four stills added (758 table rows on 757 files, 621 new-row G/N rows).
- **Cloud** (the migration is the last step): inserts the four twins, deactivates all 56 removed ids (the 50 of C2a are already inactive), rollback scoped to this batch (reactivate the six, deactivate the four twins).

## Findings worth keeping

- **The depth rule must see the twin.** The frozen base fixture has no twin rows, so E111 stayed a keep. `test/fixtures/library_c2b_twin_rows.json` adds the four rows to both the before and the after reading; a mirror guard pins the fixture to the shipped G rows.
- **`merged_ids` is not a remap.** The importer never writes it, and its only reader is the seed prune. The plan dropped it in review round 1; history by retired id is not remapped (accepted, pre-launch, CLAUDE.md section 1).
- **Generator golden: 8 of 998 personas change**, all `grid|home_dumbbells|build_muscle|4d` (advanced p1-p5, intermediate p4-p5, beginner p5). Later weeks swap Step Up (E044) for Lateral Lunge (E145). Traced by probe: removing any one of the six alone, or adding G1368, G2567 or G0474 alone, leaves every plan byte-identical; the change is the E111 to G1489 swap (G1489 carries variant_family `sissy_squat` and secondary muscle Core, E111 had neither), which re-orders a home pool. Accepted, golden re-recorded.
- **Injury sweeps and scorecard:** all five injury sweep files, `scorecard_gate_test`, `core_list_pool_gate_test`, `session_set_budget_gate_test` and `injury_safe_omission_test` green (50 tests, 2 skipped). The C2a ceiling `repeat bodyweight` stays `(4, 0)` (4 thin days: elbow 2, lower_back 2; 0 one-exercise; 0 empty).
- **The no-commit window.** The cloud tests (`exercise_library_cloud_seeded_test`, `exercise_library_cloud_tuples_match_test`) and `applied_migrations_parity_test` read the newest seed migration or the ledger, so they are red until the migration file is on disk and ledgered. Gate 14 is red while the file is on disk without its ledger entry. The gate loop ran with the file absent (pre-commit) and present-untracked (full tests), then the file was removed.

## Mutation evidence (rule 21)

Each mutant applied to the real file, the targeted tests run, the file restored and compared byte for byte:

- `SeedService._exerciseLibraryVersion` 19 back to 18: 5 tests red (v19 and v16 upgrade tests).
- `E179` deleted from `kRetiredLibraryIdsNoTwin`: 3 red (v19 upgrade, v18 equality).
- `warmup_cooldown.dart` key back to `'Ankle Rotations'`: 1 red (`warmup_library_injury_mirror_test`).
- E043 `standard_swap` set back to `E111` in the library: 2 red (`library_batch_c2_name_readers_test`, `exercise_library_frozen_reference_test`).
- `removed_in` of one C2a id flipped to `c2b` in the removals file: 3 red (`library_batch_c2_removals_file_test`).
- G1489 deleted from the twin fixture: 5 red (depth rule and removals file tests).
- G1489's injury tokens emptied in the table: 2 red (`library_batch_c_injury_coverage_test`).
- Seed generator `ownRemoved` widened to every removal: 2 red (cloud seeded test).
- The seed generator's twin flag: `replacement_new` deleted from E179 in the removals file: 2 red (removals file test, `--check`).
- The twin fixture edited (one note character) without regenerating the removals file: 1 red (the sha256 pin in the depth rule test).
- The depth rule test also carries its own in-file mutation (G1489 removed from the base: E111 turns into a computed keep).

## B-pass (docs/reviews/library-batch-c2b-bpass.md)

0 P0, 0 P1, 5 P2, all handled here. (1) Media not in the bucket yet: ordering rule above. (2) The twin fixture note named a test that did not exist and its sha was recorded but never read: note corrected, a depth-rule test pins the sha256 to the removals file. (3) The seed generator inferred its twins from every c2b replacement, which would deactivate a live row for a batch whose replacement already ships: the removals file now flags `replacement_new` and the generator, its rollback and the tests derive twins from it (mutated). (4) `core_list_pool_behavioral_test` `_skillIds` still listed E101 and E179: now E069-E074, E086, E180 and G0474. This is a data correction with NO behavioural proof of its own: taking G0474 out of the list again reddens nothing, because the selector already excludes skill rows by discipline (`core_list_selector.dart:187`, covered by the synthetic test in the same file). (5) ACCEPTED, no code change: between `putAll` and the prunes in `SeedService._seedExercises` an upgrading install briefly holds both E084 and G1368 named "Ankle Circles" (and the three other same-name pairs), and `getByExactName` returns the first key, the stale E row; the window is a few milliseconds of one awaited seed on app start, before any UI reads it, and after the prune every pair and both aliases resolve to the twins (the v19 test asserts that).

## Accepted behaviour changes (told to the founder)

- History keyed by a retired id (a logged E179, a swap entry for E111) is not remapped to the twin; the retired names still resolve.
- 8 golden personas change one later-week exercise (above).
