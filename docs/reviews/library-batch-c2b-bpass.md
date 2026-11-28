---
reviewed_at: 2026-11-05T19:40:00+05:30
staged_against: library-batch-c2b (staged tree, pre-commit and full suite green apart from the by-design migration-window red and the Windows baseline)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh agent, no conversation context)
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
---

# Code Review: Library Batch C2b (the four twins and the six twin_pending removals)

Plan `docs/plans/2026-11-05-library-batch-c2b-twins.md`, diagnose `docs/diagnoses/2026-11-05-library-batch-c2b-twins-b2c7e4.md`. The reviewer read the staged diff, ran the seed generator to a scratch directory, ran `repointStandardSwap` on probe inputs and queried live cloud with SELECT only. No P0, no P1.

## Finding 1 - P2 - missing_input / ordering
- **file:line:** `docs/diagnoses/2026-11-05-library-batch-c2b-twins-b2c7e4.md` tier 9, `assets/exercise_stills`, `scripts/data/library_media_v16.json`
- **claim:** the library, media table and stills carry `media_slug` for G1368, G1489, G2567 and G0474, but the private bucket holds 755 objects and none for these four (`select name from storage.objects where bucket_id='exercise-media' and name like '%1368%'` and the other three return no row). The diagnose doc spoke of the upload in the present tense.
- **suggested-fix:** upload and `--verify --only` before any build that carries library v19; reword tier 9.
- **status:** fixed (diagnose tier 9 now states the ordering rule; the upload is founder go 1 in plan Task 6).

## Finding 2 - P2 - asserted_fixture_value / guard_without_its_mirror
- **file:line:** `test/fixtures/library_c2b_twin_rows.json` `_meta.note`, `scripts/library_batch_c2_removals_gen.js` (`twin_fixture_sha256`)
- **claim:** the note named `library_c2b_twin_fixture_test.dart`, which does not exist, and the recorded sha256 of the fixture was read by no test.
- **suggested-fix:** correct the note; assert the sha256 in `library_depth_rule_test.dart`.
- **status:** fixed (note corrected, test added; mutated: one edited character in the fixture without regeneration reddens it).

## Finding 3 - P2 - guard_without_its_mirror
- **file:line:** `scripts/seed_exercise_library.js` (`ownTwinIds`, the header, the rollback)
- **claim:** twins were inferred as every replacement of a `c2b` removal. A later batch whose replacement already ships (C2a's E144 to G3470) would get a rollback line that deactivates a live row.
- **suggested-fix:** an explicit flag.
- **status:** fixed (the removals generator emits `replacement_new: true` for the six, the seed generator and its tests derive the twins from it and refuse a flagged twin that is not in the library; the file test allows the flag only on a `c2b` removal with a replacement and pins the four twin ids; mutated: flag deleted from E179 reddens two tests).

## Finding 4 - P2 - asserted_fixture_value
- **file:line:** `test/contracts/core_list_pool_behavioral_test.dart:31`
- **claim:** `_skillIds` still listed E101 (C2a) and E179 (C2b), so the skill-row check never covered G0474, the only new `calisthenics_skill` row. Production is safe: the selector excludes skill rows by discipline.
- **suggested-fix:** replace E179 with G0474.
- **status:** fixed (list corrected; a data correction with no behavioural proof of its own, said so in the diagnose doc).

## Finding 5 - P2 - writer_reader_drift
- **file:line:** `lib/core/services/seed_service.dart:270-278`
- **claim:** between `putAll` and the prunes an upgrading install briefly holds both E084 and G1368 named "Ankle Circles" (and three more same-name pairs), and `getByExactName` returns the first key, the stale E row.
- **verification:** the window is a few milliseconds inside one awaited seed on app start; after the prune every pair and both aliases resolve to the twins (asserted by `library_seed_v19_upgrade_behavioral_test.dart`).
- **status:** accepted, no code change (recorded in the diagnose doc).

## Verified clean (attacked, not broken)
- Generated SQL: the INSERT precedes every UPDATE, four cue-copy statements (E084 E111 E169 E179), two plain (E211 E162), rollback reactivates the six and deactivates the four twins.
- `repointStandardSwap`: name-form, id-form, no-replacement, self-replacement, untouched id and non-string all behave; E043 reads G1489; nine other dangling `standard_swap` names pre-date this batch.
- Frozen TWIN tags equal the base rows' tags; no row references any of the six ids; no duplicate name or alias across 862 rows; removals file 66 entries, 56 remove (50 c2a, 6 c2b), 10 keep.
- Counts recomputed from the data: 862, 633, 149/147/133/280, 757/758 (621 G/N + 137 E), 229, golden 8 changed.
- No secrets in the diff; no Edge Function or schema change.

## Founder triage notes
Triaged by the working session, not by the founder: no P0 or P1, all five P2 handled above. The founder is told in the batch summary; the media upload and the migration apply remain the founder's two explicit gos.

## Tuning entry
- **2026-11-05** - blast-radius platform - 5 findings; 0 false_alarm; tuning: none (the five were a missing live step, an unread recorded hash, a twin inferred rather than flagged, a stale id list and an accepted seed-window; each is covered by an existing lens).
