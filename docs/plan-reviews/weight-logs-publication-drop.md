---
branch: weight-logs-publication-drop
date: 2026-11-05
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/weight-logs-publication-drop-bpass-review.md
---

# Plan-review record - drop weight_logs from the supabase_realtime publication

Plan: `docs/plans/weight-logs-publication-drop.md`. Execution mode: inline, one worktree.

## What this is

Follow-up to PR #214 (the client Realtime subscription removal). Migration 168 drops `public.weight_logs` from
the `supabase_realtime` publication and `log-client-error` was redeployed (v21). Both ran live on 2026-11-05 with
the founder's explicit per-action go BEFORE this review; the plan states that order and the review covered the
paper trail, the exposure of old app builds and the live-state claims that can be checked from the repo.

## Rounds

Three context-blind Sonnet rounds. Round 1 (ground truth): converged, five P2s (wording, a tracked home for the
cold-start log check). Round 2 (exposure, mirror): not converged on one P1, the plan described old builds as
looping on `channelError` forever; the removed `sync_realtime.dart` shows a bounded flow (one reconnect, then
teardown, per foreground), corrected from the file. Round 3 (confirmation read of the corrected plan):
converged, four wording P2s, all folded. OI-470 tracks the post-build log check with a positive control.

## B-pass

`docs/reviews/weight-logs-publication-drop-bpass-review.md`: two P2s (an approximated `applied_at` and
repo-unverifiable live version numbers), both addressed; no P0/P1. Local gates passed at commit time; CI on the PR
is the full-suite gate.
