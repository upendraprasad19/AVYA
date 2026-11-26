---
reviewed_at: 2026-11-10T12:30:00+05:30
staged_against: generator-step1-s1b3 staged tree (50 files) vs origin/main 01ed781c
blast_radius: platform
reviewer: two fresh context-blind Sonnet seats (adversarial B-pass; seat A the importer, media builder and injury builder, seat B the seed, the cloud generator and migration 175)
lens_set: [writer_reader_drift, guard_without_its_mirror, self_inclusion, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
---

# Code Review (B-pass) — Library Batch S1b-3, E053 Donkey Calf Raise merged into G1373 (`generator-step1-s1b3`)

Two fresh, context-blind Sonnet seats reviewed the staged diff read-only. The commands they could run were listed
exhaustively: no `dart run scripts/*`, no database statement. Seat A ran `node scripts/add_library_batch_c_v15.js --check`
(byte-identical) and eight test files (198 pass). Seat B rebuilt the v23 library in Python and matched the digest pin
`d858d26b…`. It checked the rollback's E053 cues byte for byte against migration 174 line 83 and ran seven contract
files (67 pass).

**Verdict: accepted.** No P0 or P1. One P2 (stale document numbers) and seven P3. All eight are fixed in this batch.

## Finding 1 — P2 — asserted_fixture_value, document drift (seat A)
- **file:line:** docs/operations/EXERCISE_MEDIA.md:50, :52
- **claim:** The batch updated the "Files mapped" row to 757 / 311,412,724 bytes, but the rows below it still said
  311.87 MB per full download and "about 801" downloads on Pro. GO_LIVE 5.8 says 802.
- **verification:** `grep -nE "311\.87|801" docs/operations/EXERCISE_MEDIA.md`
- **status:** fixed. The rows now say 311.41 MB and about 802 (250,000 / 311.41).

## Finding 2 — P3 — asserted_fixture_value (seat A)
- **file:line:** test/contracts/exercise_stills_bundle_test.dart:6
- **claim:** The comment still gave the old byte total 3,808,628. The current total is 3,802,202 (E053's still was 6,426 bytes).
- **verification:** `jq '[.files[]|.thumb_bytes]|add' scripts/data/library_media_v16.json`
- **status:** fixed.

## Finding 3 — P3 — guard_without_its_mirror (seat A)
- **file:line:** scripts/build_library_media_v16.js:196-206, test/scripts/library_media_builder_test.dart
- **claim:** "Drop only a slug that lost its LAST row" has a mirror that no test covered: a pruned row whose slug a
  surviving twin still maps. Every `--drop-unmapped` test removed the unique-slug G6000, so a mutant that dropped the
  slug of any pruned row would have passed all five tests. The code itself was correct.
- **verification:** `jq -r '.rows|to_entries|group_by(.value)|map(select(length>1))|.[]|map(.key)|join(",")' scripts/data/library_media_v16.json` (G3643,N06)
- **status:** fixed. A new test removes G3643 alone and expects N06 to keep `3643-farmer-s-walk`, active, with its
  still present. The mutant (lost = slugs of pruned rows, ignoring `after`) turns that test red (1 test).

## Finding 4 — P3 — guard_without_its_mirror (seat A)
- **file:line:** scripts/add_library_batch_c_v15.js readMerges
- **claim:** A chained record (A into B, then B into C) would drop B after it took A's alias and merged_ids, and both
  would be lost silently. No refusal existed. The current one-row record cannot trigger it.
- **status:** fixed. `readMerges` now refuses an `into` that is another record row's `id`. Test (e) adds the chain
  in both orders. The mutant (refusal off) turns test (e) red (1 test).

## Finding 5 — P3 — document drift (seat A, pre-existing)
- **file:line:** docs/operations/EXERCISE_MEDIA.md:16
- **claim:** The page said `_exerciseLibraryVersion = 20`; the code is at 24.
- **status:** fixed.

## Finding 6 — P3 — record not yet written (seat B)
- **file:line:** docs/audit/library-batch-s1b3.closure.yaml:5
- **claim:** The ledger cites `docs/plan-reviews/generator-step1-s1b3.md`, which did not exist yet.
- **status:** fixed. The record is written alongside this review. The ledger's "(uncommitted)" placeholders are
  stamped with the commit SHA, as in S1b-2.

## Finding 7 — P3 — diagnose-doc citations (seat B)
- **file:line:** docs/diagnoses/2026-11-10-library-batch-s1b3-retire-donkey-calf-raise-c3e8f1.md (writers, readers)
- **claim:** The importer writer was cited at 328 (`const MERGES`) and getFormCues at line 1.
- **status:** fixed. The citations are now 348 (`applyMerges`) and 67 (the exact `ilike` name query).

## Finding 8 — P3 — registry range ends mid-method (seat B, pre-existing shape)
- **file:line:** docs/sot_registry.yaml (seed_service.dart `line_range: 271-312`)
- **claim:** Line 312 sits inside the `catch` of `_seedExercises`.
- **status:** fixed. The range is now 271-316, the method's closing brace. `check_sot_registry_parity` passes.
  The seat also noted a stale test title in `exercise_library_schema_contract_test.dart` ("285 rows … 7 retired in
  v12" on a test asserting 870); it is retitled.

## Clean lenses (summary)
**Seat A.**
- Every reader of `merged_ids` / `name_aliases`: `seed_service`, `exercise_repository`, the swap sheet and the picker sheet. No Edge Function reads `merged_ids`. All of them handle a SOURCE-built row carrying the two keys.
- No E053 residue anywhere: library, media table, old-rows input, `standard_swap`, ladder.
- Every refusal and its mirror. The one gap is Finding 3.
- The importer is idempotent on its own output.
- The FROZEN_ORIGINALS from-scratch rebuild passes.
- Missing-input checks: the fixture, the two records, and the old-rows sha.
- Twelve recomputed counts all match.

**Seat B.**
- Migration 175 against 174: the forward UPDATE touches only is_active, coaching_cues and common_mistakes. The rollback restores exactly those, plus G1373 `name_aliases = NULL` (its 174 value). The migration is idempotent.
- `arrayLiterals` handles `''` escapes and `ARRAY[` inside quotes.
- `ownMerged` leaves Batch A's seven pairs alone.
- Generating 176 from 175 later ignores 175's commented rollback.
- Every `exerciseBox.get(id)` caller degrades on a miss.
- getFormCues has no is_active filter, so an inactive E053 answers with G1373's cues.
- The v23 digest and every count were recomputed.

## Founder triage notes
None needed: no finding above P2, and the one P2 was a document number.

## Tuning entry
- **2026-11-10** - blast-radius platform - 8 findings; 0 false_alarm; tuning: none. The seat split (data pipeline / seed and cloud path) held again. Seat A's twin-slug mirror came from grouping the real table by slug, the lens-6 "fourth question" (do TWIN rows agree?) used as a test-coverage probe; worth asking for whenever a guard is keyed on "the last row".
