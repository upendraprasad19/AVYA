---
reviewed_at: 2026-11-06T16:33:00+05:30
staged_against: library-batch-c2c (staged tree: 29 files at the seats' read, final tree after the fixes; pre-commit, whole-project analyze and the full suite run on it, red only where the diagnose doc says)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh seats, no conversation context)
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value, unawaited_no_error_sink]
findings_count: 17
verdict: accepted
verdict_note: all seventeen handled by the working session (ten in round 1, seven in the delta round of 2026-11-07), none left open; the founder is told in the batch summary
---

# Code Review: Library Batch C2c (E230 Standing Single Leg Curl becomes a bodyweight row)

Plan `docs/plans/2026-11-06-library-batch-c2c-e230.md`, diagnose `docs/diagnoses/2026-11-06-library-batch-c2c-e230-d8ac69.md`. Seat A took data, seed and cloud (lenses 1, 3, 7); seat B took guards, tests and text (lenses 6, 8, unawaited, secrets). Both ran the allowed test files, `node scripts/add_library_batch_c_v15.js --check`, the seed generator into a scratch directory, and `dart analyze` on the staged Dart files. Seat A rated one finding P1 (the second readers of E230's logged history), seat B rated the same one P2; it is recorded as P1 here. No P0.

## Finding 1 - P1 - writer_reader_drift (second readers of E230's logged history)
- **file:line:** `docs/diagnoses/2026-11-06-library-batch-c2c-e230-d8ac69.md` readers and accepted (c); unlisted readers `lib/features/train/providers/train_provider.dart:99-107`, `lib/features/train/screens/active_workout/exercise_last_try_lines.dart`, `lib/shared/repositories/plan_engine/progression_resolver.dart:239-277` with `periodization_engine.dart:108-112`, `lib/core/services/auth_session_bootstrapper.dart:1196-1262`, `lib/core/services/logging_type_repair_migrator.dart:315-322`, `lib/shared/repositories/plan_engine/core_list_selector.dart:196`.
- **claim:** the doc named only `workout_write_service` as a reader of the old `weight_reps` rows and called (c) "keeps its cable weight". Readers that key on the exercise NAME and the LOG's stored `logging_type` show LAST and TRY lines and a "N kg (from last phase + progression)" cue on the now unloaded row, and the sign-in heal meets a deterministic mismatch for every account with E230 history.
- **verification:** read each cited range. Seat B also said the heal zeroes `weight_kg`; that part is false (`fieldsClearedFor('bodyweight_reps')`, `workout_write_service.dart:93-115`, clears only duration and distance), seat A's reading was right. The heal reaches only rows still in memory as `Map<String, dynamic>`; a row from disk throws at the `.cast` (OI-394) and the outer catch records `exlog_format_normalization_heal_failed`. The migrator's flag is `logging_type_repair_v3_done` (its header still says v1).
- **status:** accepted, no lib change. Every reader is now in the diagnose `readers:` list and in the registry manifest, accepted (c) states the visible effects and the repair paths that do not reach them, and the reason is the launch status (every account is a testing account, CLAUDE.md section 1). The new heal-failed telemetry on a tester's device is named.

## Finding 2 - P2 - asserted_fixture_value (figures and prose in operations docs)
- **file:line:** `docs/operations/EXERCISE_MEDIA.md` (the 310.03 MB and "about 806" rows, the "E230 are listed there" sentence), `docs/operations/GO_LIVE_CHECKLIST.md`.
- **claim:** the diff set 758 files / 311.87 MB in one row and left two others on the old figures; E230 was still described as a waiting pair.
- **verification:** `node` over `library_media_v16.json`: 758 files, 311,867,164 bytes, 250000/311.867 = 801, 5000/311.867 = 16.
- **status:** fixed (all rows read 311.87 MB, about 801 and about 16; E230 is described as released and retagged by C2c).

## Finding 3 - P2 - asserted_fixture_value / test hygiene
- **file:line:** `test/contracts/library_e230_retag_test.dart` (sample floor, tier and `gym_availability` equality), `test/contracts/library_media_table_test.dart` (`retag_waits` pinned empty), the version pins.
- **claim:** a floor of 90 against a sample of 92; the convention assertions tie E230's permanent contract to every future bodyweight row; `retag_waits` empty is a snapshot.
- **status:** fixed (floor 50; the tier set and `gym_availability` are checked against the MODAL value of the sample; the media-table test now asserts "E230 not in retag_waits"). The literal `20` in six version pins is the existing pattern and an optional helper was not added.

## Finding 4 - P2 - guard_without_its_mirror (the seed generator)
- **file:line:** `scripts/seed_exercise_library.js` (the BATCH comment, the Intent and Rollback header text, `reactivateLine` / `deactivateTwinsLine`, the new `fail()` paths).
- **claim:** a comment said nothing else names a batch while the header text hard-coded C2c; the non-empty list branches and two of four new `fail()` paths had no test.
- **status:** fixed (comment and header reworded and derived from the BATCH block; sandbox cases for `batchTag: 'c2b'`, an id that is not a library row and a missing `before` cloud column; the unknown-label violation test kept).

## Finding 5 - P2 - guard_without_its_mirror (importer message)
- **file:line:** `scripts/add_library_batch_c_v15.js:216-232` (`retagRow`).
- **claim:** for a half-applied row (eight keys at `before`, one at `after`) the error listed all nine keys.
- **verification:** both seats ported the function into `node -e`; the behaviour was right, the message was not.
- **status:** fixed (the message names the keys at `before`, the keys at `after`, and the keys with a foreign value; test (c) asserts the minority key).

## Finding 6 - P2 - asserted_fixture_value (diagnose doc evidence and labels)
- **file:line:** `docs/diagnoses/2026-11-06-library-batch-c2c-e230-d8ac69.md` status line, tiers 5 and 9, the "Gates" pointer, the "(accepted, plan change b)" label, the attribution counterfactual.
- **claim:** `status: fixed` and tiers 5 and 9 were written before the live steps; the ledger the doc points at did not exist; the (c) label was wrong; the 338 / 215 / 21 classification and the 21-of-21 counterfactual rest on a throwaway test the plan deletes.
- **status:** fixed (`status: built_live_steps_pending` with a state line naming the two live gos; the gate results are written into the doc; the label reads (c); the attribution test, classifier and ripple keys are kept as `.txt` under `docs/audit/library-batch-c2c-attribution/`).

## Finding 7 - P2 - missing mirror (the record's `gif`)
- **file:line:** `scripts/data/library_e230_retag.json`, `test/contracts/library_e230_retag_test.dart`.
- **claim:** `gif: "0795"` was asserted only as a literal.
- **status:** fixed (a test compares it with the media table's `rows.E230` slug prefix and with the old-rows input entry's `gif`).

## Finding 8 - P2 - writer_reader_drift (registry ranges and manifest)
- **file:line:** `docs/sot_registry.yaml` (`applyMedia` 154-175, `docs/blast_radius.yaml` 39-539, the `exercise_library_schema` manifest).
- **claim:** the ranges were stale after the insertions (the parity gate checks bounds only for a prose method), and the manifest did not list the retag record, its importer stage or the second readers.
- **status:** fixed (`applyMedia` 172-193, `blast_radius.yaml` 39-634, the record and the stage added as writers, seven second readers added with their semantics, each cited line read).

## Finding 9 - P2 - blast_radius_mismatch (one engine)
- **file:line:** `test/contracts/blast_radius_library_data_account_test.dart` group 1d.
- **claim:** groups 1 and 1b also assert the commit-time review gate's own copy of the rules reader; 1d asserted only the classifier.
- **status:** fixed (the `reviewGate.parseRules` assertion, with a look-alike mirror, was added to 1d).

## Finding 10 - P2 - plan-generator baselines not re-frozen
- **file:line:** `test/plan_generator/baseline/baseline_scorecard.json`, `baseline_plans.md:253`.
- **claim:** line 253 still showed the attempt-3 fallback pick E230 now replaces, and the gate only asserts "at most the baseline", so the old fallback total stayed allowed.
- **verification:** the generator was run on the HEAD library and on this tree (library swapped in place with the byte-compare restore). The committed freeze was already stale before this batch (420 of 606 entries differ from a HEAD regeneration, mean overall 82.3 against 83.2). The C2c-only delta is 246 personas, each explained by the picks mirror: fallback picks 2009 to 1765, overall 83.2 to 82.9, progression 78.7 to 75.7 through 18 personas in six bodyweight beginner families flipping on a one-set difference in the sum of library `default_sets` in phase 6.
- **status:** fixed (both files re-frozen on this tree; the diagnose doc states the pre-existing staleness, the C2c-only delta and the one-set sensitivity; the scorecard gate passed against the old freeze before the refresh and against the new one after).

## Verified clean (attacked, not broken)
- Importer: the record absent (printed no-op), the row at `before`, at `after`, half-applied, a foreign value, a typo key and an id that is not a kept row; `readRetag` and `retagRow` return values followed to both call sites; `--check` byte-identical to a fresh import, 862 rows; the library differs from HEAD in E230 only (nine record keys plus the three media keys appended last).
- Generated seed: one non-comment line differs from migration 171, the E230 tuple (958 identical lines); no `IN ()`; header counts match the data (862 rows, 633 gif-set rows, 7 retire UPDATEs, 56 removals, 63 inactive); the rollback restores the four cloud columns with the array literals of migration 171 and the uuid v5 of `exercise_library|E230`.
- Numbers recomputed from the data: 92 sample rows (tier set 92/92, `gym_availability` home 92/92, logging 81/9/2), media table 758 files / 311,867,164 bytes / 759 rows, golden 998 keys with 574 changed (338 + 215 + 21), all 229 frozen row hashes.
- Animation 0795 in the founder's folder: sha256 equals the table's `1009bd7d...`, 252,438 bytes; the bundled still equals the `thumbnails-192` file byte for byte.
- Blast radius: maximum staged tier `platform`; the library, media table, seed service and the new record are `account`; the new rule sits above `scripts/**`. No secrets in the diff; no Edge Function or schema change.

## Delta round (2026-11-07): a second fresh seat on everything after the batch commit 0577f760

One seat, tip 30ed28d0, lenses A to H: merge-resolution safety, the re-pinned Quads test, the golden, the baseline, the migration ledger, the binding-doc figures, the skill bullet, hygiene. Verdict: no merge damage. It checked 106 paths main changed since the base (98 byte-equal to main, 8 differ only by this batch's own lines), the ledger (181 records, 172 and 173 each hash their own file, the diff against main is the 173 append), the golden (574 changed keys, the same set as before the merge; 60 keys differ from the pre-merge golden), the baseline figures, and re-ran the probe (24 cells, identical to the author's log). It found 2 P1 and 5 P2; the seat also ran one command outside its list (`git merge-tree --write-tree`), which only wrote an unreferenced tree object. Each claim below was re-verified by the working session before it was acted on.

## Finding 11 - P1 - binding-doc over-claim (golden split)
- **file:line:** `docs/diagnoses/2026-11-06-library-batch-c2c-e230-d8ac69.md` (Merge with main bullet).
- **claim:** "the SAME set of 574 keys ... so the C2c effect and its 338 / 215 / 21 split stand". An equal key set does not carry the class of each key; 45 of the 574 keys are also among the 60 keys main itself changed (OI-454), and their class was never re-measured.
- **verification:** `node -e` over the goldens at HEAD, 77af2d56, c2f81ea4 and 1118d3b1: changed against main 574, main against base 60, intersection 45, HEAD against the pre-merge golden 60 (confirmed by the working session).
- **status:** fixed (the doc now says the key set is unchanged, the split was measured before the merge, and 45 keys are unverified).

## Finding 12 - P1 - wrong baseline and floor for Hamstrings
- **file:line:** the diagnose doc (Interaction with OI-454 bullet), the OI-477 "Widened by Batch C2c" paragraph, the comment above `_quadsAfterC2c` in `quads_floor_6day_behavioral_test.dart`.
- **claim:** "Hamstrings rise 5 to 12, floor 12". The 5 is `_hamstringsBefore`, the table from BEFORE OI-454, not main's figure; and the advanced floor is 14 (`session_budget.dart:432`), so "advanced 5 to 12, floor 12" was wrong twice.
- **verification:** confirmed by reading the test (lines 75-90) and `session_budget.dart:429-433`; then measured: the same 24-cell probe run with main's library (12ae6db3, the cable E230; one tracked file swapped in a script that restores it byte-identical, probe copy deleted afterwards) gives Quads equal to the OI-454 tables in all 24 cells and Hamstrings 2 to 5 sets lower than now in 11 cells (intermediate bodyweight 90: 8 to 12; advanced bodyweight 90: 7 to 12 of 14; advanced home 90: 11 to 14).
- **status:** fixed (the three places state the measured figures and the right floors; the net sentence is rewritten: Hamstrings up 2 to 5 sets in 11 cells against Quads down 1 to 3 in 10).

## Finding 13 - P2 - stale snapshot figures in the diagnose doc
- **claim:** "carries the entry (180 records)" and "Nothing is committed or pushed yet".
- **status:** fixed (181 after the merge with main, each entry holding its own sha256; the state sentence names the commit, the PR, the two merges and this round).

## Finding 14 - P2 - architecture doc and board counts after the widening
- **file:line:** `docs/architecture/plan-engine-detail.md` (the OI-454 "Not reached" list), the OI-477 paragraph.
- **claim:** both still describe the pre-C2c shortfall list (5 of 12 at 90 minutes, 9 of 12 at 60, advanced bodyweight `co_group_limited`).
- **verification:** counted from the two probe logs by `node -e`: Quads short 9 and 5 on main, 11 and 7 now; Hamstrings short 12 and 7 on main, 12 and 5 now.
- **status:** fixed (a clause in the architecture doc and the counts in the OI-477 paragraph).

## Finding 15 - P2 - test hygiene in the re-pinned Quads test
- **(a)** the lever-OFF "above the old one" check still reads the pre-OI-454 Quads table: no change, it is the stricter of the two and still true, and the measured-figure ratchet above it covers the same cells.
- **(b)** the "overrides are live" test checked only `endsWith('|90')` for a label key: fixed (it also requires the key to be a real cell). Mutated once (a typo in a label key): 2 tests red, the live-override test with the direct message.
- **(c)** the label helper cannot express "now reaches its floor": no change, no override needs it, and a cell that did would need its table changed anyway.
- **(d)** the four new `cap_limited` cells had no cause check: fixed (the existing check, both leg days hold a quad compound at the per-exercise maximum, now runs for them and names the cell in its reason; it passes, sets [5, 5]). Mutated once (maximum minus one): red, naming `intermediate|bodyweight|90`.
- Helpers on a key absent from every table: the two integer helpers throw (fail closed), the label helper returns null (expects no shortfall), as main's table does.

## Finding 16 - P2 - skill bullet counts one reader too few
- **claim:** the History-reader bullet says "six more"; the review row of round 1 says seven (LAST and TRY are two files).
- **status:** fixed ("seven more", naming the two files).

## Finding 17 - P2 - main moved while the review ran
- **claim:** `origin/main` is c18a606f (PRs 228 and 229), not 12ae6db3; a merge preview is clean, with overlap in the skill file, the board and the naming glossary.
- **status:** handled in the close-out: main is merged again after the close-out commit and the delta is checked by the same record-aware sync.

## Founder triage notes
Triaged by the working session, not by the founder: no P0; round 1: all ten handled above (one P1, nine P2); delta round: all seven handled (two P1, five P2). The media upload and the migration apply were the founder's two explicit gos; nothing live had run at review time, and both ran afterwards on the final, unchanged tree (diagnose tiers 5 and 9).

## Tuning entry
- **2026-11-06** - blast-radius platform - 17 findings (10 in round 1, 7 in the delta round of 2026-11-07); 0 false_alarm (one sub-claim by a seat, that the sign-in heal zeroes the weight, was false and checked against `fieldsClearedFor`); tuning: lens 1 gained a case worth keeping in mind, a retag of a row whose stored `logging_type` is copied into history rows needs a reader sweep of the HISTORY keyed by the stored value, not only of the library; a seat's claim about runtime behaviour must be read in the code before it goes into a binding doc. The delta round added: a figure compared with a table whose label says "before X" is not a delta against main; re-measure on main with the old row (one library file swapped and restored, a scratch probe) before writing "A to B" into a binding doc, and read the floor from the band table, not from the nearest example.
