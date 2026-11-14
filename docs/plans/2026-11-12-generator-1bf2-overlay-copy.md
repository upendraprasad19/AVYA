# Generator Unit 1B-F2: copy the core-list overlay labels into the library's own fields (OI-495)

Plan v4, 2026-11-12 (v4: review round 3 folded in: the S1b-3 cloud tests read the applied 175 (the S1b-2
precedent), the tuples test compares the newest migration only, blast-radius rules, the seed tests' box rows; v2: review round 1 folded in: E274's four pins, the cloud seed generator's batch block and
its tests, the C2 generator left alone, the v13 table left alone, the overlay key positions, the docs pins. v3: review
round 2: the generator's rollback emitter flattens a TEXT column, the older cloud tests keep their S1b-3 coverage
through a mutated BATCH, the rollback wording for installed devices; section 6). Branch `generator-step1-1bf2` (worktree `.claude/worktrees/generator-step1-1bf2`, from main
67b536e4, after Unit 1B-R). Part of generator step 1 (parent `docs/plans/2026-11-08-generator-step1-core-list.md` items
1B-7 / 1B-11; Unit 1B-F's plan section 11, `docs/plans/2026-11-10-generator-1bf-flip.md:1473`, is this unit's first
draft and its pins table; this plan re-measures every row of it on today's main). Founder basis: B1 Ruling 4
(`docs/plans/2026-10-22-library-core-list-pool.md:83`), which assigned the copy to the flip; 1B-F split it out under
§4.12.1. No new founder decision is needed except the live migration go (§4.3). Tier L (library data + schema-free
cloud reseed + plan engine reader), blast radius `account` (library data) with a cloud migration; full x2 review,
B-pass. Execution mode: inline, one worktree (§4.12.7). Pre-launch (testing accounts only).

## 1. Measured state (main 67b536e4)

**The overlays.** 27 rows carry an overlay key the core-list picker reads instead of the row's own field
(`core_list_selector.dart:184, 225, 227`: `slot_focus ?? target_focus`, `slot_pattern ?? movement_pattern`):

- `slot_pattern` on 13 rows: E015 Front Raise (vertical_push -> shoulder_isolation), E046 Nordic Curl (hip_dominant ->
  knee_dominant), E048 Glute Bridge (hip_isolation -> hip_dominant), E050 Sumo Deadlift (knee_dominant ->
  hip_dominant), E064 Rowing Machine ([cardio, horizontal_pull] -> [cardio]), E127 Reverse Hyper (hip_isolation ->
  hip_dominant), E198 Lunge with Twist (core -> knee_dominant), E222 Kas Glute Bridge (hip_isolation -> hip_dominant),
  E274 Prone T Raise, E276 Standing Towel Pull Apart, E277 Prone W Raise (horizontal_pull -> shoulder_isolation), E292
  Sliding Leg Curl (hip_dominant -> knee_dominant), N20 Dumbbell Sumo Deadlift (knee_dominant -> hip_dominant).
- `slot_focus` on 19 rows: E064, E090, E114, E118, E122, E133, E172, E175, E186, E198, E264, E272, E273, E274, E275,
  E276, E277, E289, E290 (values in Task 1's record). 5 rows carry both; 27 distinct rows; 26 are kept E-rows, N20 is a
  Batch C source row.
- Writers today: the v13 table `scripts/data/library_core_fields_v13.json` (12 `slot_pattern`, 19 `slot_focus`) applied
  in place by `scripts/add_library_core_fields_v13.js`; the Batch C source `scripts/data/library_batch_c_source.json`
  (N20, ~:57372) passed through by the importer's `LINK` list (`scripts/add_library_batch_c_v15.js:104`); the C2
  removals generator copies the key (`scripts/library_batch_c2_removals_gen.js:232`).

**Readers of the target fields (they see new values after the copy).**

| reader | field | effect |
|---|---|---|
| `CoreListSelector.rankedPool` / `namesMuscle` (`core_list_selector.dart:184, 225, 227`) | both, via the overlay today | none: it reads the same values from the target fields |
| `ExerciseRepository.queryV4` (`exercise_repository.dart:312, 316, 321`), whose only caller is the thin-day top-up (`exercise_selector.dart:662`, injured users) | both | the top-up's same-pattern rung now sees the 27 rows under the picker's labels (measured below) |
| `ExerciseDisplay.formatMuscleLabel` (`exercise_display.dart:11-26`) | `target_focus` | the muscle label changes on the 19 rows for intermediate and advanced users (beginners see the category) |
| `swap_service.dart:576` | `target_focus` | copies the incoming row's label into the swapped plan row (display only) |
| `ai_snapshot_builder.dart:614`, `injury_swap_planner.dart:196` | `target_focus` | none: the snapshot reads `category` first; the planner reads it only when it is a String (library rows hold a List) |
| cloud `exercise_library.movement_pattern` (TEXT, first element), written by the reseed migration | `movement_pattern` | 12 of the 13 rows change their first element (E064 stays `cardio`); verified live read-only 2026-11-12: today's values are the old ones. No Edge Function reads the column (`getFormCues` selects name, cues, mistakes, instructions, muscles, difficulty, logging type; `promote-community-item` inserts) |
| warm-up eligibility | `movement_pattern` | none: no overlay row carries a `warmup` pattern (E064 keeps `cardio`) |

**Prototype (the copy done directly in the asset, the selector reading the target fields; scratchpad
`f2/asset_proto.json`).**

- Golden (1,010 personas): equal to main's fixture (0 keys differ).
- 2,304-plan audit (no injuries): `plan_dump.jsonl` byte-identical to main (sha256 5b3da296...): no uninjured plan
  changes. `audit.json` differs: the audit's own checks read `movement_pattern` / `target_focus`, so its
  "a loaded row of the same pattern could be used" flags now judge by the picker's labels. Plans flagged `unloaded`
  116 -> 46 (Hamstring Walkout 48 and Nordic Curl 22 clear: their slot is `knee_dominant`, where no loaded home leg
  curl exists, while the old audit offered `hip_dominant` hinges); `improvised` 275 -> 0 (Sliding Leg Curl likewise);
  verdicts suitable 482 -> 513, needs work 1519 -> 1763, not suitable 303 -> 28. A measurement correction, not a plan
  change; stated in the closure and on the board.
- Core-list gate (1,036 personas): green.
- Injured sweeps: a, b, c, d, e equal (the ratchet is exact); `f_repeat_pairs30 full_gym` thin days 27 -> 21 (the
  repeat phase's top-up finds same-pattern rows under the copied labels); one-exercise days unchanged. The other three
  f tiers equal.

## 2. Rulings

**Ruling 1 (data: the copy).** On the 27 rows, `movement_pattern := slot_pattern` and `target_focus := slot_focus`,
then both overlay keys are deleted from every row. Key positions: the target field keeps its position, the overlay key
leaves. N19 keeps `hip_isolation` (founder 2026-11-09, S1b-2: N19 is the Glutes-isolation loaded version; E048, its
original, becomes `hip_dominant`). Writers, each changed so a re-run of any historical script reproduces the shipped
library:

- Kept E-rows (26): a new before/after record `scripts/data/library_overlay_copy_v27.json` (for each id: `before`
  {movement_pattern, target_focus, slot_pattern, slot_focus} and `after` {movement_pattern, target_focus}, absent
  keys omitted) applied by a new OVERLAY-COPY STAGE in `add_library_batch_c_v15.js`, the same contract as the
  core-levels / suitable_for / injury-tag stages but MULTI-KEY: every key named in `before` must equal the row's value
  AND every overlay key not named must be absent (a partial match stops the run naming the id and key); a row at
  `before` takes `after` (target fields in place, overlay keys removed), a row at `after` with no overlay key is a
  no-op, anything else stops the run; an id that is not a kept row, or a duplicate, stops the run; an absent record is
  a printed no-op (importer tests copy the script into temp dirs). Order: after the injury-tag stage, before the media
  stage. The hard-coded E274 step (Upper Back -> Mid Back, `add_library_batch_c_v15.js:466-471`) runs earlier, so
  E274's `before.target_focus` is `["Mid Back"]` (the shipped value).
- N20 (source row, rebuilt by `buildRow` from the source each run): the source row's `slot_pattern` key is REMOVED and
  its `movement_pattern` set to `["hip_dominant"]` (its key position is fixed by `REQUIRED`); `LINK` keeps
  `same_movement_as` only.
- The v13 table and script are left as they are: the table is the v13-era record (285 rows) and the script refuses a
  library whose ids differ from the table's (`add_library_core_fields_v13.js:68-71`), so it cannot run on the shipped
  870-row library before or after this unit; its `--check` (a round trip of the file's own bytes) stays green.
- The C2 removals generator is left as it is: `patternsOf('slot', r)` (`library_batch_c2_removals_gen.js:85`) runs
  over the FROZEN fixture `test/fixtures/library_c2_base_depth.json`, which keeps its `slot_pattern` keys (it records
  the library before C2; the depth rule's two semantics differ on it by design), and `buildFixture` (:214-232) is a
  one-shot the normal run and `--check` never reach. `library_batch_c2_removals.json` is not regenerated (its
  `depth_rule` text names the slot semantics of that fixture).

**Ruling 2 (reader).** `CoreListSelector` reads `movement_pattern` / `target_focus` directly (three expressions plus
the `namesMuscle` doc comment at :170). With Ruling 1 shipped the result is identical (prototype: golden and audit
plans equal).

**Ruling 3 (seed v27).** `_exerciseLibraryVersion` 26 -> 27; the new upgrade test
`library_seed_v27_upgrade_behavioral_test.dart` (a v26 bundle rebuilt from the asset with the record's `before` values
and N20's overlay restored, its sha256 pinned independently with Python's compact `json.dumps`, ensure_ascii off; the
box ends at v27 with the 27 rows as bundled and every other row unchanged; MIRROR: a v27 box is not rewritten). The
older seed tests (v16 to v26) move their current-version literal 26 -> 27 and their MIRROR marks. The tests that
rebuild an older bundle from the current asset and pin its sha256 (v23, v24, v25, v26) restore the overlays through a
shared helper `test/helpers/library_overlay_v26.dart` (like `library_g0355_v25.dart`): the target fields take the
record's `before` values in place, and the overlay keys are re-inserted at their measured positions, directly after
`variant_family`, `slot_focus` before `slot_pattern` (all 27 rows, checked on main; N20's `slot_pattern` therefore sits
before `same_movement_as`). The helper is proved by those tests' sha pins (a wrong position changes the digest). Those tests also build their
box from the rebuilt bundle, and a seed to v27 rewrites rows whole (`putAll`), so their "every other row is
unchanged" sets exclude the 27 ids (as Unit 1B-R excluded G0355), and their MIRROR marks move to 27 (a box marked 26
is upgraded now). The
v15, v16, v18 to v22 tests rebuild nothing digest-pinned and need only the literals, except the E274 value pins
(Task 4). The completeness greps of Unit 1B-R's Task 1 are re-run.

**Ruling 4 (cloud).** A reseed migration minted with `sh scripts/mint_migration.sh reseed_exercise_library`,
generated by `scripts/seed_exercise_library.js` from the new asset (870 rows; 12 change `movement_pattern`; no other
column changes). The generator's `BATCH` block (`seed_exercise_library.js:46-76`) is edited for this batch: label
`library v27, Unit 1B-F2`, the diagnose id, `batchTag: 'f2'` (no removals or merges of its own), `previousMigration:
'175'`, `newRowIds: []`, `mergesFile` and `keptRowRecords`. The kept-row record is a per-column record in the
generator's existing shape, `scripts/data/library_f2_movement_pattern.json` (`{id, before, after}`, column
`movement_pattern`, the JSON arrays), holding the 12 rows whose cloud value changes (E046, E048, E050, E015, E127,
E198, E222, E274, E276, E277, E292, N20); E064 is left out (its first element stays `cardio`, so its tuple does not
change and a record row would only add a no-op rollback line). The generator checks each row's `after` against the
library and each `before` against migration 175's tuple, and writes the 12 inline rollback UPDATEs itself, after one
generator fix: its rollback emitter (`seed_exercise_library.js` `changed.push`, value from `cloudValue(e.before)`,
:371 / :420-421) writes a JSON array as a `text[]` literal into the TEXT columns `movement_pattern` and
`exercise_type` (the INSERT path flattens them with `firstOrNull`, :180). (Corrected at build, measured in the local
rehearsal: Postgres does not reject it, it assignment-casts it to the text `{vertical_push}`, a silent corruption.) No record has targeted those columns
before. The emitter maps `before` through `firstOrNull` for those two columns (a set `TEXT_FROM_ARRAY`); the `after`
check and the `before` tuple check keep the arrays (they already go through `tupleOf`). Tests:
`exercise_library_cloud_seeded_test.dart`: the batch-label regexp (:131, today `library vN, Batch ...`) also accepts
`library vN, Unit ...`; the shape dispatch (:234-239, :337, :552-553, :624-630) gains the F2 shape (12 TEXT rollback
lines `SET movement_pattern = '<old>'`, no merges, no removals of its own); a new test asserts the generated rollback
of the F2 record is a bare quoted string per row (a mutation: the emitter without `firstOrNull` reddens it); the S1b-3
label, restore and MUTATION tests (:552-553, :624-630, :676-699) read the APPLIED file
`supabase/migrations/175_reseed_exercise_library.sql` instead of the generator's output, as the S1b-2 tests were moved
to 174 when S1b-3 landed (:633-660, the precedent); the sandbox guard tests that run the real generator copy
(:702-812, including the c2b-tag mirror at :798-812 and the `_batchLabel == 'S1b-3'` / `batchTag: 's1b3'` assertions)
become F2's: the sandbox holds 175 as the previous migration, the label is `Unit 1B-F2`, the tag `f2`; the generator's
merge branch keeps a sandbox test that sets `BATCH` back to S1b-3 with `mutateScript` and 174 as previous (the merge
refusals and the E053 reactivation shape), and an F2 MUTATION test sits next to it (a deleted restore line, a changed
restore value, an array literal in a restore: each a violation). `exercise_library_cloud_tuples_match_test.dart`
compares the generated SQL with the NEWEST migration only (the new file; the S1b-3 generation on the v27 asset
differs from 175 on exactly the 12 rows, so a 175 comparison would be red), copies 175 into its sandbox as the
previous migration (:62-81) and names the new record file in its `containsAll` list. The `BATCH` record entry carries a `note`
(the header's changed-rows sentence prints it): "movement_pattern first element: the picker's slot pattern (12 rows;
E064 keeps cardio)". Blast radius: the two new record files get `tier: account` rules in `docs/blast_radius.yaml`
(next to the S1b-3 records, :549-560) and pins in `blast_radius_library_data_account_test.dart`, in the same commit. `mergesFile` stays
`library_s1b3_merges.json` (its rows carry `merged_in: 's1b3'`, so `ownMerged` is empty for tag `f2`; the generator
stops on a missing file). The 175-style header (intent, destructive: yes (upsert rewrites rows), inline rollback, linked
diagnose). Rehearsed in the local docker
postgres inside `BEGIN ... ROLLBACK` (memory: never rehearse on prod); live counts read-only before (expect 934 rows /
870 active / 64 inactive) and after; applied ONLY on the founder's explicit go (§4.3), then `backups/applied_migrations.json`
and a per-row check of the 12 values. `seed_exercise_library.js:448` and the header comment drop `slot_pattern` from
the JSON-only list. `exercise_library_cloud_tuples_match_test.dart` reads the newest migration file: it is red between
the asset change and the migration file, so both land in one commit.

**Ruling 5 (scope, unchanged behaviour stated).** Uninjured plans do not change (prototype). Injured plans change only
through the top-up's `queryV4` (`f_repeat_pairs30 full_gym` 27 -> 21 thin days; the ratchet lowered). The injury
filter in `queryV4` is unchanged, so no unsafe row can surface (the sweeps' unsafe-pick zeros hold). Display labels
change on 19 rows. No kill switch: a data copy with no new code path (§4.6 covers new code paths; the reader change is
an identity on the shipped data, proved by the golden and the audit dump; the one behaviour change, the injured
top-up, is bounded by the exact sweep ratchet and revertable). §4.6 names the plan generator among its triggers
("payment / sync / auth / AI prompt / plan generator"), so this is a deliberate exception: the founder ruled the copy
into the flip (B1 Ruling 4) with no gate, the reader change is an identity on the shipped data, and the one output
change is ratchet-bounded. The §4.12.4 ship-dark route was considered and not taken: there is no code path to gate, only data, and a data flag would need both label sets shipped side by side,
which is the overlay this unit removes. Recorded in the diagnose. Rollback: revert the commit (the bundle and seed v26
come back with the next install of that build) restores the picker's behaviour only: a device already at seed v27
keeps the copied rows (the seed upgrades only when the stored version is lower, `seed_service.dart:222`), and the
reverted reader's `slot_pattern ?? movement_pattern` then reads the copied values, so its plans are unchanged but its
injured top-up keeps the new labels. A full data rollback is a seed v28 that writes the overlays back (the record's
`before`), plus the migration's inline rollback. Plan rows already stored on a
device keep the `target_focus` they were generated or swapped with, so a new label reaches a plan generated or
swapped after the update. A device whose v27 seed has not finished still reads old
rows under the new reader (E048 as `hip_isolation`): every generation path awaits `seedIfNeeded` first
(`splash_screen.dart:160`, `train_provider.dart:787`, `onboarding_provider.dart:563`), so the window is the seed's own
retry on the next launch. The §4.6 exception is stated in the plan-review record as well as the diagnose.

## 3. Writers and readers

- Data writers: `scripts/data/library_overlay_copy_v27.json` + the importer stage (kept rows); the source N20;
  `seed_service.dart` `_exerciseLibraryVersion`; the cloud: `scripts/data/library_f2_movement_pattern.json` +
  `seed_exercise_library.js` `BATCH`.
- Readers: `CoreListSelector` (:184, :225, :227), `queryV4` (:312, :316, :321), `formatMuscleLabel`, `swap_service.dart:576`,
  the seed import (`seed_service.dart:222`), the cloud reseed, the audit harness (`test/plan_generator/plan_audit/`).
- SoT: `core_list_pool` (description: the overlay sentence replaced), `exercise_injury_tags` unaffected.

## 4. Tasks

1. Data: the record (generated by a one-shot script from today's asset and checked by hand for the 26 ids), the importer
   stage, N20 in the source, `LINK`; `node scripts/add_library_batch_c_v15.js` then `--check`;
   `node scripts/add_library_core_fields_v13.js --check` and the C2 generator `--check` (both unchanged, still green);
   the result equals the prototype asset byte for byte.
2. Reader: `core_list_selector.dart` direct reads; analyze.
3. Seed v27 and the seed tests (Ruling 3).
4. Pins, each changed in the same edit (re-measured on main 67b536e4):

| file | today | after |
|---|---|---|
| `exercise_library_core_fields_contract_test.dart:7, 39-100` (`_slotPattern`, `_slotFocus` and their comments), :131-141 | the ids carrying the keys and their values | the two tables become the expected `movement_pattern` / `target_focus` of the 27 rows; the test asserts no row carries either key |
| `exercise_library_schema_contract_test.dart:41-45, 74` | allow-list holds both keys; "40 required plus 15 optional" | both leave the allow-list; 13 optional |
| `library_s1b2_loaded_versions_test.dart:34, 65, 70-71` | `slot_pattern` in `_copied`; E048 keeps its overlay; N19 carve-out on `slot_pattern` | `slot_pattern` leaves `_copied`; E048 `movement_pattern` `hip_dominant`; N19 carve-out on `movement_pattern` (N19 stays `hip_isolation`) |
| `core_list_pool_behavioral_test.dart:493, 501` | `slot_focus ??` in an oracle; "slot_pattern fills the Front Delts isolation slot" | the oracle reads `target_focus`; the test is renamed and asserts E015's `movement_pattern` |
| `library_batch_c_rows_contract_test.dart:37-39`, `test/scripts/library_media_importer_test.dart:841-850` | LINK passes `slot_pattern` | N20 carries `movement_pattern` `[hip_dominant]` and no overlay; LINK holds `same_movement_as` only |
| `library_depth_rule_test.dart:4, 163`, `test/helpers/library_depth.dart:9, 38` | the depth rule under both semantics | unchanged on the frozen base; on the shipped library the slot semantics equal the plain ones; 0 violations before and after |
| `injury_safety_tags_v13_behavioral_test.dart:85` | `queryV4('hip_isolation')` holds E127 | the tuple moves to `hip_dominant` |
| `injured_push_day_core_test.dart:46` | reads `slot_pattern` first | reads `movement_pattern` |
| `exercise_library_frozen_reference_test.dart` (fixture `exercise_library_v12_row_hashes.json`) | hashes all 26 kept overlay rows | re-recorded with `RECORD_LIBRARY_REFERENCE_IDS=<the 26 ids>`, named in the diagnose |
| `injury_floor_sweep_lib.dart:343` | `f_repeat_pairs30 full_gym: (27, 0)` | `(21, 0)` with the reason |
| `library_batch_c_rows_contract_test.dart:285-286` (`_e274Violations`), :570, :576 (its mutation) | E274 `target_focus` is exactly `[Mid Back]` | the Batch C1 invariant restated: E274 carries `Mid Back` and no `Upper Back`; the :576 mutation (Upper Back restored) still reddens it |
| `library_seed_v15_upgrade_behavioral_test.dart:49, 77`, `library_seed_v16_upgrade_behavioral_test.dart:96` | E274 bundled / upgraded `target_focus` is `[Mid Back]` | the same invariant (contains `Mid Back`, no `Upper Back`) |
| `exercise_library_cloud_seeded_test.dart:131, 337, 624, 702-780`, `exercise_library_cloud_tuples_match_test.dart:62-81` | the S1b-3 batch label, migration 174 in the sandbox | Ruling 4 |
| `docs/naming_conventions.md:306` (the overlay glossary entry), `docs/sot_registry.yaml` (`core_list_pool` and the entries citing the overlay at ~:11782, :11974-75, :12002, :12037), `plan_engine/CLAUDE.md:64, 118, 120` | name the overlay keys as live | rewritten: the keys are gone since seed v27; the glossary entry kept as history |
| `seed_service.dart:108` and the version comment :178-183 (the v27 line and its test), `docs/ship_dark_pending_review.yaml:303-305` (says the flip commit copies the overlays), `seed_exercise_library.js:448`, `add_library_batch_c_v15.js:37, 101-104, 470`, `plan-engine-detail.md`, `docs/reference/exercise-library.md` | name the overlay keys | updated |

   Completeness: `git grep -n -E "slot_pattern|slot_focus" -- lib scripts test supabase/functions docs/naming_conventions.md
   docs/sot_registry.yaml docs/ship_dark_pending_review.yaml` returns only: the frozen C2 fixture and the C2 generator / removals file that read it,
   `library_depth.dart`'s base-fixture read, the v13 table and script (history), the new record and helper, migrations
   171-175 (history), and comments that say the keys were removed.
5. Tests (new): `library_overlay_copy_test.dart`: (a) no shipped row carries either key; (b) each of the 27 rows equals
   the record's `after` (and N20 its source value); (c) the importer stage: a row at `before` is copied, at `after` is a
   no-op, anything else stops the run naming the id, an unknown id stops it (importer test group, temp dirs, as the
   injury-tag stage's); (d) `rankedPool` on the shipped library returns the same order as on the v26 library for every
   slot of every split at every level and phase, bodyweight and full_gym capability (the reader change is an identity).
   Mutations: the stage skipped (a, b red); the stage writes `after` without deleting the overlay (a red); a `before`
   mismatch accepted (c red); the selector reads `slot_pattern ?? movement_pattern` on a v27 library with a planted
   overlay (d's companion red); the version constant back to 26 (v27 red); one record value changed (b red).
6. Re-run: golden (equal), audit (plans equal; the audit summary re-baselined), core-list gate, same-movement gate,
   the six sweeps, `core_list_like_for_like_data_test.dart`, the T5 / T5b / T8 real-data tests of 1B-R, the seed tests,
   and the real-library injured-user tests the prototype did not run: `thin_day_topup_behavioral_test.dart`,
   `injury_filter_behavioral_test.dart`, `plateau_rotation_behavioral_test.dart`,
   `cross_phase_variety_behavioral_test.dart`, `keep_all_slots_selection_test.dart`; then `test/contracts/` whole and
   the review CI (the full suite) before the round-4 review of the draft diff.
7. Docs: diagnose `docs/diagnoses/2026-11-12-generator-overlay-copy-<id>.md` (full template, writers / readers above,
   recurrence: the label drift class between the picker and `queryV4`, B1 Ruling 4), closure
   `docs/audit/generator-step1-1bf2.closure.yaml`, SoT, nested CLAUDE.md, OI-495 closed.
8. Migration (Ruling 4): mint, generate, rehearse locally, read live counts, STOP for the founder's go; then apply,
   ledger, verify.
9. Full gate loop (§4.12.8), B-pass, commit, PR, `land_pr.sh`, retire, board, memory.

## 5. Acceptance

- Golden equal; audit plans byte-identical; sweeps equal except the lowered f ratchet; unsafe zeros hold.
- No row carries an overlay key; every historical script's `--check` green; the seed upgrade proved.
- Every mutation in Task 5 reddens its test.
- The migration applied on the founder's go; 12 cloud values changed, nothing else.
- Runtime: the founder's device check (a label on one of the 19 rows; an injured plan's top-up day), with 1B-F's and
  1B-R's.

## 6. Review log

- **Round 1 (Sonnet, context-blind, 2026-11-12): not converged, 3 P1.** (1) E274's `target_focus` becomes
  `[Mid Back, Rear Delts]`, pinned as exactly `[Mid Back]` in four places (C1 rows contract, seed v15 x2, v16): added
  with the C1 invariant restated. (2) The cloud seed generator's `BATCH` block and its two test files were not
  planned: Ruling 4 now edits `BATCH`, uses a per-column `movement_pattern` record of the 12 rows (E064 out) and lists
  both tests. (3) The C2 generator change would have changed the removals decisions on the frozen fixture: the
  generator and its file are left alone. P2: the v13 script cannot run on the shipped library (it is left alone; only
  `--check` applies); the overlay key positions for the seed helper (measured: after `variant_family`, `slot_focus`
  first); the glossary and registry pins; the stage's multi-key validation and N20's key removal; plan rows already
  stored keep their old label. P3: the kill-switch argument (ratchet-bounded, revertable, ship-dark considered).
  Verified clean by the round: the prototype is exactly the copy (27 rows, key order kept, N19 unchanged); the cloud
  holds only the first `movement_pattern` element and no `target_focus`; `SameMovement` has no pattern logic; the
  N19 carve-out is needed and sufficient; the frozen-reference ids; the other real-library tests.
- **Round 2 (Sonnet, context-blind, 2026-11-12): not converged, 1 P1.** (1) The generator's rollback emitter writes
  a JSON array as `text[]` into the TEXT column `movement_pattern`: Ruling 4 now maps `before` through `firstOrNull`
  for the two TEXT columns, with a test and a mutation. P2: (2) the S1b-3 sandbox tests in the cloud-seeded test would
  lose their merge coverage once `BATCH` moves: they run with a mutated `BATCH` set back to S1b-3, the tuples test
  keeps 174 and 175; the batch-label regexp accepts `Unit`; (3) a revert restores the picker's behaviour only, not v27
  devices' data (a v28 reverse copy is the full rollback); (4) the §4.6 trigger list quoted, the exception argued. P3:
  `ship_dark_pending_review.yaml:303-305`, the core-fields contract's `_slotPattern` / `_slotFocus` tables, `_copied`'s
  `slot_pattern`, the schema test's optional count (15 -> 13), the seed version comment. Verified clean by the round:
  the prototype equals the copy; the key positions; no missed overlay reader or writer; the remaining target-field
  readers; the importer data path; round 1's P1 fixes (E274 pins and the :576 mutation, E064 out of the record); the
  N19 / N20 pairs; digest pins only in v23-v26; the depth rule (0 violations, both semantics, main and prototype); the
  equipment-tier floor per pattern; the real-library `queryV4` tests; the generator's empty-batch paths.
- **Round 3 (Sonnet, context-blind, 2026-11-12): not converged, 1 P1.** (1) the S1b-3 MUTATION test (:676-699) and
  the sandbox guard test (to :812) build on the generator's output, which becomes F2's: the S1b-3 tests read the
  applied 175 (the S1b-2 precedent, :633-660), the sandbox tests become F2's with one S1b-3 merge-branch test under a
  mutated `BATCH`, and an F2 mutation test is added. P2: (2) the tuples test cannot compare an S1b-3 generation on the
  v27 asset with 175 (12 rows differ): it compares the newest migration only; (3) blast-radius `account` rules and
  pins for the two record files; (4) the older seed tests' boxes come from the rebuilt bundle, so their "others
  unchanged" sets exclude the 27 ids and their MIRROR marks move to 27. P3: the `BATCH` record `note`; the seed window
  under the new reader and the §4.6 exception in the record; the real-library injured tests the prototype did not run.
  Verified clean: the prototype equals the copy; the cloud effect is exactly 12 rows; the generator's empty-batch paths
  and the `firstOrNull` fix; the key positions; the E274 invariant and its mutation; the importer and historical
  scripts; N19 / N20; the source test; the depth rule; the other readers; the real-library `queryV4` tests; the sweeps.
  Rounds 1-3 each found pins only in the test harnesses around the cloud seed generator and the seed tests (the
  mechanism converged at round 2): the build runs the whole `test/contracts/` and the review CI, and round 4 reviews
  the draft diff (§4.12.5), where a missed pin is a red test rather than a reading.
- **Round 4 (Sonnet, context-blind, 2026-11-12, on the BUILT diff after review CI was green on 7ca1233b): converged
  (0 P0 / P1).** P2 (1): the pool-identity test in `library_overlay_copy_test.dart` was vacuous (the per-row test already
  makes the two libraries content-equal) and four records cited it as independent proof: the test is removed, its slot
  sweep lives in the planted-overlay test, and the diagnose, closure, SoT registry and OI-495 now cite the per-row
  identity, the planted-overlay guard, the golden and the plan dump. P3: the LINK line (109 -> 112) and "20 blocks" (24)
  citations; `seed_service.dart:127-128` / `:190` in `exercise_plate_library_data_test.dart` (stale on main) -> 227-228 /
  314; `readOverlayCopy` now refuses a record row whose `after` is not the overlay its `before` carries, and test (e)
  asserts each refusal's text (the check removed reddens it); the two display-only readers (`ai_snapshot_builder.dart:614`,
  `injury_swap_planner.dart:196`) named in the diagnose. Verified clean by the round: the asset against the record and
  main field by field; N20; the importer's idempotency and refusals; the v26 rebuild equal to main's asset; the planted
  test non-vacuous; `_s1b3Batch` equal to main's BATCH; 176 vs 175 exactly 12 tuples, the rollback values; the registry
  ranges.
