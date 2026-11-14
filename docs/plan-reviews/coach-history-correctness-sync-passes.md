---
branch: coach-history-correctness-sync-passes
date: 2026-10-06
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-history-correctness-sync-passes-bpass.md
---

# Plan-review record — L1a-3 exercise-log skip index: merge, don't overwrite; restore records what it wrote (`coach-history-correctness-sync-passes`)

Plan: `docs/plans/coach-history-correctness-sync-passes.md` (v3). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L1). Defects D5a (overlapping passes overwrite each other's skip-index confirmations) and D2e (restored exercise logs are pushed back once). Neither loses data; both cost redundant uploads.

`bpass: accepted` (2026-10-09, `docs/reviews/coach-history-correctness-sync-passes-bpass.md`): two fresh context-blind reviewers on commit c73dded9, 10 findings, all fixed or recorded.

## Lineage and rounds

- The units began inside L1a-2 as U6 (a `SerialSlot` with timeouts) and U2(e) (restore fingerprints behind that slot) and were reviewed there in R3–R7 (`docs/plans/coach-history-correctness-client.md` §8–§14). Each of R5, R6 and R7 found new P1s in the slot/timeout machinery, so they were split out (§4.12.1).
- **R8** (v1, slot design): three P1s (orphaned `whenComplete` future reaching the app zone; an unbounded failure report wedging the slot; key starvation under the timeout cap).
- **R9** (v2, redesign: merge-on-commit, no slot): **converged**. Two P2s applied in v3: deltas defined as pushed-and-confirmed keys (never skipped keys), which also preserves a `sync_epoch` `clearAll` during launch restore; the withdrawal propagated to the sibling plans.

`review_rounds: 2` counts the rounds on this unit's own lineage (R8 on v1, R9 on v2 — review #2 ran on the post-review-#1 design). The earlier R3–R7 rounds are in L1a-2's record.

## Ground truth verified (coordinator + reviewers, read-only)

`SyncSkipIndex` snapshot at construction (`sync_skip_index.dart:131`), whole-map `commit` (`:270`), skip returns true (`:217`), one `recordConfirmed` caller (plans, `sync_workout.dart:1455`), `clearAll` during launch restore (`sync_service.dart:1735`), no domain relies on the whole-map write except through prune/forget, Hive `put` updates memory before its disk await (a synchronous read-merge-write cannot interleave).

## Founder decisions (2026-10-06)

The late-upload residual is accepted under "last sync or write wins"; the late-delete case follows the corrected L1a-2 §10 decision ("newest action wins").

## §4.6

No flag for M1 (the whole-map write is the defect; identical outcome for a single pass); M2 sits under L1a-2's restore switch `disable_exlog_restore_dedupe`.
