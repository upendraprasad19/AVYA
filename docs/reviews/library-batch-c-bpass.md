---
reviewed_at: 2026-10-26T13:10:00+05:30
staged_against: 1eeb7705f417c2aba7f4e8e5c2f14968e6f2d39f
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh reviewers: A data / importer / tags / seed / cloud generator, B tests / gates / baselines / documents)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 14
verdict: accepted  # 0 P0, 1 P1 + 13 P2; every finding verified by the author against the files before acting; 13 fixed in the batch, 1 (B6) is expected and lands in its own later commit; 0 false alarms; 2 reviewer numbers were wrong and corrected from the source
---

# Code Review (B-pass) — branch `library-batch-c` (Batch C1), `git diff origin/main...HEAD` at `1eeb7705`

Severity count: P0 0 · P1 1 · P2 13.

Method note. Two reviewers with no conversation context, each given a part of the diff, the batch's own claims as numbers to recompute, and an exhaustive allow-list of read-only commands (no `dart run scripts/*`, no sweep, no golden, no gate runs; seven named contract files allowed). Neither wrote into the repo. Reviewer B ran one `git fetch` outside the allow-list (it only moved a remote-tracking ref; `origin/main...HEAD` was unchanged) and said so. Every finding below was re-verified by the author from the files, not from the reviewer's summary: G1432's picture was read against G1431's, the builder's sibling filter and the Dart helper's were read side by side, the generator's ledger guard was run unfixed (it rewrote migration 162 in the worktree; restored with `git checkout`, `git status supabase/` clean), the shard layout was recomputed with `scripts/ci_test_partition.dart`, and every document number was recomputed from the data.

## Finding 1 — P1 — writer_reader_drift (two rows that show the same machine disagree on equipment)

- **file:line:** `assets/data/exercise_library.json` G1432 Standing Assisted Pull Up (source `scripts/data/library_batch_c_source.json`, no `picture_checked` record before this review).
- **claim:** G1432 shipped `equipment_needed ["pull-up bar","elevated surface"]`, tier `basic_gym`+`full_gym`, cue "Start from a full hang". Its picture (`1432_Standing_Pullup.gif`) is the same weight-stack assist machine as G1431 (`1431_Standing_Chinup.gif`), which was read at triage and ships `["machines"]`, `full_gym`. A basic_gym user could be served a machine the gym tier does not have (the OI-89 class), with a cue that does not match the movement. Exposure was small: `priority_tier 3`, not core.
- **verification:** I read both GIFs: same platform, same stack, same handles. `node -e` on the library printed the two rows' equipment as above.
- **status:** accepted, fixed. Source row set to `["machines"]` (`full_gym` derived), exercise_type compound, cues and mistakes in the G1431 style, `picture_checked.G1432` record (`edited`); scope `--write` and `--check` OK (picture records 104, unchecked shipped rows 530 to 529, doubting-note unchecked 131 to 130; OI-437, the diagnose doc and the ledger updated). New check `_sameMachineViolations` in `library_batch_c_rows_contract_test.dart` (positive on the real library, mutation reddens it). The bounded sweep for the same class (id-adjacent rows whose equipment differs from an `edited` record) found only this pair; the rest of the unchecked residual stays OI-437.

## Finding 2 — P2 — guard_without_its_mirror (builder sibling pool)

- **file:line:** `scripts/build_library_injury_additions_v15.js:50` against `test/helpers/library_injury_floor.dart:27-29`.
- **claim:** the builder took same-family siblings from the WHOLE library file. Right at commit 3 (only E rows), wrong from commit 5 on: the file now holds the shipped G/N rows and the row being built, so a from-scratch build or a `--drop` and re-run counted new rows as "originals" (reasons read "all 16 same-family originals" for 3).
- **verification:** new test `a from-scratch build reproduces every non-judgement row of the committed table` failed on the unfixed builder with 506 differing rows (the reason strings counted new rows as originals), passes after.
- **status:** accepted, fixed (`/^E\d/` filter). The test also handles the 9 rows where the founder dropped a majority token (committed reason is the built reason plus the recorded drop).

## Finding 3 — P2 — asserted_fixture_value (under-tag, per movement)

- **file:line:** G0786 Squat Jerk, table class `judgement`, tokens `[]`.
- **claim:** shipped `[lower_back, shoulder, wrist]`; the loaded squats E036, E037, E088, E112 and E149 all carry hip + knee. A knee- or hip-injured user was not filtered from a deep overhead squat catch. Low exposure (olympic, requires_coaching, tier 3, advanced) but it is the sixth under-tag instance's own class.
- **verification:** library query: G0786 is the only olympic squat-catch row without a leg token.
- **status:** accepted, fixed: table tokens `hip`, `knee` with a reason (founder's standing rule: tag per movement, no "kept safe" list). Tightening only; golden hashes unchanged. Surfaced to the founder in the PR text because the table was founder-approved.

## Finding 4 — P2 — guard_without_its_mirror (seed generator ledger refusal)

- **file:line:** `scripts/seed_exercise_library.js:72-85`.
- **claim:** the "number already in the applied ledger" refusal ran only when `--out` was absent; `--out supabase/migrations` (any spelling) rewrote the immutable applied migration.
- **verification:** new test (four spellings) failed on the unfixed generator, and the run really did overwrite `162_reseed_exercise_library.sql` (restored by `git checkout`; `git status supabase/` empty). Green after.
- **status:** accepted, fixed: the refusal runs whenever the resolved output directory is the default migrations directory.

## Finding 5 — P2 — missing_input (new vocabulary value)

- **file:line:** 7 rows with `difficulty_level "elite"` (G3297 G3303 G3315 G3299 G0725 G3291 G3298); documented vocabulary `getFormCues.ts:41` is beginner / intermediate / advanced.
- **status:** accepted, fixed in the source file (`advanced`), new vocabulary check over all 914 rows with a mutation. Readers print the raw string, so this was cosmetic, but a fourth value in a documented three-value column is how the next reader breaks.

## Finding 6 — P2 — asserted_fixture_value (doc number, ambiguous)

- **claim:** diagnose doc "nine rear-delt rows tag shoulder": the `rear_delt_fly` family has 16 shipped rows, 13 carrying `shoulder`, 3 safe pool.
- **verification:** nine is the count of rows that GAINED `shoulder` from the table (raw tags had none or only `lower_back`); four more already carried it. The number was right, the sentence was ambiguous.
- **status:** accepted as wording; fixed in the diagnose doc, ledger and registry ("nine gain, four already carried it, three safe pool").

## Finding 7 — P2 — writer_reader_drift (field disagrees with its siblings)

- **file:line:** G0725 Single Arm Push Up `is_bilateral true`; the other 79 single/one-arm/leg rows are false.
- **status:** accepted, fixed in the source; new check (every new single-limb row is not bilateral, covering more than 60 rows, with a mutation).

## Finding 8 — P2 — asserted_fixture_value (CI shard layout)

- **claim (reviewer B):** the diagnose doc says the pairs 4/6 block, the singles block and the B2 gate land on shard 4; after the origin/main merge they land on shard 1 (main's four new test files moved the indexes), 405 + 514 + 327 = 1,246 s solo = 20:46 against the 20-minute shard cap and the 18-minute stop rule.
- **verification:** `dart scripts/ci_test_partition.dart <shard> 4` for all four shards reproduces it; the author's brute force over name families found `injury_sweep_a..e` gives a heaviest shard of 679 s (shard 1 repeat + B2 gate; 2 core gate + pairs + singles46 678; 3 thin-day + singles 547; 4 golden + pairs46 + scorecard 672).
- **status:** accepted, fixed: the five files renamed (`git mv`; the letter is a CI sort key, explained in the first file's header), living references repointed, doc corrected. Historical docs keep the old names. Fragile by nature (any file added before them re-deals the shards), so the draft PR's four shard times still decide.

## Finding 9 — P2 — guard_without_its_mirror (golden R6)

- **claim:** R6 (iii) was `isNotEmpty`; `newRowPickViolations` had no committed negative test.
- **status:** accepted, fixed: (iii) now needs at least half of the personas to pick a new id (measured 939 of 998), and `test/contracts/library_new_row_pick_violations_test.dart` feeds every branch a violating row plus the mirror cases; mutating the (i) and floor-token checks reddens 5 of its 10 tests.

## Finding 10 — P2 — guard_without_its_mirror (weakened end-to-end proofs)

- **claim:** the thin-day, E121 and Hip Adduction generator-level proofs were re-pointed or moved to `queryV4`; the diagnose doc did not say so.
- **verification:** the tests' own comments record the reach searches. The reviewer's figures "36 and 48 combinations" were WRONG: the E121 search covered 3 goals x 4 tiers x 3 levels x 4 day counts, the hip adduction one 36 combinations.
- **status:** accepted, fixed: a "Traded proofs" bullet in the diagnose doc with the correct figures.

## Finding 11 — P2 — asserted_fixture_value (eight document numbers)

- **status:** accepted, fixed, each recomputed by the author: equipment-audit waivers 37 to 36 (`git diff ... | grep -o` = 36 at the reviewed SHA; 37 again after Finding 1, because G1432's name says pull up on a machine row and the audit gate asked for its own waiver); "83 core-list slots (56/47/31)" is 83 rows and 134 level slots; "11.6 percent of the library" is the ORIGINAL 285-row library (33 of 285), the 914-row library is 62 of 914 = 6.8 percent; "125 reads" is 125 records (100 + 22 selected, extra records from the equipment audit), now 126 records and 122 selected; OI-436 "the file's 11 tests" is 12; OI-435 "400 rose, 118 fell" recomputes to 416 and 121 over coverage, balance, volume and realism (410 and 121 beyond 0.2); "five files of four tests" is 22 tests now; the shard (Finding 8).

## Finding 12 — P2 — blast_radius_mismatch (OI-404 closure basis)

- **claim:** the closure said no volume loss is left; 86 of the 176 moved personas are still below the original baseline (mean -2.72, worst -12.0, 74 uninjured; 36 p6, 31 p1, 19 p2).
- **verification:** all five figures recomputed from `git show 8ef89153:` and `origin/main:` against the current baseline.
- **status:** accepted, fixed: the closed entry and the ledger now say the closure is on the aggregate re-measure its own last sentence allowed, name the per-persona residue, and say why it cannot be attributed to the seven rows any more. No new OI (the residue is a scorer-feature question in OI-435's family).

## Finding 13 — P2 — missing_input (plan-review record)

- **claim:** `docs/plan-reviews/library-batch-c.md` (cited by the ledger) does not exist.
- **status:** expected and not a defect of this diff: the record needs `bpass: accepted`, so it lands in its own later commit citing this file (SKILL.md §3 hash-cycle rule). Tracked as a Task 6 step, not a finding.

## Finding 14 — P2 — guard_without_its_mirror (what the sweep silently assumes)

- **claim:** a plan week that lost a day was neither empty nor thin; the tier pin covered the constants only; a block file could drop its tier loop unnoticed; the phases are narrow.
- **status:** accepted, fixed: `scan` takes the requested day count and counts `wrongDayCount` (gated in `expectSafe`); the first sweep file pins injuries, pair injuries, goals and levels as literals and reads all five files for the tier loop, the run call with its day list, and both gates (a mutation dropping one file's loop reddens it); the phase scope is written into the OI-408 closure. The "tags are the oracle" point is by design (the coverage test owns under-tagging).

## Founder triage notes
<filled in by founder during triage>

---

# What each lens checked and found clean

- Row shape on all 914 rows (key set and order, derived keys, float tokens, ASCII, no `;`, cue style, unique names including aliases, links resolve); `equipment_tier` recomputed from the Dart tier table (0 mismatches); Smith machine 39 rows all `full_gym`; E rows byte-identical to `origin/main` except E274.
- Final tags equal sorted(raw union table) for all 629 rows, every token canonical, 29 untagged new rows equal `safe_pool_additions`, `kV14SafePool` equals the 62 untagged names, the table re-serialises byte-identically; twins hold; the importer builds from an allow-list so a held row or a source `note` / `changes` / `confidence` cannot leak; `--check` is byte equality over the inputs the writer reads.
- Seed: version 15, the upgrade path keeps the community row and deletes only retired E ids; generator tuples for the 285 kept rows are byte-identical to migration 162; every INSERT column exists in `backups/live_schema_columns.json`; the rollback `source = 'exercise-gif-set'` selects exactly the 629 new rows; the 3 red cloud-seeded checks are red only because the migration file does not exist.
- Sweep split equivalence (functions byte-identical to the old file apart from the tally class name; run counts 432/216/360/360/432 = 7,200; no path for a thin day to pass), golden fixture shape (999 keys, same sorted order, 943 values changed), core gate classification untouched, scorecard aggregates recomputed from 606 personas, ledger commits exist, equipment_vocab.dart comment-only.
- Noted, not defects: G0815's `progression_to` is not reciprocal (cosmetic, no reader needs it); `--check` reads kept rows from the shipped file so it cannot see an edit to an E row (the row-by-row comparison with `origin/main` closes it for this SHA); the scorecard gate is one-sided by design (a stale-low baseline also passes), and after this review the regenerated baselines are byte-identical to the committed ones.

## Tuning entry
- **2026-10-26** - blast-radius platform - 14 findings; 0 false_alarm; tuning: the reviewer that was told to RECOMPUTE every number in the batch's own documents found eight wrong or ambiguous ones that the author's self-review had passed, so a brief should list the document claims as numbers to recompute, not as text to read; a twin check (rows whose pictures show the same machine, adjacent source ids) caught what a per-row picture triage could not, so lens 8 gains "twin rows must agree"; a builder that reads the library its own pipeline later writes into silently changes meaning at the commit that first ships rows (self-inclusion), so lens 6 gains a sub-check; and a reviewer's own numeric claims (the reach-search sizes) were wrong in one place, which is why every figure was re-derived from the source before it was written into a document.
