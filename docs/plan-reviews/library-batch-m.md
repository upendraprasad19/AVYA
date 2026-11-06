---
branch: library-batch-m
date: 2026-10-27
blast_radius: platform
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/library-batch-m-bpass.md
---

# Plan-review record — Batch M1: media data and storage for the exercise-library animations (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`.** Computed over the plan's file list (`docs/plans/2026-10-27-library-batch-m1-media-data.md`, "Blast radius"): the Storage-bucket migration is `supabase/migrations/*` (`platform`; its name does not contain `rls`, so the catastrophic RLS rule does not match, a call the B-pass raised as finding 11 and the founder settled at go (a) on 2026-10-27: "Keep as platform"); `assets/data/exercise_library.json`, `scripts/upload_exercise_media.js` and `scripts/data/library_media_v16.json` are `account` (two new rules above `scripts/**` in `docs/blast_radius.yaml`); `lib/core/services/seed_service.dart` is `account`.

## Plan
`docs/plans/2026-10-27-library-batch-m1-media-data.md` (r6, FINAL) implements the media half of the exercise-library programme (spec `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md`). The app side (M2), the intake tool (M1c) and the picture check of the 522 unrecorded rows (M1b, OI-437) are separate board entries.

## Review rounds (context-blind Sonnet reviewers; the author re-ran the load-bearing numbers)

1. **Round 1** (two lenses, plan r1): 18 distinct P1 (the picture check dominated). Applied in r2.
2. **Round 2** (on the hardened r2): 4 P1.
3. **Round 3** (on r3): 3 P1, two of them in the intake / table / upload join. **Split under §4.12.1:** the intake, the x-form and the swap cluster were cut to M1c; M1 kept the data, the storage and the upload tool.
4. **Round 4** (two lenses, on r4): both reviewers `converged`, 0 P0 / 0 P1 (A: 14 P2 + 5 mechanical; B: 14 P2 + 7 mechanical). Folded into r5.
5. **Delta rounds 5, 6, 7 on the founder requirement** ("only users who have installed and logged in should be having access to the assets. no one else."), which made the bucket PRIVATE with one read policy for a logged-in, non-anonymous account (r6): delta 1 (2 P1: the probe design and the migration pin), delta 2 (1 P1: the "unscoped" wrong policy could not redden its leg), delta 3 (the probe block only): converged, 0 P0 / 0 P1.

The unit was split once (round 3) and the privacy change went through three narrow delta rounds rather than a rewrite, so §4.12.1's "split rather than keep reviewing" was applied and the converged piece is the smallest that ships the data and the storage.

## Ground truth
Every count in the plan was re-run by the author against the committed table and the library on disk, and again by reviewer B of the B-pass against the founder's folder (616 animations and 616 thumbnails, every sha256 and size equal to the table): 617 rows, 616 files, 253,550,820 bytes, largest 987,558, 914 library rows of which 617 carry the three media keys last and in order, and with the keys stripped the library equals `origin/main` row by row. The live project was read before and after each live action (bucket absent, then the bucket and its one policy, then 618 objects and 258,172,324 bytes in storage), and `--verify` matched all 616 objects to the table by length and sha256.

## Execution evidence
Commits on `library-batch-m`, in order, are listed in `docs/audit/library-batch-m1.closure.yaml`. Full `flutter test` on the founder's Windows machine: 12,000 passed, 35 skipped, 3 failed, all three Windows-only and untouched by the batch (OI-415 x2, OI-446); CI on the pull request is the full-suite source of truth and was green on `ee7152d7` (Analyze, Audit Gates, Deno, Build Check, four unit-test shards) after one real fix found by its first run. Whole-project `flutter analyze --no-fatal-infos`: 0 warnings, 0 errors. Every new protection was neutered once and watched red (the tallies are in the diagnose doc). Live actions, each on its own founder go in chat: migration 165 applied after a rehearsal (the role probe passes; five wrong policies each turn it red), the canary, then the bulk upload of 616 files (uploaded 616, failed 0); the role probe passes again with the files in place.

## B-pass
Two fresh reviewers plus three fresh delta reviewers: 62 findings (0 P0, 3 P1, 27 P2, 32 P3), all verified by the author before acting, 61 fixed in the batch and 1 a founder decision (the migration tier, settled at go (a)). Verdict `accepted`; file `docs/reviews/library-batch-m-bpass.md` carries the findings and its own `## Tuning entry`.
