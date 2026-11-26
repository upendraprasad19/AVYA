---
branch: oi348-landing3d
date: 2026-11-26
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/oi348-landing3d-bpass.md
---

# Plan-review record — OI-348 Landing 3d (P3: rescue a missed workout into today)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform tier
(`day_swap_rules.dart`, `streak_progress_service.dart`, `user_repository.dart`), so it carries a B-pass. Not
catastrophic, so no Hermes.

Plan: `docs/plans/oi348-landing3d.md`. Founder: P3 on the 22 Nov walk of AAB +50 (decided in principle that day);
the four detail calls locked 26 Nov (partner = today only on a rest day, same week; the old day shows MOVED and
counts as rest; a freeze spent on it is refunded; the rescue spends the weekly swap). It amends day-swapper spec
decision 4 and §5.2 rule 2.

## Rounds
- **Round 1** (context-blind Sonnet, prose plan, every cite read): 10 findings, 2 P1: the merge raised a side that
  never debited the spend (a free extra freeze), and `_restoreScheduledWorkouts` takes the cloud status over an
  unpushed swap (the plan had claimed the plan-bundle merge L1/L3 covered it). P2s: hybrid host, no reckon after a
  rescue, refund not atomic with the swap, free cap, coach tool path, test teeth, `weekStates` cost, docs. All
  folded ("holds D" rule, true-rest host, coach origin off, derived idempotent refund + rollover caller, reckon,
  one `datesWithExerciseLogs` pass).
- **Round 2** (fresh seat, post-round-1 plan): 9 findings, 3 P1: the restore guard re-adds `template_id` on
  template days and is permanent per row (`arranged_at_ms` is carried forward), and the merge proof rested on
  hand-picked states. Per CLAUDE.md §4.12.1 the unit was SPLIT: the per-row restore race is pre-existing for EVERY
  swap and is OI-532 (filed in this branch with the evidence). Folded: the durable `rescued_into` row mark (the
  row shape is reachable without a rescue), the current-week bound on the refund, `preview(origin:)`, sequence
  tests over every two-device interleaving.
- **Round 3** (fresh seat, narrow check of the round-2 folds): one P1 in a TEST claim (MS1's stock-minus-spends
  bound is false on main itself), four P2 (`rescued_into` must be a `markerKeys` member and the refund must also
  require `is_swapped`, since hold / copy-week copy rows; `istMondayKey` takes a DateTime; the confirm sheet passes
  its own origin; a restore that undoes a rescue keeps the refund). All folded as plan-text / test-spec fixes; no
  change to the converged mechanism. Converged.

## Ground truth
Every cite in plan section 2 was re-read on main `8cd4556f` by the author and by each round's reviewer; the
restore merge (`sync_workout.dart:2611`, `:2810`, `:2860`), the cloud column list
(`backups/live_schema_columns.json`), the RPC body (migration 115) and the merge callers were read in full.

## Build notes
- B1: the coach card reads only `preview.allowance` and `preview.warning` (never the refusal), so the coach-origin
  preview cannot show a different answer there; the planned card test (mutation n) had nothing to catch and was
  dropped; the argument is kept for consistency (diagnose b3f7d2, residue).
- B2: the grant carry counts NET spends (a refunded date is not a spend), found while writing M8; counting the
  plain date alone under-refunded.

## B-pass
Pending: `/code-review` on the branch diff before the merge.
