---
bug_id: b4e7a2
date: 2026-10-27
batch: library-batch-m
status: in_progress
blast_radius: platform
symptom: >-
  616 Wardroom animations (253,550,820 bytes) exist only on the founder's disk,
  and no library row says which animation it shows. 522 of the 617 mapped rows
  are already shipped in the library; none of them carries the data an app or a
  server would need to find its picture. Nothing stores the files either, and
  the founder's rule is that only a person who has installed the app and logged
  in may reach them, no one else. Batch M1 builds the data and the storage; the
  app side (M2) and the picture check of the 522 shipped rows (M1b, OI-437)
  come after it.
concept: exercise_media_fields
sot_registry_entry: exercise_media_fields
writers:
  - file: scripts/build_library_media_v16.js
    method: builds scripts/data/library_media_v16.json (id to slug, slug to file, every hash and size read from the files and checked against the ledger)
    line: 1
  - file: scripts/data/library_media_v16.json
    method: the committed provenance table (617 rows, 616 files)
    line: 1
  - file: scripts/add_library_batch_c_v15.js
    method: media stage writes media_slug, media_version, media_source last and in order on mapped rows (--media table|none)
    line: 1
  - file: scripts/upload_exercise_media.js
    method: moves the files into the private exercise-media bucket (dry run, canary, execute, verify, sign, delete, probes)
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 15 to 16
    line: 128
readers:
  - file: lib/core/services/seed_service.dart
    method_or_widget: seedIfNeeded re-seeds exerciseBox by id when the stored version is below 16
    line: 128
  - file: test/contracts/library_media_table_test.dart
    method_or_widget: CI links between the table, the media map and the library
    line: 1
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (re-seeded by SeedService v16 putAll when the stored version is below 16; customs and community rows are never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: []
contract_test_path: test/contracts/library_media_table_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Record the provenance once, in a committed table built by a tool that reads
  the real files and the Wardroom ledger (so a hash is never typed by hand),
  link it to the library by three fields on each mapped row, and store the files
  in a PRIVATE bucket whose only read policy is for a logged-in, non-anonymous
  account. Reads go through the authenticated route or a short signed URL,
  never a public link. The upload tool is pinned to this project and bucket and
  proves, with no-credential probes, that the bucket refuses a reader with no
  login and one with an anonymous session. Nothing in the app reads the fields
  yet (M2).
regression_test_planned:
  - test/scripts/library_media_builder_test.dart
  - test/contracts/library_media_table_test.dart
  - test/contracts/exercise_media_bucket_private_test.dart
related_bugs:
  - c1d7a4  # Batch C1: the 629 rows whose pictures this batch links
recurrence: |
  Not a recurrence of a bug class. The identity class from c1d7a4 (a row whose
  name and picture disagree) bounds what the table can promise: it links a row
  to the animation the founder's own map names, and it does not claim the
  picture is the right one for the name. That check is M1b (OI-437).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "builder, table, tests (31 builder tests, 24 table tests so far); importer media stage, seed v16 and the upload tool follow in this batch. The builder's seven protections were each neutered once and each reddened its matching test; the table test's nine legs were each neutered once and each reddened at least one test." }
impact_analysis: >-
  The library file gains three keys on mapped rows only; unmapped rows are
  byte-identical. Nothing reads the keys until M2, so no screen changes. The
  bucket is private and empty until the upload, so no user can reach a file
  before the founder's go. The seed constant moves 15 to 16, so installs re-seed
  the library once on the next launch; stored plans are unchanged.
---

# Batch M1: media data and storage

Plan: `docs/plans/2026-10-27-library-batch-m1-media-data.md` (r6, converged; executed inline). This file is completed at close-out (Task 10) with the live results.

## Task 1 results

- Builder `scripts/build_library_media_v16.js`: 31 tests in `test/scripts/library_media_builder_test.dart`, watched RED (module not found) then GREEN. Seven mutations, each applied to a saved copy, confirmed by a diff, run and restored (cmp identical): the animation disk sha no longer compared with the ledger, the thumbnail comparison gone, the recorded-sha comparison gone, `--prune-only` leaving a row, kebab without trimming, `_meta.taken_down` ignored, `omitted` not counted. Each reddened exactly the test written for it.
- Real table: 617 rows, 616 files, all active, sum of `webp_bytes` 253,550,820, largest 987,558, one version per file, N06 and G3643 on the one slug `3643-weighted-cossack-squats`, `_meta.old_rows` null, `_meta.taken_down` empty. `--check` is byte equality.
- `test/contracts/library_media_table_test.dart` (24 tests): the real data passes every leg of R10 (a) to (h) and R1; 18 broken copies each turn the matching leg red; each of the nine legs was neutered once and reddened at least one test.

## Task 2 results (importer media stage, library v16, seed v16)

- Importer `scripts/add_library_batch_c_v15.js` gained the media stage as a new function (`applyMedia`) and call; the lines holding `/*HELD-SKIP*/` and `[...rawTags, ...tableRow.tokens]` are untouched (`grep -c` 1 and 1 before and after). `--media <path>|none`; a missing default table is fatal; `--media none` is refused without `--library`. The importer test `test/scripts/library_media_importer_test.dart` ran RED (14 of 15 failing, the stage did not exist) and then GREEN (15 of 15). Eight protections were each neutered once in the importer, confirmed applied by a diff, run and restored (cmp identical): keys prepended instead of appended, a missing default table skipped, the refusal of an absent id gone, the strip of an unmapped old row gone, delete-then-set replaced by plain assignment, the E001 sentinel exclusion gone, a partial triple written, the `--library` requirement for `--media none` gone. Each reddened exactly its own test(s).
- Library regenerated: 914 rows, 617 carry the three keys, `--check` byte equality OK. With the three keys stripped it equals the previous library (`git show HEAD:assets/data/exercise_library.json`) row by row: 914 rows, 0 differing. The equipment audit gate passes on 914 rows.
- Seed constant 15 to 16 (`lib/core/services/seed_service.dart:128`). `library_seed_v16_upgrade_behavioral_test.dart` (3 tests): a v15 box gets the keys on exactly the mapped ids and version 16; a stored-13 install reaches 16; a v16 box is not re-seeded. With the constant put back to 15, two of the three redden.
- Pinned C1 assertions edited: `library_batch_c_rows_contract_test.dart` (plate keys stay forbidden; media keys only on ids the committed table maps, last three keys, in order; three importer spawns get `--media none`), `library_batch_c_injury_coverage_test.dart` (one spawn gets `--media none`), `library_seed_v15_upgrade_behavioral_test.dart` (`greaterThanOrEqualTo(15)`), `exercise_library_schema_contract_test.dart` (11 to 14 optional keys; a new "all three media keys or none, with the right types" leg and its mutation). The R10 (c) library-side legs live in `test/helpers/library_media_table_checks.dart`, used by the table test; each library-side check was neutered once and reddened its own test, and a partial-triple check that could never fail on its own was removed.
- SoT registry: `exercise_media_fields` added (writers: the importer stage and the seed constant; no reader file, M2 adds it); the `_exerciseLibraryVersion` line range re-pointed 122 to 128. `check_sot_registry_parity`, `check_sot_registry_citations` and Gate 42 pass.
- Local acceptance run of the R13 chains on a temp mirror of the real tree with the real Wardroom folder (victim G0103, slug `0103-barbell-standing-ab-rollout`): after the hold chain, after the release chain and after the takedown chain, the importer `--check` is OK, the builder `--check` is OK and the R10 conditions (a) to (h) evaluate to 0 violations (rows 616, 617, 616). After the hold the victim is not in the library; after the release it is back with its keys; after the takedown the row stays in the library without keys, its file has status `taken_down` and no row maps it.

## Task 3 results (cloud-copy proof)

`test/contracts/exercise_library_cloud_tuples_match_test.dart` (10 tests): the SQL generated from the committed library in a sandbox copy equals the newest seed migration (164) line for line; the one-time run recorded 0 differing lines of 954. A media key added to a row leaves it green. Mutations on the sandbox, each reddens: a changed name, cue list, equipment list or activation flag on one row; a row removed; a row added; one column dropped from the generator's SET list; the generator's retire statements dropped.
