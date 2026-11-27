---
reviewed_at: 2026-11-27
staged_against: 0da42833a8030b3dba8c7214acbad0f532f323da
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: pending
verdict_note: all six fixed by the author; not triaged by the founder (advisory at account tier)
---

# Code Review — media-three-adds (PR 359)

One fresh, context-blind seat. No P0 or P1; no functional defect found in the three rows, the builder, rule P8, table leg (g)
or the seed bump.

**Base:** the reviewed head was 4 commits behind `origin/main` (skill step 0b asks for a sync first). The author did not sync
before dispatch: a trial merge (`git merge-tree`) was clean and a sync would have cost another CI cycle. The branch is synced
after the fixes, before any merge.

## Finding 1 — P2 — asserted_fixture_value
- **file:line:** docs/operations/GO_LIVE_CHECKLIST.md:184
- **claim:** the bucket size and object count did not include the three uploaded files (312.96 MB, 761 animations by the records).
- **verification:** 311,867,164 + 1,093,650 = 312,960,814
- **status:** accepted — fixed

## Finding 2 — P3 — asserted_fixture_value
- **file:line:** EXERCISE_MEDIA.md, exercise-library.md, naming_conventions.md
- **claim:** "the other 12 new rows have none" is 21 (642 non-E rows, 621 with media); wrong before this batch too.
- **verification:** python count over exercise_library.json
- **status:** accepted — fixed

## Finding 3 — P3 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml seed_service.dart range 309-354
- **claim:** not moved with the three inserted lines and short of `_seedExercises`.
- **verification:** grep pruneRetired / _seedExercises in seed_service.dart
- **status:** accepted — fixed (327-377)

## Finding 4 — P3 — writer_reader_drift
- **file:line:** plate_flags.dart:35-36, naming_conventions.md, EXERCISE_MEDIA.md:130 and :134, exercise-library.md, OI-443
- **claim:** stale or garbled counts and wording (31/106 old rows, 11 held, missing 9001 and repicks mentions).
- **verification:** python counts; git grep of the old figures
- **status:** accepted — fixed

## Finding 5 — P3 — asserted_fixture_value
- **file:line:** library_seed_v20..v24 MIRROR titles, v28 upgrade title
- **claim:** titles still named v28 while the bodies expect 29.
- **verification:** grep "(v28, OI-523)"
- **status:** accepted — fixed

## Finding 6 — P3 — asserted_fixture_value
- **file:line:** EXERCISE_MEDIA.md section 3, GO_LIVE_CHECKLIST.md:187
- **claim:** the two download quotients used different rounding.
- **verification:** 5e9/312506374 = 16.00; 250e9/312506374 = 799.98
- **status:** accepted — fixed (about 16, about 800)

## Reviewer's checks and gaps
Seat ran the media table, v29, builder and seed tests (161 + 47 passed), the builder, importer and stills `--check` modes, and
matched the three files' hashes. Clean: function_exception_swallow, unawaited_no_error_sink, secrets_in_tree,
blast_radius_mismatch, guard_without_its_mirror (no hole affecting shipped data). Not checked by the seat: the live bucket, any
device or in-app playback, whether the pictures match, mutations, plan-generator tests. After the fixes the author reran the
library, media and stills tests: 737 passed.

## Founder triage notes

## Tuning entry
- **2026-11-27** - blast-radius account - 6 findings; 0 false_alarm; tuning: none.
