---
bug_id: c1d7a4
date: 2026-10-26
batch: library-batch-c
status: fixed
blast_radius: platform
symptom: >-
  The exercise library held 285 rows, and 83 core-list rows (134 level slots: 56
  beginner, 47 intermediate, 31 advanced) that the B1 core-list pool needs were missing from
  it; its flip criteria (docs/ship_dark_pending_review.yaml) wait on them.
  Batch C1 adds 629 of the 708 converted sheet rows (79 held). Three problems
  had to be handled while adding them. (1) E274 Prone T Raise carried
  target_focus "Upper Back" while its slot_focus said "Mid Back", so a Mid Back
  slot could not see it. (2) The under-tag class: a row is excluded for an
  injured user only when its injury_contraindications list CONTAINS the user's
  token, so a new row with a missing tag is a silent pass, and four earlier
  batches each tagged only the rows in front of them. (3) The identity class:
  the sheet's name and cue text can disagree with the row's picture (G0007
  "Alternate Lateral Pulldown" is a seated cable pulldown, not a bodyweight
  move; G0980's cues were a triceps kickback on a band glute kickback; G0578
  Lever Squat's first cue described shoulder pads the machine does not have).
concept: exercise_injury_tags
sot_registry_entry: exercise_injury_tags
writers:
  - file: assets/data/exercise_library.json
    method: 629 rows appended (285 to 914), E274 target_focus Upper Back to Mid Back
    line: 1
  - file: scripts/add_library_batch_c_v15.js
    method: importer (allow-list of the 40 required keys, derived keys, tags = sorted(raw UNION table row), drop every source id then append the non-held rows, v13 formatter round trip, --check is byte equality)
    line: 1
  - file: scripts/build_library_injury_additions_v15.js
    method: add-only, merge-preserving builder of scripts/data/library_injury_additions_v15.json (629 rows, 29 safe_pool_additions)
    line: 1
  - file: scripts/library_batch_c_scope.js
    method: scope contract C1 to C6 over scripts/data/library_batch_c_source.json (which rows need a picture or identity read, holds, derived counts)
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 14 to 15
    line: 122
readers:
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: queryV4 injury filter (attempts 1 to 4)
    line: 412
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _isContraindicated (attempt 5, repeat pins, the thin-day top-up)
    line: 1715
  - file: lib/shared/repositories/plan_engine/core_list_selector.dart
    method_or_widget: CoreListSelector.rankedPool (B1, ship-dark, reads core_levels and the same injury filter)
    line: 1
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (re-seeded by SeedService v15 putAll when the stored version is below 15; customs and community rows are never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: []
contract_test_path: test/contracts/library_batch_c_rows_contract_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Add the rows through one importer from a committed source file and a
  founder-approved tag table, so the library file is a function of two
  reviewed inputs (--check proves byte equality), and tag every new row by
  rule, not by feel: each carries at least its original sibling's floor tokens,
  its family rule and its twin's tokens, recomputed independently in
  test/helpers/library_injury_floor.dart and asserted both on the library and
  on every row the real generator picks (golden R6 (ii)). Names that no check
  could settle are held, not shipped. E274 is relabelled by id in the importer.
  Seed v15 re-seeds existing installs. The cloud gets the same rows by an
  upsert-only migration (Task 7), rolled back by one UPDATE on
  source = 'exercise-gif-set'. Nothing is removed, renamed or aliased here
  (Batch C2). No flag flips; the OFF generator changes on purpose because 629
  rows join its pool.
regression_test_planned:
  - test/contracts/library_batch_c_rows_contract_test.dart
  - test/contracts/library_batch_c_injury_coverage_test.dart
  - test/contracts/library_batch_c_source_test.dart
  - test/contracts/library_seed_v15_upgrade_behavioral_test.dart
  - test/plan_generator/generator_golden_test.dart
  - test/plan_generator/injury_sweep_b_singles_test.dart
  - test/plan_generator/injury_sweep_a_pairs_test.dart
  - test/contracts/library_new_row_pick_violations_test.dart
  - test/plan_generator/core_list_pool_gate_test.dart
  - test/contracts/exercise_library_cloud_seeded_test.dart
related_bugs:
  - d30de7  # v14 injury re-check: the fifth under-tag instance and the per-injury rule this batch applies at ingestion
  - 2d04d7  # thin-day top-up: its residual (OI-408) is closed by these rows
  - f4c1e8  # Batch 13-B under-tagging
  - c2d5e8  # v13 safety-direction tags
  - e1a7c4  # 13-A injury field missing on stub rows
  - a1f6c3  # injury filter non-functional
recurrence: |
  Sixth instance of the under-tag class (a1f6c3, e1a7c4, f4c1e8, c2d5e8,
  d30de7): earlier batches tagged the rows in front of them, and the next batch
  that adds rows starts from nothing. Known-good fix applied and moved to the
  point of ingestion: the tag table is decided per injury by movement pattern
  with no "kept safe" list (feedback_injury_tag_per_injury_no_kept_safe, founder
  2026-10-23 and again 2026-10-26: nine rear-delt rows gain shoulder from the table (four more already carry it), three are
  safe-pool), the safe pool grows only by named, founder-approved additions
  (29, kV14SafePool 33 to 62, 4.6 percent of the new rows against 11.6 percent of
  the original 285-row library and 6.8 percent of the 914-row library after this batch), and a library-side test recomputes the floor, family and twin
  tokens independently of the table. New this time: the same check runs on what
  the real generator PICKS (golden R6 (ii)), so a tag lost after import is seen
  where users see it. The identity class (G0007, G0980, G0578) is new: the sheet
  is not a source of truth for what a row IS; the picture is.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "assets/data/exercise_library.json 285 to 914 rows (importer --check byte equality; idempotent; 629 shipped, 79 held: 13 token, 4 name_collision, 53 low_confidence, 9 picture); seed constant 15; E274 target_focus. Tests: library_batch_c_rows_contract_test 37, library_batch_c_injury_coverage_test (library group), library_batch_c_source_test, library_seed_v15_upgrade_behavioral_test, golden R6, five injury sweep files, core_list_pool_gate." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "SeedService v15 re-seeds exerciseBox by id via putAll when the stored version is below 15. library_seed_v15_upgrade_behavioral_test builds a v14 box with 285 library rows (E274 still Upper Back), a UUID-keyed custom exercise and a community row, runs seedIfNeeded, and reads back the 629 new rows, the 285 kept rows, E274 Mid Back, the custom and community rows untouched, version 15. Stored PLANS are not rewritten: pre-launch every account is a testing account (CLAUDE.md section 1)." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json exercise_library (26 columns: id, name, name_aliases, category, movement_pattern, exercise_type, muscles, equipment_needed, logging_type, difficulty_level, suitable_for, instructions, coaching_cues, common_mistakes, alternative_ids, regression_id, progression_id, default_sets/reps/rest/duration, source, is_active, is_indian_context, created_at). It has no target_focus and no injury_contraindications column, so E274 and every tag are Hive-only; no schema change." }
  - { tier: 4, name: postgres_data, status: blocked_on_user, evidence: "The cloud table gains the 629 rows by the upsert-only migration of Task 7 (generated by scripts/seed_exercise_library.js with the new name). The live apply needs the founder's explicit go (CLAUDE.md 4.3); this doc is updated in the commit that lands the file." }
  - { tier: 5, name: migrations_applied, status: blocked_on_user, evidence: "No migration applied yet: Task 7 mints the number with scripts/mint_migration.sh, rehearses the file, and records the ledger hash in the same commit; backups/applied_migrations.json is updated only after the apply." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "No Edge Function changes. getFormCues reads exercise_library by name with no is_active filter (supabase/functions/_shared/tools/exercise/getFormCues.ts:65 and :92), so a row the rollback deactivates would still serve cues: OI-438." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched; the upsert runs as the migration role." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object is added; 758 library rows have no artwork in the bundle (pinned by the plate and library data tests)." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real PlanGenerator.generateV4, flag OFF, on the 914-row library: the five injury sweep files (7,200 runs, 22 tests) have 0 unsafe, unresolved, unperformable, duplicate, empty, one-exercise and thin days; generator golden re-recorded (998 personas, 943 changed, 50 distinct new ids picked by 939 personas, top pick G0380 Dumbbell Rear Lateral Raise x589 = 59.0 percent); scorecard gate, core-list gate and B2 gate green on the final library. Cloud side: exercise_library_cloud_seeded_test has the generator and rollback assertions; three of its checks stay red until the migration file exists." }
impact_analysis: >-
  Every OFF plan can change because 629 rows join the cascade's pool: 943 of the
  998 golden personas differ (grid bodyweight 240, home_dumbbells 240,
  basic_gym 211, full_gym 215, extra 37). The change is intended (R6 of the
  plan) and bounded by assertions scoped to the new ids: no picked new row is a
  skill, olympic, plyometric, high-impact or requires-coaching row, and every
  picked new row carries its sibling floor, family and twin tokens. Kept rows are
  byte-identical except E274's target_focus. Users with a stored library get the
  rows on the next launch (SeedService v15); stored plans are unchanged. The flag
  state of every ship-dark feature is unchanged; B1's ON-world numbers are in
  docs/ship_dark_pending_review.yaml and OI-436.
---

# Batch C1: 629 new library rows, tagged by rule

Plan: `docs/plans/2026-10-25-library-batch-c-new-rows.md` (r9, converged after eight review rounds; executed inline). Spec: `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` section 9 row C, additions half. Removals, aliases, plates and the four name-collision rows are Batch C2.

## What was wrong

Three separate things, one batch.

1. **E274.** `E274 Prone T Raise` has `slot_focus` Mid Back and `target_focus` Upper Back. The cascade queries `target_focus`, so a Mid Back slot never saw it. The importer relabels it by id (`target_focus` Mid Back); the cloud table has no such column, so there is no cloud clause. The frozen reference fixture is re-recorded by id (`RECORD_LIBRARY_REFERENCE_IDS=E274`), the only kept row that changed.
2. **The under-tag class**, sixth instance (see `recurrence`). The always-on `queryV4` filter drops a row only when its list contains the user's token. A new row with no tag is a silent pass.
3. **The identity class.** `G0007` (name "Alternate Lateral Pulldown", picture: a seated cable pulldown, so cable + bench, compound, not bodyweight), `G0980` (cues were a triceps kickback; the picture is a standing band glute kickback, so the cues were replaced and the family set to `glute_kickback` like E109 and E257) and `G0578` (Lever Squat; cue 1 described shoulder pads the machine does not have). Every one was found by looking at the picture. Nine rows were held because the picture and the row disagree and the name cannot settle it (G0016 G0555 G0730 G0870 G1352 G1708 G1772 G3221 G3672).

## Decisions that are not obvious from the diff

- **Held, not dropped.** 79 of 708 stay in `scripts/data/library_batch_c_source.json` with a `hold` entry and an owner: 13 token (Batch D), 4 name_collision (G1368 G1489 G2567 G0474, Batch C2), 53 low_confidence and 9 picture (the founder's GIF review). The importer drops every source id and re-adds only the non-held ones, so a hold placed after a first import removes the row on the next run. Release steps: OI-437.
- **The shipped residual is not zero.** 529 of the 629 shipped rows have neither a picture record nor an identity record (130 of them with a doubting word in their source note). The triage criterion selected 122 reads (100 picture, 22 identity); 126 records exist (104 picture, 22 identity): three extra picture records come from the equipment audit and one, G1432, from the B-pass (it showed the same weight-stack machine as G1431). This is stated here and in OI-437 instead of being left implicit.
- **Tag table.** 629 rows, founder-approved (`approve all`, then nine rear-delt rows that gained `shoulder` from the table, three safe pool; four more already carried it). Two majority-token calls were shown to the founder and approved: eight lying or seated leg raises lost a majority `shoulder` (the originals are hanging or dragon-flag moves), and G0873 reverse crunch lost a majority `neck`. 29 safe-pool additions (4.6 percent untagged against 11.6 percent of the original 285-row library and 6.8 percent of the 914-row library); `kV14SafePool` 33 to 62 and asserted equal to `safe_pool_additions`.
- **Smith machine rows are `full_gym` only.** 39 new rows use the `smith machine` token and the tier table puts it in `full_gym` alone (`equipment_vocab.dart`); the comment there that said 0 rows use it is corrected.
- **Traded proofs (named so no one thinks they were kept).** Re-pointing the thin-day personas and the removal of the E121 Renegade Row and Hip Adduction Machine generator-level cases are not extra coverage: with the 914-row library no persona reaches E121 or the hip adduction machine any more (a reach search over 3 goals x 4 tiers x 3 levels x 4 day counts found no plan holding E121, and one over 36 tier, level and day combinations found none for the hip adduction machine), so the real-generator proof that an E121 wrist or shoulder tag removes it from a plan, and the equivalent for the hip adduction machine, are replaced by their `queryV4` level proofs. The generator-side cover that remains is golden R6 (ii) on the new rows and the sweep. Five thin-day personas were re-pointed (for example `shoulder` to `shoulder+wrist`, `knee+hip` to `shoulder+elbow`), each after a reach search and with its precondition asserted first.
- **Core text.** 14 core rows had their coaching cues rewritten from a reviewed file, not taken from the sheet.
- **Equipment audit.** 37 row-specific waivers in `scripts/equipment_audit_lib.dart` (each with its reason; 36 at the reviewed SHA, and the B-pass added G1432's when its name still said pull up on a machine row), 9 cue fixes made in the source file, 3 picture records; the audit id regex is `^[EGN]\d{2,4}$`.
- **Recorded exceptions.** Ten rows that break the family rule (`_meta.family_exception`) and three groups of identical cues that are correct (`_meta.identical_cues_ok`) each carry a reason in the source file; none is silent.

## Measured

Real `PlanGenerator.generateV4`, B1 flag OFF unless stated.

| Evidence | Before (285 rows) | After (914 rows) |
|---|---|---|
| Injury sweep, 7,200 runs: unsafe / unresolved / unperformable / duplicate / empty / one-exercise | 0 | 0 |
| Injury sweep thin days (pairs 3/5 days, pairs 4/6 days) | 2 and 6 scan days (OI-408) | 0 and 0 |
| Golden: personas that differ | n/a | 943 of 998 |
| Golden: distinct new ids picked / personas picking one / top pick | n/a | 50 / 939 / G0380 x589 (59.0 percent) |
| Scorecard mean overall | 86.1 | 81.1 (progression 100.0 to 62.9, see below) |
| Scorecard coverage / balance / volume / realism | 94.5 / 67.1 / 69.1 / 86.0 | 94.7 / 67.1 / 70.4 / 91.8 |
| Scorecard fallback picks | 2,864 | 1,679 |
| Core pool gate (B1 ON): hard counts | 0 | 0 |
| Core pool gate: emergencyAnyLevel, golden personas / multi-injury runs / refilled runs | 2 / 74 / 34 | 2 / 58 / 34 (OI-436) |
| B2 gate (hard zeros, 7 tests) | green | green; days over the user's minutes 3,965 to 4,292 of 33,204 |

**Solo timings, same machine, back to back:** golden 160 s to 242 s; core pool gate 18 s to 39 s (wall); scorecard gate 14 s to 25 s; B2 gate 135 s to 327 s; injury sweep 754 s as one file to 1,922 s as one file, which is why it is five files now: four tier tests each, plus two more in the singles file that pin the sweep's lists and read all five files for the tier loop (22 tests; worst test 3:06 solo, pairs 4/6 days, bodyweight). **CI partition (`ci_test_partition.dart`: sorted files, index modulo 4).** Under the first names (`injury_floor_sweep_*`) the pairs 4/6 block, the singles block and the B2 gate all landed on one shard (shard 4 before the origin/main merge, shard 1 after it, because main's new test files moved the indexes): 405 + 514 + 327 = 1,246 s solo, 20:46, against the 20-minute shard cap and the 18-minute stop rule. The B-pass renamed the five files `injury_sweep_a..e_*_test.dart`; the letter is a sort key, and the layout is now shard 1 repeat + B2 gate 679 s, shard 2 core gate + pairs + singles46 678 s, shard 3 thin-day + singles 547 s, shard 4 golden + pairs46 + scorecard 672 s (solo seconds of the heavy files only). Any file added before them in the sorted list re-deals them, and CI speed relative to solo is not measured, so the draft PR's four shard times still decide (stop rule: a shard over 18 minutes).

**Scorecard progression, 100.0 to 62.9.** The dimension sums `default_sets` of every picked row per phase and fails a family if the total ever falls: 75 of 213 families fail it, every one at phase 1 to 2, every one by exactly one set (for example `build_muscle|basic_gym|5|intermediate` 109 to 108), because the new rows carry `default_sets` 3 (mean 3.00 over 2,183 picks) against 3.57 for the older rows (17,363 picks). It is a binary test on a selection proxy, not the periodized set count. The baselines were regenerated, the scoring was not changed, and OI-435 holds the fix.

**Mutations (each applied to a saved copy, run, restored; `git diff` empty afterwards):**

| Mutation | Result |
|---|---|
| G3288 Korean Dips made pickable (bodyweight, tier 1, foundational, Beginner), G0380 loses its `shoulder` floor token, both at once | the five golden group tests redden; the (i) list names G3288 (calisthenics_skill), the (ii) list names G0380 |
| the 629 rows deleted from the library | golden R6 (iii) reddens ("no golden persona picked any new row"); core gate R9 reddens back to the three-id set; pairs[bodyweight] and pairs 4/6[bodyweight] redden with exactly the old 2 and 6 thin scan days |
| importer: ships a held row; ignores the table; edited cue or tag by hand; alias changed; missing table row | each reddens its own test in library_batch_c_rows_contract_test or the coverage test (control runs on clean inputs are green) |

## B-pass (two fresh reviewers, 14 findings, `docs/reviews/library-batch-c-bpass.md`)

One P1 and thirteen P2, all verified by the author from the files before acting. Fixed in this batch: **G1432** shipped a pull-up bar and a box for the same weight-stack assist machine G1431 shows (now `machines`, `full_gym`; a same-machine check pins the pair); the **tag builder** counted shipped new rows as "original" siblings (E-ids only now; a from-scratch build must reproduce every non-judgement row of the committed table); **G0786 Squat Jerk** gained `hip` and `knee` (founder's per-movement rule; the table was founder-approved, so the PR text says so); the **seed generator**'s applied-number refusal ignored an explicit `--out supabase/migrations`; seven rows shipped `difficulty_level "elite"` (now `advanced`, vocabulary check over all 914 rows); G0725 `is_bilateral`; the sweep now counts plan weeks with a missing day and the first sweep file pins its lists and reads all five files for the tier loop; golden R6 (iii) needs at least half the personas on a new id and `newRowPickViolations` has its own negative tests; the five sweep files were renamed `injury_sweep_a..e` to spread the heavy shard (see the timings paragraph); eight document numbers were corrected and the OI-404 closure now states it is on the aggregate.

**Mutations of the B-pass tests (each applied, run, restored):**

| Mutation | Result |
|---|---|
| builder sibling filter reverted to the whole library | the from-scratch test reddens with 506 differing rows (before the fix) |
| generator ledger guard reverted (only when `--out` is absent) | the four-spelling test reddens, and the run overwrote the applied migration 162 in the worktree, restored with `git checkout` |
| the repeat sweep file loops one tier instead of `kSweepTiers` | the loop-presence test reddens (expected 1 loop, found 0) |
| `newRowPickViolations` (i) condition and floor-token check neutered | 5 of the 10 tests in `library_new_row_pick_violations_test.dart` redden |
| G1432 back to a pull-up bar and a box; G0725 back to bilateral; one row at `elite` | each reddens its own check in `library_batch_c_rows_contract_test.dart` |

## Left open, each with an owner

OI-435 (scorer), OI-436 (B1 flip criteria), OI-437 (held rows and the unchecked residual), OI-438 (getFormCues `is_active`). OI-404 and OI-408 are closed by this batch. The live migration apply is the founder's explicit go.
