---
branch: media-two-new-two-retag
date: 2026-11-28
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/media-two-new-two-retag-bpass.md
---

# Plan-review record — library v30 (two new exercises, two retags, four animations)

Keystone record for the 4.12 merge gate (`check_plan_review_record_exists.dart`). Platform tier, so it carries a B-pass.
Not catastrophic, so no Hermes. Plan: `docs/plans/2026-11-28-media-two-new-two-retag.md`. Diagnose: c41a7e.

## Rounds
- **Round 1** (context-blind Sonnet): the planned step order would have shipped both new rows without injury tags or
  media (the builders only see rows that already exist); missed expected reds, count pins, the tuples-test sandbox and
  the blast-radius globs for the cloud records. Folded into the plan.
- **Round 2** (context-blind Sonnet, on the post-round-1 plan): ran the corrected order on a copy; wrong script flags,
  missed injury-recheck pins, the re-record rule extended to inline pins, expected reds named by title. Folded; converged.

## After the rounds
- The first CI run showed one behaviour change: with E027 machine-only, a basic_gym advanced repeat week put Cable Low
  Seated Row on two days. Founder decision (2026-11-28, "add it to rotation"): G0574 Landmine T-Bar Row joins the core
  list at intermediate and advanced and carries `same_movement_as: E027`. This addendum had no new plan round; the
  B-pass reviewed it with the rest of the diff.
- Measured effect on generated plans: the table "Plan snapshots and pins re-recorded for library v30" in diagnose c41a7e.

## Departure
No full suite ran locally (a local library run was too slow on the Windows laptop and was stopped). The base is main's
green CI at `d2d92832`; the after state is PR CI.

## Live steps, each needing the founder's go
Storage upload of four objects; the cloud reseed (`Destructive?: yes`, draft in `test/sql/`; no Supabase-branch or
local-docker dry run is available, a departure from `supabase/migrations/CLAUDE.md`; applying it before the merge is a
second departure); the merge.
