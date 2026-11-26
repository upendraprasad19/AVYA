---
branch: services-telemetry-pair-row
date: 2026-09-30
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — telemetry-pair pitfall row lands in the services docs (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `account`, COMPUTED** by `blast_radius_from_diff.dart` in BOTH modes (real paths as args,
and the staged set on stdin): `lib/core/services/CLAUDE.md` + `docs/architecture/services-detail.md`
→ `account`. No `bpass` is required below `platform`.

## What this branch is

Documentation only: no code, schema, Edge Function or test. One pitfall row that documents a bug
class whose FIX already shipped (`b2baab45`, diagnose `f7b2c9`): a caller-level
`ErrorTelemetry.recordNonFatal` in the same catch block as a `_reportSyncFailure` posts the same
failure to `client_errors` twice unless it passes `skipServerPost: true`. The row had been staged
in the primary worktree against the pre-lean-down `lib/core/services/CLAUDE.md`; the lean-down
(`dd966b5c`) restructured that file, so the staged hunk no longer applied and the row existed
nowhere on `main`. It lands as a condensed row in the nested CLAUDE.md and the full row as an
"Added" section of `services-detail.md`.

## Rounds

1. **Round 1 (context-blind, ground-truth against code).** No blockers. Found two imprecisions,
   both verified by the coordinator against `test/sync/sync_telemetry_test.dart` before acting:
   "missed 87 of 87 pairs" was stale and overstated (87 at fix time, pinned at 75 now; a
   single-file grep sees ~13), and "immediately preceding" understated the rule (the sweep test
   pairs to the end of the brace-matched enclosing block). Both rows reworded.
2. **Round 2 (on the corrected rows).** No blockers. Found one real inconsistency and four
   wording points, all fixed in this branch: the file header said everything there was moved
   VERBATIM (now excepts "Added" sections); the provenance sentence read as a verified claim
   (now neutral); "8 of the 9 files" qualified "at fix time"; the comment length (583) is not
   reproducible from current code (now "~570-580"); "~13 pairs" is really ~13 `H-42` hits.
   The reviewer independently replicated the sweep test's 75 and found no real pair missing
   `skipServerPost: true` and no case where the rule would wrongly force it.

## Ground truth verified (not taken from prose)

- `skipServerPost` default, the `_reportSyncFailure` POST and the sole-writer claim, the 75 pin,
  the existence of the diagnose file, the test and `loadSyncServiceSource()`.
- `check_context_artifact_budget.dart` passes (13 within band); no gate or test parses these rows.
- Tests: none run for this batch, by design (docs only); the pre-commit gate loop runs at commit,
  pre-push analyze and CI run on push and merge.
