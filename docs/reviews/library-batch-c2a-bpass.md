---
reviewed_at: 2026-11-05T09:55:00+05:30
staged_against: 07191c744d4dfd49faa54baaae2ddac1c34982ae
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: all six triaged below; findings 2, 4 and 6 fixed in this batch, finding 1 and 3 resolve by the planned last steps, finding 5 is the founder's alias decision, finding 6 second half is a stale generated report
---

# Code Review: Batch C2a (library removals), branch library-batch-c2

Reviewed SHA 07191c74 (HEAD after the merge of `origin/main`), diff `origin/main...HEAD`, 7 commits. A fresh Sonnet reviewer with no conversation context ran all eight lenses, plus a dry-run of the generated seed SQL (`999_dryrun_seed_exercise_library.sql`, generated from HEAD into the session scratchpad, never into the repo). Every claim below was re-checked by the author against the file before triage.

## Finding 1 — P1 — asserted_fixture_value
- **file:line:** test/contracts/exercise_library_cloud_seeded_test.dart (4 tests); docs/audit/library-batch-c2a.closure.yaml C2A-7
- **claim:** 4 tests are red at HEAD because the newest seed migration on disk is still 164 (914 rows); the closure ledger cites that file as the verification of a `closed_in_commit` finding.
- **verification:** `flutter test test/contracts/exercise_library_cloud_seeded_test.dart` (ends `+102 -4`; the four are the disk-reading ones, the generator-only tests pass).
- **suggested-fix:** mint and commit the seed migration before merge, or skip the disk tests until it exists.
- **status:** accepted_by_design — the four tests are red on purpose until the migration file exists (plan step 9: mint, byte-compare with the dry-run, rehearse, founder's explicit go, apply, commit as the LAST commit). The branch is not pushed before that commit, so no CI run sees a red tree. C2A-7's verification is valid from that commit; the closure keeps C2A-8 `blocked_on_user` until then.

## Finding 2 — P2 — writer_reader_drift
- **file:line:** assets/data/exercise_library.json, E266, E267, E278, E280 (`standard_swap`)
- **claim:** all four name "Prone Lat Pull", the removed E265. E280 is E265's replacement and so pointed at the name it replaces. No Dart in `lib/` reads `standard_swap`.
- **verification:** `node -e` over the library for a `standard_swap` naming no row (13 dangling values, 4 added by this change, 9 older).
- **status:** fixed — E266 E267 E278 now name "Prone Lat Pull Hold" (the replacement), E280 is cleared; the importer's removals pass (`repointStandardSwap`, `scripts/add_library_batch_c_v15.js`) does the same on a from-scratch run, and `library_batch_c_rows_contract_test.dart` (byte-exact importer output) passes. New test `no row's standard_swap / progression_to / regression_to names a removed row` in `library_batch_c2_name_readers_test.dart`, mutated by putting the dangling value back in the library (red, restored, `cmp` identical). The 9 older dangling values are not removed rows and are left as they were.

## Finding 3 — P2 — missing_input
- **file:line:** docs/audit/library-batch-c2a.closure.yaml:9-10
- **claim:** the ledger cites `docs/plan-reviews/library-batch-c2.md` and this review file; neither existed.
- **status:** fixed — this file now exists; the plan-review record lands in its own later commit (the hash-fixed-point rule in the code-review skill, section 3).

## Finding 4 — P2 — guard_without_its_mirror
- **file:line:** scripts/seed_exercise_library.js (removals block)
- **claim:** the SQL generator builds its deactivations from the removals file alone; a removed id re-added to the library would be upserted active and then deactivated, shipping dead. The Dart seed has the mirror guard (`pruneRetired(...difference(shipped))`), the SQL generator did not.
- **verification:** copy of the library with a removed row added, generator run with `--out`.
- **status:** fixed — the generator now refuses (exit 2, names the ids). New mutation test in `exercise_library_cloud_seeded_test.dart` (a removed id added to a copy of the library, selected with the new test-only `SEED_LIBRARY_JSON` environment variable: exit 2, stderr names the id, no file written) with its mirror (the unmodified library still generates, exit 0). It passes (`+102`, the 4 red being finding 1).

## Finding 5 — P2 — writer_reader_drift
- **file:line:** assets/data/exercise_library.json G3470 `name_aliases`; scripts/library_batch_c2_removals_gen.js:45
- **claim:** "Reverse Lunge" aliases Forward Lunge, a different movement, so a stored Reverse Lunge shows Forward Lunge's cues.
- **status:** accepted — founder decision (alias policy YES, 2026-11-04, plan r4); the other three aliases are the same movement. Recorded in the diagnose doc and told to the founder at the end of the batch.

## Finding 6 — P2 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml (`seed_service.dart` entry, `line_range: 227-272`); test/plan_generator/baseline/baseline_plans.md; test/plan_generator/exercise_target_focus_review.csv
- **claim:** the range ends before the new prune's `debugPrint` (line 275); two generated reports still list removed names.
- **status:** range fixed (227-276, verified against `seed_service.dart`: `retiredLibraryIds` 238, `pruneRetired` 254, `_seedExercises` 260-275). The two reports are written only by `generate_baseline.dart` and read by nothing under `lib/`, `test/` or `scripts/`; they were not regenerated by the earlier library batches either, so they are stale snapshots, not gated state (false_alarm for the gate class, noted here).

## Lenses clean
- Lens 1: `git grep` of all 50 names over `lib/`, `supabase/functions/`, `scripts/*.dart`, `test/`, `assets/` leaves comments, tests that do not read the library, and historical migrations; every `progression_to` resolves (G1429 to G3418); no media key is on a removed id.
- Lens 2: `grep "\.functions\.invoke("` over the added lines: 0.
- Lens 3: tiers read from `docs/blast_radius.yaml`; consistent.
- Lens 4: credential-shaped literals over the added lines: 0.
- Lens 5: `unawaited(` added: 0; the second `pruneRetired` is awaited in the same `try`/`catch`; the version flags are written after both prunes.
- Lens 6: the uninjured cell recomputed independently from the fixture and the shipped library for every removed row under both pattern semantics and all tiers: 0 violations; 0 duplicate names or aliases; a shipped id can never be pruned; an install at v18 does not re-run; UUID custom rows are untouched; all 50 rows were active before, so the rollback reactivation is exact.
- Lens 7: `test/fixtures/library_c2_base_depth.json` exists with the expected shape; no kept `demo_slug` lacks a plate; the 4 deleted slugs are used by no row; `pubspec.yaml` lists the plate directory.
- Lens 8: recomputed 864 rows, 914 before, 50 remove, 16 keep, 150 rows with `demo_slug`; 0 duplicate ids; the v18 and name-reader tests are non-vacuous.
- SQL dry-run: exactly 864 tuples with 864 unique cloud uuids; 50 deactivations (plus the 7 older Batch A retirements, 57 in all) after the upsert, none overlapping a tuple; the inline rollback reactivates exactly the 50; the 3 names with apostrophes are escaped as `''`.

## Founder triage notes
Triaged in this session by the author. Nothing here is a decision that was the founder's to make, except finding 5, already decided on 2026-11-04.

## Tuning entry
- **2026-11-05** - blast-radius platform - 6 findings; 1 false_alarm (the stale generated reports half of finding 6); tuning: none. Lens 6 (mirror) found a real gap again (finding 4: the SQL generator lacked the guard the Dart seed already had), and lens 8 caught that a closure entry cited a test that is red by design until the last step; neither needs a lens change.
