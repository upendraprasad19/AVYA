---
reviewed_at: 2026-11-01T15:10:00+05:30
staged_against: fc7e91ff9feb75c7a3ff5c727a168565de7dd98d
blast_radius: account
reviewer: claude-sonnet-via-skill (three fresh read-only reviewers with no conversation context: A data, upload, seed, docs; B tests, gates, guard and mirror; C runtime and user-visible behaviour)
lens_set: [guard_without_its_mirror, missing_input, asserted_fixture_value, writer_reader_drift, blast_radius_mismatch, secrets_in_tree]
findings_count: 17
verdict: accepted
verdict_note: 0 P0, 0 P1, 4 P2, 13 P3 (17 distinct from 19 raw; the registry range was found by seats A and B, the version label by A and B); every finding verified by the author against the staged files before acting; 14 fixed in the batch, 1 recorded for the founder (the VIEW PLATE label), 1 already tracked (the 0551 frame memory), 1 by design (the review record is written after this file)
---

# Code Review (B-pass) — branch `library-old-rows-media` (OI-443 data step: 137 old-row animations), staged tree on base `fc7e91ff`

Severity count over the 17 distinct findings: P0 0 · P1 0 · P2 4 · P3 13.

Method note. Three fresh reviewers (Sonnet, read-only, no conversation context), each given the neutral change description, the lenses and a command allow-list (the Read, Grep and Glob tools, read-only git, node one-liners writing only into a scratch directory, no `flutter`, no `dart`, no network, no database; a full-suite run held the project). Each wrote a file with a `diagnose_stanza` first. Their PROPOSED RUNs were run by the author. Every number in the findings was re-derived by the author from the staged files before it was used: the 106 / 31 / 648 split (`rows.filter(media_slug)` by `^E\d+$` and `demo_slug`), 758 of 914 rows without a drawing, the stale M1 figures (`git grep`), the registry range (staged `seed_service.dart` lines 227 and 272 against base lines 222 and 267). One reviewer claim was corrected: seat C said the "VIEW PLATE" label is inexact for 648 rows; the door shows in the FORM & CUES panel for every exercise (`coaching_content_panel.dart:118-142`), so it is inexact for all 754 rows that have an animation.

No reviewer found a defect in the data chain: input file → table → library → stills → seed, the four parked buckets, the shape rule (66 rows, equal to the `_discarded` literal), the cloud neutrality of the three keys, or any reader of them (`resolveMedia` is the only one; no id-prefix test; 0 duplicate names across 914 rows). The change to `assets/data/exercise_library.json` is exactly three appended keys on 137 rows (777 of 777 other rows deep-equal), 753 stills match the table by sha256 and size.

## Finding 1 — P2 — asserted_fixture_value (the M1 figures stood in four living texts) (A1)
- **file:line:** `docs/operations/GO_LIVE_CHECKLIST.md:182,185`, `docs/audit/open_issues.md` OI-440 What and OI-444 What (253.55 MB, 616 files, 19 and 985 downloads, 3,102,690 bytes).
- **claim:** this change restated the same quantities in `EXERCISE_MEDIA.md` (753 files, 310.03 MB, about 16 and about 806), so the repository held two answers; the plan itself promised the OI-444 update.
- **verification:** `git grep -n -E "253[,.]?55|3,102,690" -- docs/operations docs/audit/open_issues.md`; 5e9 / 310.03e6 = 16.1 and 250e9 / 310.03e6 = 806.4.
- **status:** fixed. Each place now states 310.03 MB / 753 files / 16 / 806 and keeps the M1 figure as history where the sentence is about M1.

## Finding 2 — P2 — writer_reader_drift (the registry range for `seed_service.dart` stood five lines stale) (A2, B1: two seats)
- **file:line:** `docs/sot_registry.yaml:11479` (`line_range: 222-267`).
- **claim:** the +5 comment lines above `_exerciseLibraryVersion` moved the `retiredLibraryIds` to `_seedExercises` span to 227-272. The plan said three ranges move; the diff moved two. `check_sot_registry_parity.dart` takes a symbol only from a bare identifier or a backticked token and checks only bounds for a prose `method:`, so its PASS cannot see this.
- **verification:** `sed -n '227p;272p'` on the staged file prints the doc comment of `retiredLibraryIds` and the closing brace of `_seedExercises`; the same two lines are at 222 and 267 in base.
- **status:** fixed (`227-272`); the code-review skill gained an "Inserted-lines sub-check" so the next reviewer lists every registry entry that cites a file the diff inserts lines into.

## Finding 3 — P2 — asserted_fixture_value (the OI-443 heading and What said the data step applies the E230 retag) (A3)
- **file:line:** `docs/audit/open_issues.md` OI-443 heading and the What sentence "so the data step applies that retag ... (148)".
- **claim:** after this change 137 of the 160 pairs are in the table and E230 is deliberately not applied (plan R1; Blocked on 3; the C2 draft's carried finding 11a). The heading is what the generated OPEN_INDEX shows.
- **status:** fixed. Heading now reads "137 of the founder's 160 picks ... are in the media table; 11 are held, 10 wait on Batch C2, E230 waits on C2's seed migration, and 529 ... were never compared"; the What paragraph says the data step did NOT apply the retag and why.

## Finding 4 — P2 — asserted_fixture_value (`plate_flags.dart` named the animation-and-no-drawing set as the 617 new rows) (C1, A4)
- **file:line:** `lib/shared/widgets/exercise_plate/plate_flags.dart:34-37`.
- **claim:** the set is 648 rows: the 617 new rows that have an animation plus the 31 old rows that have an animation and no drawing (106 old rows have both). The sibling docs already said 31.
- **verification:** `rows.filter(r => 'media_slug' in r && !r.demo_slug).length` = 648; old with media and `demo_slug` 106, without 31.
- **status:** fixed (comment only: "the 617 new rows that have one and 31 old rows").

## Finding 5 — P3 — asserted_fixture_value ("the 617 new rows" read as all new rows; 12 of the 629 new rows have no animation) (A4)
- **file:line:** `docs/naming_conventions.md` (media_slug row, disable_exercise_animations row), `docs/operations/EXERCISE_MEDIA.md` (the library-fields row, the kill-switch bullet), `docs/reference/exercise-library.md`.
- **status:** fixed ("the 617 new rows that have an animation (the other 12 new rows have none)").

## Finding 6 — P3 — writer_reader_drift (the version label was v16 in some places and v17 in others; the registry description read v16-only) (A5, B6)
- **file:line:** `docs/reference/exercise-library.md` heading, `docs/sot_registry.yaml` `exercise_media_fields` description, `docs/naming_conventions.md`.
- **status:** fixed. One convention: introduced in v16 on 617 new rows, 137 old rows added in v17; the registry description now names the cumulative input and the v17 re-seed.

## Finding 7 — P3 — asserted_fixture_value (S7 of the spike findings pointed at a document that now says another largest file) (A6)
- **file:line:** `docs/audit/library-m2-spike-findings.md:26`.
- **status:** fixed (dated: 987,558 was the largest of the 616 at the 2026-10-31 reading; of the 753 mapped now it is `0551`, 999,800).

## Finding 8 — P3 — missing_input (the closure ledger cites a plan-review record that is not written yet) (A7)
- **file:line:** `docs/audit/library-old-rows-media.closure.yaml:10`.
- **status:** by design. The order is this file first (it is committed before the record, because the record cites it as `bpass_review`), then `docs/plan-reviews/library-old-rows-media.md`; `check_plan_review_record_exists.dart` enforces the record at the merge-to-main commit. Gate 40 does not resolve the key.

## Finding 9 — P3 — asserted_fixture_value (the glossary said "null `variant_family`"; the key is absent on all 66 rows) (A8)
- **file:line:** `docs/naming_conventions.md` (removal-slated pair row).
- **verification:** `variant_family absent 66`, `strict null 0`; the helper's `row['variant_family'] == null` is true for an absent key, so the rule is right and only the wording was off.
- **status:** fixed ("no `variant_family` key").

## Finding 10 — P3 — guard_without_its_mirror (a held or retag-decided pair could be released into `entries` with every rule green) (B2)
- **file:line:** `test/helpers/library_old_rows_input_checks.dart` P3 and P5.
- **claim:** P3 is a subset check (releasing stays legal) and P5 checks a flag the same author sets, so moving E027 (held: a plate-loaded T-bar station for a barbell row) or E230 (the decided retag, which needs C2's seed migration) into `entries` and rebuilding the table, library and still passed every test. The only thing between the suite and shipping the wrong picture was a person.
- **status:** fixed. Rule P7: an entry whose id is in the equipment-check record's `equipment_mismatch.rows` or `movement_mismatch.rows`, or in the picks record's `equipment_retag_decided` (12 ids), carries a non-empty `released_by`; an empty record fails closed. Six cases in `library_media_table_test.dart` (two positive, three mirrors, one fail-closed). Mutation proof (rule 21): check skipped reddened 3, empty-record guard removed reddened 1, rule made eager for every entry reddened 3 (the real-data test and both mirrors). The builder ignores `released_by`. Documented in `docs/operations/EXERCISE_MEDIA.md` section 6.

## Finding 11 — P3 — guard_without_its_mirror (the input hash covers the parked buckets too, and the test did not say why it was red) (B3)
- **file:line:** `test/contracts/library_media_table_test.dart` the hash test.
- **status:** fixed (the `expect` now carries a `reason:` that says any edit of the file, even only a parked bucket or the `_note`, changes the hash and names the rebuild command). Hashing only `entries` was rejected: it would change the builder's recorded hash for no gain, and the whole-file hash is what binds the reviewed bytes to the live upload.

## Finding 12 — P3 — asserted_fixture_value (the ledger said each of seven input mutations reddened "the real-data test and the hash test"; one of them reddened 1) (B4)
- **file:line:** `docs/audit/library-old-rows-media.closure.yaml` U1.
- **status:** fixed ("the real-data test, the hash test or both (edit_without_rebuild only the hash test)"); the same sentence on OI-443 corrected.

## Finding 13 — P3 — guard_without_its_mirror (five protections had no recorded mutation) (B5)
- **claim:** the real-row mirror in `exercise_media_fallback_chain_test.dart`, `files.keys == rows.values`, the CR-byte guard, the non-empty worst-case pool in `exercise_plate_sheet_test.dart`, and `stripOldRows`.
- **status:** fixed by running them (applied, run, restored from the index, `git diff` empty after each; ledger U12): `stripOldRows` made a no-op reddened 3; the worst-case pool emptied reddened 1; a CR byte appended to the input file reddened 1 (the hash and CR test only); an orphan file added to the table reddened 4 (including the shape test); E001 stripped of its media keys reddened 1 (the real-row mirror).

## Finding 14 — P3 — asserted_fixture_value (`plate_flags.dart` still quoted "127 artwork-less exercises") (C2)
- **verification:** 758 of 914 rows have no `demo_slug` (pinned by `exercise_plate_resolver_test.dart:80`); 127 was the v11 figure.
- **status:** fixed (the number is dropped; a count in a comment goes stale).

## Finding 15 — P3 — missing_input / user-visible copy (the FORM & CUES door label "VIEW PLATE" opens an animation) (C3)
- **file:line:** `lib/features/train/screens/active_workout/coaching_content_panel.dart:141`.
- **claim:** already inexact for the 617 new rows since Batch M2a; this release widens it to 106 old rows that used to open a real plate and 31 that opened NO DRAWING YET (754 rows). No test pins the label.
- **status:** blocked_on_user. A copy call in the Wardroom voice (rename or keep); OI-443 Blocked on (4); closure ledger `LABEL-VIEW-PLATE`.

## Finding 16 — P3 — missing_input (the new worst-case file `0551` has 54 frames and is unmeasured on a phone) (C4)
- **claim:** if a device retained every decoded frame at the 720 px clamp the ceiling is about 107 MiB against about 95 MiB for the 48-frame `3214`; UNVERIFIED (how many frames the engine keeps is not in the repository).
- **status:** already tracked, no change: OI-440 "NOT observed" names `0551` (E141, 54 frames, 999,800 bytes), S6 of the spike findings, and the closure ledger's `POST-MERGE-DEVICE-CHECK` (on a low-end phone, `0551` next to `3214`). The PR does not claim S6.

## Finding 17 — P3 — missing_input (the E102 / E103 source file names are swapped and the new record did not say so) (C5)
- **claim:** E102 Incline Push Up uses `3785-box-decline-pushup` and E103 Decline Push Up uses `0279-incline-pushup`; the reviewer looked at both stills and the pictures match OUR names, so the mapping is right. The reason sat only in `library-old-rows-equipment-check.json` (`names_vs_pictures`), so a later name-against-slug pass could "fix" two correct pairs.
- **status:** fixed in the documents the next editor reads (`EXERCISE_MEDIA.md` section 6, OI-443 What). The hashed input file was left byte-exact on purpose (any edit changes the hash the live upload is bound to and forces a full rebuild).

## Checked and clean (all three seats)
- Table totals recomputed from the staged table: 754 rows, 753 files, 310,027,946 bytes, largest `0551` 999,800, 56,477,126 new bytes, 3,785,288 bytes of stills; the input sha256 `943a0b1b…6231` equals `_meta.old_rows.sha256`; no CR byte; a copy of the importer's media stage reproduces the staged library byte for byte.
- Partition: 163 picks, 160 in the library, buckets 137 + 11 + 10 + 1 + 1, 0 ids in two buckets, 0 gif mismatches; no parked id has a table row, a library key or a still.
- Seed: the only readers of `_exerciseLibraryVersion` are the constant, its key name, the comparison and the write after `putAll`; the v16 → v17 re-seed rewrites the 285 old rows identically plus the keys on 137; plans, logs and swaps reference exercises by NAME and no name changed.
- Cloud: no `media_*` column anywhere in `backups/`, `supabase/` or the seed generator; `exercise_library_cloud_tuples_match_test.dart:114-122` pins the case.
- Secrets: no credential-shaped literal in the 2,811 added text lines; no new username path. Blast radius: the maximum tier of any touched path is `account` (nothing platform or catastrophic).
- Mutation walk by reading (seat B): eight realistic mutations of the input file all redden at least one of the 17 tests of the input group; the shape rule selects the same 66 rows as the `_discarded` literal (symmetric difference empty); six repointed tests are equal strength or stronger.
- Deferral-euphemism scan of the 22 phrases over the staged markdown additions: 0 hits (before the fix pass; re-run in the gate loop).

## UNVERIFIED (could not be checked by the reviewers; the author's state)
- The live bucket (137 uploaded, 755 objects, privacy probes, the live-verify verdict): recorded in the closure ledger U4 from the author's own run; not re-read.
- The 137 animations playing in a browser or on a phone: OI-440's post-merge check.
- The three host-only red tests of the full suite on this Windows machine (`gate_index_e2e_test.dart` em-dash codepage, `merge_scope_git_test.dart` S21 drive-letter path, `discipline_hook_local_indexes_e2e_test.dart` fixture hook): they fail identically on a clean checkout of base `fc7e91ff` (+50 passed, -3), so they are not caused by this change; CI on Linux is the gate.

## Founder triage notes
- The label "VIEW PLATE" (Finding 15) is the one open call; the rest is closed in the batch.

## Tuning entry
- **2026-11-01** - blast-radius account - 17 findings; 0 false_alarm; tuning: when a diff inserts lines into a file, list every `docs/sot_registry.yaml` entry that cites it and re-open each `line_range` by hand (the parity gate checks bounds only for a prose `method:`, so two of three seats found a stale range the gate called PASS), and when a count changes grep the OLD figures across `docs/operations/` and the board rather than only the files the plan names (added to the code-review skill as an "Inserted-lines sub-check"); for a new guard ask whether the thing it protects can be released with every rule green (seat B's P7), and run the mutation for every protection the first pass left unrecorded instead of listing it.
