---
branch: oi532-sched-restore-swap
date: 2026-11-27
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi532-sched-restore-swap-bpass.md
---

# Plan-review record — OI-532 (a stale schedule restore undoes an unpushed day swap)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Sync restore path (L tier),
platform blast radius, so it carries a B-pass. Not catastrophic, so no Hermes.

Plan: `docs/plans/oi532-sched-restore-unpushed-swap.md`. Origin: OI-348 Landing 3d plan 3.5 (R1-2 verified the
race, R2-1/R2-2 rejected the `arranged_at_ms` guard) split it out as OI-532.

## Rounds
- **Round 1** (context-blind Sonnet, prose plan, every cite read): 9 findings, 1 P1: the swap wrote its rows
  before its marker and the restore takes no date lock, so a restore in that gap (or one whose `existingMap`
  went stale across the template awaits) still undid the swap. P2s: a push confirming during the restore's
  fetch, the guard without a local row, the Case 2 omitted-template-key confirm, a vacuous mutation and no
  push-vs-swap test, the launch order untested. All folded (mark before and after the rows, guard right
  before the put, local-row clause, Case 2 handling, T7/T8).
- **Round 2** (fresh seat, post-round-1 plan): 7 findings, 1 P1: a swap made AFTER the restore's fetch and
  pushed and cleared before its merge was still overwritten (round 1's snapshot only covered marks present at
  the fetch). P2s: the Case 2 fix only delayed the clear by one pass; T7/T9/T12 unbuildable as written. P3s:
  CAS between the rows and the second mark, token ABA, an L3 discard leaving a mark, docs and the sibling
  writer. Folded with one mechanism change: a process-local touched counter + `fetchMark` (subsumes round 1's
  snapshot), an in-flight set, a never-reused persisted token; marked Case 2 rows return false. The
  template-unassign sibling is split to OI-533 (deletion semantics).
- **Round 3** (fresh seat, narrow check of the round-2 folds): no design change except one line (never reset
  the counter on a user change). P2s: T9's single-call variant and T7 need awaited stub hooks; P3s: mutation
  (j) wording, a stuck in-flight entry if marking throws, a late clear on a closed box, the test seam's fetch
  mark. All folded; converged.

## Build notes
- The stub gained an awaited `beforeWrite[table]` hook (T7, T13). R3-1's single-call BEHAVIOURAL run was not
  built: driving `_attemptSingleCallRestore` needs an authed session and the 29-table bundle. The fetch-mark
  behaviour is T9 at the restore function; the single-call wiring is a source-order test in the same file
  (precedent `restore_readiness_prefetch_test.dart`).
- T13 added at build time: the post-rows re-mark has a test of its own (mutation n).

## B-pass
Two fresh seats on `f72863c4` (`docs/reviews/oi532-sched-restore-swap-bpass.md`): 1 P2 (a never-confirming mark
was permanent: now expires after 14 days), 1 P2 (14 mutation survivors: all now red), P3s folded (re-check of the
rows after the pre-row mark, cites, tests). Accepted.
