# Library Batch S1b-3: retire E053 Donkey Calf Raise into G1373 Bodyweight Standing Calf Raise, seed v24, one cloud migration (v5, converged after review #5)

> **For agentic workers:** inline (§4.12.7): one worktree (`generator-step1-s1b3`, base `01ed781c` = PR #237), one
> writer. Reviewers and the B-pass are fresh Sonnet subagents.

**Founder decisions.**
- In the exercise-plates brainstorm (OI-147), Donkey Calf Raise was ruled "not feasible generally" and leaves the library.
- The generator overhaul plan's step 1 was approved on 2026-11-08; closure 1B-9 (OI-147) is part of it.
- S1b-2's review #1 split E053 out into this batch.

**Goal.**
- E053 leaves the bundled library and every install, and is deactivated in the cloud.
- Its name still resolves, to G1373.
- Every user keeps a bodyweight calf isolation row.
- Nothing else changes, apart from the derived counts and media entries listed below.

**Blast radius: platform** (library asset, `seed_service.dart`, a seed migration). **Not ship-dark:** the OFF `queryV4` pool loses a row. G1373 is already a core-list row and E053 was not (`core_levels: []`), so the ON core-list pool is unchanged.

## Facts (verified 2026-11-10 at `01ed781c` by review #1; re-verified in Task 0)

1. **E053 vs G1373.**
   - Both rows are equal on: category legs, `movement_pattern` [knee_dominant], `primary_muscles` and `target_focus` [Calves], `equipment_needed` [bodyweight], all four tiers, all three levels, `variant_family` calf_raise, the ankle injury tag, `is_foundational` false, and active.
   - They differ on:

     | field | G1373 | E053 |
     |---|---|---|
     | `exercise_type` | [calisthenics, isolation] | [isolation] |
     | `priority_tier` | 2 | 3 |
     | `cns_demand` | 1 | 2 |
     | default prescription | 3x15-20, 60 s | 4x20-25, 45 s |
     | `core_levels` | b, i, a | [] |

   - Other bodyweight calf raises in the bundle: G0742, G1490 (all levels) and G1387 (Intermediate, Advanced). OI-147's original worry, that no bodyweight calf isolation row would remain, no longer applies.
2. **The `merged_ids` path is generic in code.** Each layer works from the data, not from fixed ids:
   - The client prune is `SeedService.retiredLibraryIds` and `pruneRetired` (`seed_service.dart:260-283`).
   - The cloud retire UPDATEs come from `seed_exercise_library.js:226-229`.
   - `retiredPairs` (`:286-287`) feeds only the header text.
   - `merged_ids` is NOT a cloud column. `name_aliases` IS one (`backups/live_schema_columns.json`).
   - `kRetiredLibraryIdsNoTwin` and the sheet-bound removals file are not touched.
3. **Readers of a pruned id degrade; nothing crashes.**
   - `train_provider.dart:392,426` and `session_estimate.dart:45` look up by id, then fall back to name search.
   - `exercise_repository.dart:86,114` searches by name and `name_aliases`.
   - The swap, coach tool and planner readers return null or an unresolved name.
   - Exercise-log keys are name-hashed, so past logs keep working.
   - **So `name_aliases: ["Donkey Calf Raise"]` on G1373 is load-bearing.** Plan rows and templates that hold the old name resolve to G1373's row and cues through it. Its readers include `exercise_swap_sheet.dart:124` and `exercise_picker_sheet.dart:88`.
4. **Media.**
   - **Table:** `scripts/data/library_media_v16.json:14466` maps E053 to `0284-donkey-calf-raise`.
   - **Old-rows input:** `docs/audit/library-old-rows-media-input.json:240` lists it. Check P5 in `test/helpers/library_old_rows_input_checks.dart` requires every entry there to be a library row.
   - **Hash pin:** the input's sha256 is pinned in the table's `_meta.old_rows.sha256`, and `library_media_table_test.dart:453-459` recomputes it.
   - **Prune:** `build_library_media_v16.js --prune-only` (`:181-193`) drops the row and updates `old_rows.entries`, but keeps `old_rows.sha256`. Re-hashing needs the full build, and the Wardroom folder is not on this VPS.
   - **Precedent:** C2a (`43fbb074`) removed old-rows entries and updated that one pinned sha256 line in the same commit. The picks and equipment-check records are supersets and stay as they are (P1, P3, P7).
   - **Still:** `assets/exercise_stills/0284-donkey-calf-raise.webp` is bundled through the `pubspec.yaml:133` directory entry, and `exercise_stills_bundle_test` requires the folder to equal the table's `files` keys. D5 deletes both the still and the files entry. No earlier batch pruned a mapped row: C2a's removals were never in the table.
5. **The cloud seed test knows only the batch labels `C2[a-z]|S1b-2`** (`exercise_library_cloud_seeded_test.dart:130-131`, rollback dispatch at `:186-189`). It pins the retired-pair count at 7 (around `:323`).
6. **The generator's rollback can express only three things:**
   - a column restore per kept-row record (`changed[]`);
   - a reactivation, only for removals-file entries tagged with this batch (`reactivateLine`, `:262`);
   - a deactivation of new rows.

   It has no way to reactivate a row retired through `merged_ids`. Its comment (`:218-224`) and the migration header say every retire UPDATE is "idempotent, already inactive". That is false for E053, which is active in prod today (871 active).

## Decisions (mine unless marked founder)

- **D1: G1373 is the kept row.**
  - Why: same muscle and pattern, same tiers and levels, already in the core-list pool. Users keep a bodyweight calf isolation row, and the old name resolves through the alias.
  - It is the nearest bodyweight version, not the same movement: the donkey adds a hip hinge.
  - The no-twin path is not used. It would leave no alias, so plan rows holding "Donkey Calf Raise" would lose their row and cues.
- **D2: G1373 gains `merged_ids: ["E053"]` and `name_aliases: ["Donkey Calf Raise"]`.** Both are load-bearing (Fact 3).
- **D3: seed v24.** A v23 install prunes E053 and rewrites G1373; every other row is unchanged.
  - The v24 comment block follows the style of v21-v23.
  - The upgrade test restates the v23 digest as a constant, never read from git (CI checks out shallow).
- **D4: generator and migration.** Migration 175 is minted with `sh scripts/mint_migration.sh reseed_exercise_library`.
  - `BATCH`: label `library v24, Batch S1b-3`, `batchTag 's1b3'` (matches no removals entry), `newRowIds []`, `previousMigration '174'`.
  - One kept-row record: `scripts/data/library_s1b3_name_aliases.json` = `{G1373, column name_aliases, before null, after ["Donkey Calf Raise"]}`. It is checked against migration 174's tuple by the existing previous-tuples check.
  - **New field `BATCH.reactivateOnRollback: ['E053']`.**
    - It adds `UPDATE exercise_library SET is_active = true WHERE id IN ('<E053 uuid>');` to the inline rollback and to the commented block.
    - The generator refuses an id that the bundle still ships, and an id that no kept row lists in `merged_ids`.
    - The header says E053's cues were overwritten by G1373's and that re-applying migration 174 restores them, because its upsert carries E053's own tuple. Task 0 confirms that 174's tuple for E053 holds its cues.
    - The retire comment and the header's "idempotent, already inactive" sentence become true again by naming the pair this batch deactivates for the first time. The text is computed from the field, not hand-written.
  - **Test:** `exercise_library_cloud_seeded_test.dart` accepts label `S1b-3` and gains `_rollbackViolationsS1b3`:
    - exactly one name_aliases restore (G1373 to NULL);
    - exactly one reactivation line, naming E053's cloud id from `_cloudId`;
    - no new-row deactivation line.
  - **Header text is computed (review #2 P2).** When `reactivateOnRollback` is non-empty, these sentences are rewritten from the field:
    - `ownsNoRow` and `rollbackRowSentence`;
    - the Intent line (it becomes "8 pairs; E053 deactivated for the first time");
    - the Destructive line;
    - the `:218-224` comment;
    - the inline "Rollback strategy" line, which must also carry the reactivation.

    The test asserts that the old "adds no row" wording is absent.
  - **Inline cue restore (review #2 P2; method corrected by review #3 P2).** The reactivation line is `SET is_active = true, coaching_cues = <literal>, common_mistakes = <literal>`.
    - `previousTuples` stores whole tuple lines and parses no column, so the generator adds a quote-aware scan of E053's 174 tuple that respects `''` escapes.
    - The scan takes the 5th and 6th `ARRAY[...]::text[]` literals and splices them into the rollback line verbatim, never decoded and re-encoded.
    - It refuses unless it finds exactly 6 array literals, or when the tuple is missing. Measured on `174_reseed_exercise_library.sql:83` with a quote-aware scan, review #4: primary, secondary, equipment, suitable_for, coaching_cues, common_mistakes. `name_aliases` is a bare `NULL` through `sqlTextArrayOrNull`.
    - It also strips one trailing `,` or `;`, then requires the tail after the 6th literal to end `NULL, now())`. Line 83 ends `),` because E053 is mid-slice, and a test runs the check on the real 174 with that comma (review #5 P3).
    - The scan reads the file as UTF-8 (cue 1 holds `°`), treats `ARRAY[]::text[]` as a literal, and ignores `[`, `]` and `ARRAY` inside quoted strings.
    - Tests: the real 174 passes. Refused tuple mutants: a 7th array added; `NULL` turned into an array; one array dropped. A cue holding `''` round-trips byte-exact.
    - Re-applying 174 stays as the documented second route.
  - The pair count goes from 7 to 8, with the header comment updated.
  - New refusal tests for the field: the bundle still ships the id; no kept row lists it.
- **D5: media. The files entry and the still go too; the table keeps "every file active and referenced".**
  - Review #2 measured two things:
    - `library_media_table_test.dart:114-115` requires the files keys to equal the rows values, with every file `active`, and all 758 committed files are active.
    - C2a's 24 input removals were never in the table, so C2a had no mapped row to prune.
  - An `unmapped` 0284 would therefore turn the table test red, and loosening that test is refused (repoint, never loosen).
  - Change: `build_library_media_v16.js --prune-only` gains `--drop-unmapped`, which DROPS a file entry whose slug lost its LAST row in this run, instead of flipping it to `unmapped`. That means a slug a pruned row referenced and no surviving row references. A file already `unmapped` before the run is kept, so held-row provenance is never deleted (review #3 P2/P3).
    - `--drop-unmapped` refuses without `--prune-only`.
    - It never drops a `taken_down` slug.
    - It refuses when a dropped slug's still is still present in the stills directory, so the paired deletion cannot be forgotten.
      - The directory comes from a `--stills-dir` flag, defaulting to the path `exercise_stills_bundle_test` reads, so tests use a temp dir.
      - The refusal fires only when the dropped set is non-empty, so a later `--check` with an unrelated still never trips it (review #4 P3).
      - A test covers both orders.
    - It is rule-21 mutation-proven in `test/scripts/library_media_builder_test.dart`, with four mutants:
      - the flag ignored (the file stays `unmapped`);
      - a taken-down slug dropped;
      - a pre-existing `unmapped` file dropped;
      - the still-present refusal disabled.
    - The R13 hold recipe (keep `unmapped`) is unchanged.
  - `assets/exercise_stills/0284-donkey-calf-raise.webp` is deleted, because `exercise_stills_bundle_test` requires the folder to equal the files keys. The private-bucket object stays: nothing deletes storage, and nothing maps it.
  - Order, following the "Hold a mapped row" recipe in `docs/operations/EXERCISE_MEDIA.md:105-112`, because the importer stops on a table row that is not in the library:
    1. Delete the E053 entry from the old-rows input.
    2. Run `importer --media none --library <tmp>`.
    3. Delete `assets/exercise_stills/0284-donkey-calf-raise.webp`. This must happen before step 4, because step 4's still-present refusal would fire on it (review #5 P2).
    4. Run `builder --prune-only --drop-unmapped --library <tmp> --write`.
    5. Set `_meta.old_rows.sha256` to `sha256sum` of the input. The test hashes the raw bytes, with no CR, and recomputes the value.
    6. Run the real importer, then `importer --check` and `builder --prune-only --drop-unmapped --check`.
  - Media counts (review #3 P2), recomputed from the table and never hand-subtracted:
    - `docs/operations/EXERCISE_MEDIA.md` lines 15 (759 → 758 mapped, 138 → 137 old rows), 30 (758 → 757), 49 (files and total bytes recomputed), 72 (758 → 757), 129 (re-read) and 175 (137 / 31).
    - Add a "known orphan objects" line for the 0284 bucket object.
    - `docs/reference/exercise-library.md:17` (759 → 758, 138 → 137).
    - The `test/contracts/exercise_stills_bundle_test.dart:6` comment (758 → 757).
    - Task 0 runs `grep -rnE "\b(759|758|311,867|138)\b" docs/ test/` and lists every hit.
    - The 106 rows with a drawing are unchanged.
- **D10: blast radius for the two new record files (review #3 P2; test groups 1g and 1h copy 1d-1f; both files exist before the test runs, as its positive control).** `scripts/data/library_s1b3_merges.json` and `scripts/data/library_s1b3_name_aliases.json` get `account` rules in `docs/blast_radius.yaml`, next to the other record rules (`:538-544`), with glob constants and pins in `test/contracts/blast_radius_library_data_account_test.dart` (`:34-40`, `:150-210`). Otherwise they fall under the `scripts/**` feature catch-all, and a file that decides which rows leave every install would be under-tiered.
- **D9: the importer gets a MERGE STAGE (review #2 P0).**
  - The shipped library must equal a fresh `scripts/add_library_batch_c_v15.js` import byte for byte (`library_batch_c_rows_contract_test.dart:580`, with mutants at `:593` and `:607`).
  - Today that importer:
    - keeps every base row that is not in the source or the removals file (`:371-377`);
    - builds G1373 from an allow-list with no `merged_ids`;
    - writes `name_aliases` only from a removals entry's `alias_to`.
  - New record `scripts/data/library_s1b3_merges.json` = `{rows: [{id: "E053", name: "Donkey Calf Raise", into: "G1373"}]}`, read by a merge stage.
  - The stage runs on the final rows, after every other stage and before the media stage:
    - It drops the row `id` (a kept base row, never a source row).
    - It appends `id` to `into`'s `merged_ids` and `name` to `into`'s `name_aliases`, with no duplicates and existing order kept.
    - On a row that lacks them, the two keys are inserted after every non-media key, so the media keys stay last. Task 0 confirms the position, and the importer test asserts it.
  - **The record is authoritative (review #3 P1).** G1373 is a SOURCE row: `buildRow` (`:143-167`) rebuilds it from the allow-list on every run, so the stage can never read "already merged" from it. Like `applyAliases` (`:285-298`), the stage therefore:
    - always appends `id` to `into`'s `merged_ids` and `name` to `into`'s `name_aliases`, with no duplicates and existing order kept;
    - drops the row only when it is present;
    - checks `name` against the row's name only when the row is present.

    The second run and `--check` are byte-identical by construction.
  - **Order inside the stage (review #4 P2):**
    1. Drop the row.
    2. Append to `merged_ids` and `name_aliases`. `name_aliases` comes first and `merged_ids` second, the order E016 uses; both go after every non-media key. Task 1's hand edit uses the same order.
    3. Check each alias against the POST-drop name set, excluding `into`'s own existing aliases.

    So run 1 (E053 present) and run 2 (absent) decide the same way. A test runs the stage from a base library that still holds E053, then runs it a second time, and asserts both succeed with identical bytes.
  - Refusals, each naming the id:
    - `id` is a source row;
    - `into` is missing from the final rows;
    - `name` differs from the present row's name;
    - the alias equals a row name of the new library;
    - a record row lacks `merged_in`.
  - **The generator's read of the merges file (review #4 P3):**
    - A missing file is a hard stop, like the removals file at `:236`.
    - No row for this batch gives `reactivateLine = null` (the `IN ()` guard at `:262`).
    - `retiredPairs` goes from 7 to 8 by itself, because it counts `merged_ids`.
  - **Each record row carries `merged_in: "s1b3"` (review #3 P2).** The generator derives `reactivateOnRollback` from the record rows whose `merged_in` equals `BATCH.batchTag`, like `ownRemoved`. There is no hand-typed second list, so a later batch's rollback never reactivates E053. The D4 refusals stay: the bundle still ships the id; no kept row lists it in `merged_ids`.
  - **Tests:**
    - Importer tests (`test/scripts/library_media_importer_test.dart`): `_Tree` gains `_s1b3MergesRel` and a `merges` getter, copied in its constructor. Without it, every temp-tree byte-identity test goes red (`:44`; the removals copies at `:379`, `:488`, `:577`, `:657`). Task 0 greps every other importer-invoking test for the same need: `library_s1_core_levels_test`, `library_e230_retag_test`, `library_seed_v15_upgrade_behavioral_test`.
    - New stage tests: `--check` on the shipped file; a second run byte-identical; one test per refusal.
    - A test that fails if the stage reads the freshly built `into` to decide anything: the record is edited to name a second alias, and the run must append it.
  - **Mutants:**
    - the stage skipped (`--check` red);
    - the drop skipped (E053 ships);
    - the alias not appended;
    - the source-row refusal disabled;
    - the stage made conditional on `into` already listing the id (second run red).
  - **`library_batch_c_rows_contract_test.dart` `_keyViolations` (`:73-95`, review #3 P1).**
    - `_aliasTargets()` (`:46-49`) also takes the `into` ids of the merges record.
    - `merged_ids` becomes an allowed key ONLY on those ids, as a non-empty list of E-ids.
    - `_keyViolations` sees only the G/N rows (`:31-34`, `:330`), so its "absent from the bundle" check takes the full library's ids as a new parameter with a default. The single-row `[aliasless]` mutation keeps working (review #4 P2).
    - Extra mutants: `merged_ids` naming a live id; `merged_ids: []` on G1373.
    - Mutants: `name_aliases` on a non-target G row, and `merged_ids` on a non-target G row. Both must stay red, like the existing `:364-366` mutation.
  - **Ordering (review #3 P3).** Task 1's red-first step starts with a HAND edit of the library, so the tests go red against code. The final library is then the importer's output after D5 steps 1-5. A real importer run while the table still maps E053 throws (`applyMedia` `:188-191`).
  - The importer's summary line counts rows after the merge stage. Today `kept.length` at `:423` would still count E053.
  - For the importer, a missing record means the stage is skipped, with a log line, like the other stages. The generator's missing-file rule is the hard stop above.
- **D6: frozen fixtures, by name (review #2 P3).** A row's leaving the library is the one change a frozen "before" fixture cannot absorb, which is why each removal edits it on purpose.
  - Delete E053 from `test/fixtures/exercise_library_v12_row_hashes.json` (around line 2140), as C2a deleted its 50 entries. `exercise_library_frozen_reference_test`'s length expectation counts this removal by name.
  - `test/fixtures/library_core_levels_before_s1a.json` stays intact; it is FROZEN. `library_s1_core_levels_test.dart:89` gains a named `_removedSince = {'E053'}` exception, and asserts that each named id is absent from the bundle, so the exception is not vacuous.
  - `exercise_library_frozen_reference_test.dart`: `285 - c2Removed` becomes `285 - c2Removed - 1` with E053 named. The test asserts E053 is absent from both the fixture and the bundle; a bare `- 1` would pass for any removal.
  - `test/fixtures/library_c2_base_depth.json` is a base fixture replayed against itself and stays. Task 4 runs `library_depth_rule_test` to confirm.
- **D7: `baseline_plans.md` and `exercise_target_focus_review.csv`** are dated artefacts of `generate_baseline.dart` that nothing reads. They stay unchanged, and the plan says so.
- **D8: generator measurement** (Task 4):
  - Re-record golden hashes OFF and ON, and run a counterfactual with E053 restored, so that every changed key is attributed to it.
  - Record the scorecard bodyweight fallback count against its ceiling (OI-147's risk).
  - Run the same-movement, core-list and scorecard gates.

## Red-test list (review #1, to be diffed against Task 0's grep)
- `exercise_library_schema_contract_test.dart` (~169-170): 871 → 870.
- `exercise_library_merge_contract_test.dart`:
  - the "871 rows … 7 retired" test;
  - `_merges` gains `'E053': ('Donkey Calf Raise', 'G1373')`, which brings the alias, single-holder and no-live-id checks.
- `exercise_plate_library_data_test.dart`:
  - `:39-44` inverts (E053 gone; 870);
  - `:57`: 722 rows without artwork → 721.
- `exercise_plate_resolver_test.dart:80`: 722 → 721.
- `library_seed_prune_behavioral_test.dart:41-42`: the set gains E053.
- `exercise_library_cloud_seeded_test.dart`: see D4.
- `exercise_library_frozen_reference_test.dart`, `library_s1_core_levels_test.dart`: see D6.
- `library_media_table_test.dart`: see D5.
- Check: no v19 to v23 upgrade test asserts that E053 stays in the box.
- **The seed version bump (review #2 P1):** 23 becomes 24 in `library_seed_v16_upgrade_behavioral_test.dart:31` and in the v18 to v23 tests (`v18:79`, `v19:83`, `v20:85,97,107,110`, `v21:84,93,102,105`, `v22:83,89,92`, `v23:104,110,114`). S1b-2 (`ca87baba`) did the same for v16 to v22.
- **The v23 digest pin (`library_seed_v23_upgrade_behavioral_test.dart:74-81`, review #2 P1).**
  - The test rebuilds the v23 bundle and keeps its v22 digest `7a37c26c…`. To rebuild, it:
    1. re-inserts E053 at index 51 (between E052 and E054) from a new fixture, `test/fixtures/library_e053_row_v23.json`, a verbatim copy of the v23 row taken from `01ed781c` and restated, never read from git;
    2. strips G1373's `merged_ids` and `name_aliases`;
    3. then removes the nine N rows and reverts E010 / E045, as it does today.
  - So the chain v22 → v23 → v24 stays byte-proven. The v24 test pins the v23 digest by the same method.
- **Cloud seed tests (review #2 P1).**
  - `exercise_library_cloud_tuples_match_test.dart`: the sandbox copies `174_reseed_exercise_library.sql` (`:76-79`), and `containsAll` (`:70`) adds `library_s1b3_merges.json` and `library_s1b3_name_aliases.json`.
  - `exercise_library_cloud_seeded_test.dart`:
    - The S1b-2 groups (`~:520-720`) keep their checks, re-pointed at the applied file 174, as S1b-2 re-pointed C2c at 173.
    - The sandbox guard test is rewritten for S1b-3: the record files, previous migration 174, the `S1b-3` label, and the `batchTag` replace target.


## Tasks

### Task 0: Verify and baseline (scratch, clean tree)
1. Re-verify the facts.
2. Run `grep -rn "871\|722\|E053\|Donkey\|merged_ids" test/` and diff the result against the red-test list.
3. Confirm 174's tuple for E053 (its cues), and that the previous-tuples check accepts the G1373 `before: null` record.
4. Take OFF and ON golden baselines.

### Task 1: Data (RED tests first)
1. Write the red-test list's expectations, the new merge entry and the fixture edits first, and watch them fail.
2. Then make the library edit: remove E053; G1373 gets `merged_ids` and `name_aliases`.

Mutations:
- E053 back in the bundle: the bundle and count tests redden. The prune does not, because its "shipped id is never pruned" guard keeps the row.
- Alias removed: the merge-contract alias test reddens.

### Task 2: Seed v24 and upgrade test
New file `library_seed_v24_upgrade_behavioral_test.dart`:
- A v23 box holding E053 loses E053.
- G1373 is written as bundled.
- A community row named "Donkey Calf Raise" (UUID key) is untouched.
- Every other row is unchanged, via the v23 digest constant.
- Mirror: a box already at v24 is not rewritten.

Mutations:
- Version back to 23.
- `merged_ids` dropped from G1373: E053 survives the upgrade.

### Task 3: Media and importer merge stage (D5, D9; build the stage and its tests first, then run the D5 order)

### Task 4: Measure and attribute (D8)

### Task 5: Generator, migration, gate loop, reviews
1. Implement D4. Mutate `reactivateOnRollback` (removed, or the refusal disabled) and see the tests redden.
2. Mint migration 175 and generate it.
3. Rehearse it in local docker (`supabase/postgres:17.6.1.084`, with 174 loaded first) inside BEGIN … ROLLBACK, then apply. Expect 934 / 870 / 64, and E053 inactive with G1373's cues.
4. Run the inline rollback and confirm E053 is active again and G1373's alias is NULL.
5. Run the full gate loop (§4.12.8), the B-pass, and write the plan-review record.

### Task 6: Live step (the founder's go on the exact file)
1. Read prod read-only first: expect 934 / 871 / 63.
2. Apply only on the founder's explicit go.
3. Read back 934 / 870 / 64, E053 inactive, G1373 `name_aliases`, and the content md5 equal to the rehearsal.
4. Ledger the apply in `backups/applied_migrations.json`.

### Task 7: Close-out (touch list)
- **Diagnose doc:** a new one (§4.4 rule 22).
- **SoT registry:** `docs/sot_registry.yaml`, the exercise_library concept (8 retirements). Recompute every cited `line_range` for `seed_service.dart`, the generator and the importer from its anchors, in each commit (review #2 P3).
- **Closure ledgers:**
  - `generator-step1a.closure.yaml` 1B-9 and `library-batch-s1b2.closure.yaml` S1B2-E053 go to `closed_in_commit`;
  - a new `library-batch-s1b3.closure.yaml`.
- **Other docs:**
  - `docs/ship_dark_pending_review.yaml:366,373`;
  - `docs/operations/EXERCISE_MEDIA.md`.
- **OI-147:** close it and archive it to `closed_issues.md` by append, then check the diff-stat deletions.
- **Landing:** commit, PR, `land_pr.sh`, retire the worktree, update the board, write the memory entry.

## Results (measured 2026-11-10 on the final tree)

- **Data.**
  - The importer reproduces the hand-edited library byte for byte: the first run printed `file unchanged`, then `--check OK`.
  - The importer test run that starts from the pre-merge library prints `1 merged away`.
  - The library holds 870 rows; G1373 carries `name_aliases: [Donkey Calf Raise]` and `merged_ids: [E053]`.
- **Media.** The table holds 758 rows on 757 files, all active. The `0284` entry and still are gone, and `old_rows.entries` is 137. Recomputed totals: 311,412,724 bytes (311,867,164 − 454,440), largest file 999,800.
- **Golden (OFF).**
  - 76 of 999 keys change: 51 bodyweight, 16 home_dumbbells, and 9 injury personas.
  - Counterfactual A, the v23 library restored (E053 back, G1373 without the keys): 0 keys differ from the committed fixture, so every change is this batch's library edit.
  - Counterfactual B, E053 removed but G1373 without its alias and `merged_ids`: 0 keys differ from the batch, so the alias and `merged_ids` have no generator effect. All 76 keys are E053 leaving the bodyweight and home calf pools.
  - The ON core-list pool is unaffected (E053 `core_levels: []`).
- **Seed.** The Dart rebuild of the v23 bundle hashes to `d858d26b…`, the digest computed independently from git `01ed781c`. The same Python method reproduces the v22 pin `7a37c26c…`.
- **Found in the build.** None of the five review rounds caught these:
  - The injury builder's original-sibling pool shrank by E053, so the founder-approved table's "all 4 same-family originals" calf reasons no longer rebuilt. E053 is now a FROZEN original, mirrored against the base fixture.
  - `library_seed_v15_upgrade_behavioral_test` counted the 285 original rows minus the C2a removals; it now subtracts E053 by name.
- **Cloud (local rehearsal, `supabase/postgres:17.6.1.084`).**
  - The seed migrations 074, 125, 162, 164, 167, 171, 173 and 174 were replayed, giving 934 / 871 / 63 and md5 `fd91c822…`. That equals prod, read read-only on 2026-11-10.
  - 175 (sha256 `3ff320a2…`, 515,593 bytes), applied inside BEGIN … ROLLBACK:
    - 934 / 870 / 64;
    - exactly 2 rows change: E053 is inactive with G1373's cues, and G1373 has the alias;
    - 0 new rows;
    - md5 `3170849a6b1e5b9b6608a27ea2c7b501`, and a second apply gives the same md5.
  - The inline rollback returns 934 / 871 / 63 with 0 rows different from the pre-state.
- **Applied live 2026-11-10** after the founder go on the exact file: prod re-read just before at 934 / 871 / 63 (md5 `fd91c822…`); HTTP 201; read-back 934 / 870 / 64, md5 `3170849a6b1e5b9b6608a27ea2c7b501`, equal to the rehearsal. Ledger: `backups/applied_migrations.json` entry 175.

## Review log
- **Review #1 (2026-11-10, fresh Sonnet seat): not converged. No P0; 5 P1, 3 P2, 2 P3.**
  - P1 fixes:
    - the media re-pin route (D5);
    - frozen fixtures that do change (D6);
    - the cloud-seed test's batch label and shape (D4);
    - the generator's rollback and header for an E053 that is live and active (D4, `reactivateOnRollback`);
    - the full red-test list.
  - P2: the golden and fallback scope (D8), the touch list (Task 7), the seed comment and upgrade-test detail (D3, Task 2).
  - P3: D1's reasoning restated; a line-number fix.
  - The reviewer's media option (b), a full build that needs the Wardroom folder, was replaced by C2a's precedent of a test-verified hash update.
- **Review #2 (2026-11-10, fresh Sonnet seat): not converged. 1 P0, 4 P1, 3 P2, 2 P3.**
  - P0: the library edit is not reproducible by the importer, so `importer --check` goes red. Fixed by the D9 merge stage.
  - P1s:
    - the `unmapped` 0284 contradicts the media table test (D5: `--drop-unmapped`, still deleted);
    - the seven seed-version tests;
    - the v23 digest pin (E053 fixture rebuild);
    - the cloud test sandboxes and the S1b-2 groups re-pointed at 174.
  - P2s: header text computed; inline cue restore; the EXERCISE_MEDIA.md counts.
  - P3s: frozen tests by name; registry ranges.
  - Verified OK by the seat:
    - the previous-tuples check accepts `before: null` (174's G1373 tuple ends `NULL`);
    - 174 carries E053's own cues, and the upsert covers them;
    - `getFormCues` ignores `name_aliases`;
    - the alias rules;
    - Task 6's counts.
  - D9 is new mechanism, so review #3 runs on v3.
- **Review #3 (2026-11-10, fresh Sonnet seat): not converged. No P0; 3 P1, 5 P2, 3 P3.**
  - P1s:
    - D9's rule for an already-merged row read the freshly built source row, so the stage would refuse on every re-run. The record is now authoritative.
    - `_keyViolations` would reject G1373's `name_aliases` and `merged_ids`.
    - The importer harness did not copy the new record.
  - P2s:
    - a `merged_in` tag, so `reactivateOnRollback` is derived;
    - the cue-restore method (quote-aware literal splice);
    - the media counts;
    - Fact 4's contradiction;
    - blast-radius rules (D10).
  - P3s: `--drop-unmapped` narrowed to slugs that lost their last row in this run, plus a still-present refusal; Task 1/3 ordering; the summary count.
  - Verified clean by the seat:
    - no library row references E053 in any link field;
    - no plates impact;
    - the v23 digest rebuild reproduces key order;
    - 0284 is referenced only in the table, the input and one closure line;
    - the only library-reading gate is `check_equipment_audit.dart`, with no count dependence;
    - the red-test list matches its grep.
  - The seat advised a targeted re-check of D9 only, so review #4 checks D9, D10 and the corrected D4/D5 mechanics.
- **Review #4 (2026-11-10, targeted, fresh Sonnet seat): not converged. No P0; 1 P1, 2 P2, several P3.**
  - P1: the cue scan expected 7 array literals, but E053's 174 tuple holds 6, so the refusal would have fired on the real file. I measured it with a quote-aware scan. Fixed: exactly 6, plus a tail check and three mutants.
  - P2s:
    - the merge stage's drop-then-check order is now stated, with a run-1/run-2 test;
    - `_keyViolations` needs the library ids as a parameter.
  - P3s: key order; `--stills-dir`; the refusal only on a non-empty dropped set; the generator's missing-file stop; blast-radius test groups 1g/1h.
  - Verified OK:
    - D9 is byte-stable on run 1, run 2 and `--check`;
    - the lost-slug set in D5 is computable in `buildPrune`, and `--check` is stable;
    - D10's rules classify the files first-match above `scripts/**`;
    - deriving `reactivateOnRollback` is sound.
  - The only P1 was a count, so review #5 checks just the v5 deltas.
- **Review #5 (2026-11-10, delta check, fresh Sonnet seat): CONVERGED. No P0 or P1; 1 P2, 3 P3, all applied.**
  - P2: in the D5 order, the still is deleted (step 3) before the builder runs (step 4).
  - P3s:
    - the tail check strips the trailing `,` or `;`;
    - "Task 0 confirms" the key position;
    - the duplicate D9 tests and mutant block are removed, and the importer's missing-file rule is labelled.
  - Verified:
    - 857 tuples in 174 hold 6 arrays and 13 hold 7 (rows with aliases), so the 6-array refusal is correct for E053 and fails closed elsewhere;
    - the key order matches the 7 existing `merged_ids` rows and G1368 / G3470;
    - the `_keyViolations` parameter is feasible at every call site;
    - the `--stills-dir` default follows the builder's `REPO` convention.
