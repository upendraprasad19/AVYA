---
branch: oi179-cron-dead-alert
date: 2026-11-05
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/b466a59cc4f1-review.md
hermes: accepted
hermes_report: docs/audit/2026-11-05-hermes-oi179-cron-dead-alert.md
---

# Plan-review record - OI-179, alert_cron_function_dead can never fire

Plan: `docs/plans/oi179-cron-dead-alert.md` (v4). Execution mode: inline, one worktree.

## Rounds

Two context-blind Sonnet rounds on the plan before any code.

Round 1 (ground truth): no P0, two P1, five P2. Corrected the citation of the live pruner body to migration 110
(not 109/141), required re-stating the grants, found that `latestMigrationDefining` resolves functions only, and
listed the stale 7-day text (CRON_REGISTRY rows, telegram-admin-bot comments, OI-199). All folded into plan v2.

Round 2 (design, on the revised plan): two new P1 and several P2. The SQL pin could not see the keep-set against
a live table (fixed: it empties the table inside its transaction), the extractor scope contradicted where the
thresholds live (fixed: lookbacks inside the `cron_call_log` sub-select, thresholds anywhere, MAX), the existing
`cron_job_body_reader.dart` should be reused, the mutation list had "must not redden" cases that prove nothing,
a second 7-day pruner might exist (checked live: an orphan function, no caller, filed as OI-471) and
`weekly-recalc` has no cron job (filed as OI-472). All folded into plan v3.

Founder decision (2026-11-05): retention 7 -> 10 days (option 1) with a minimal scope, which made plan v4 a strict
subset of v3: the function drop and the `weekly-recalc` exclusion became their own OIs and the guard invariant
became `threshold < min(lookback, retention)`.

Round 2 raised new material points, so the unit was re-sized rather than reviewed a third time: v4 removes two
production changes and adds none; every remaining claim was verified against the repository and the live
read-only state during the build (retention body, row counts, cron jobs, last success per function).

## B-pass

`docs/reviews/b466a59cc4f1-review.md` (fresh Sonnet, reviewed at hash 1d65664bb896, six findings, all fixed before
the commit; a lookback-equality mutant had survived 15 tests until the fix). Verdict accepted.

## Hermes pass

`docs/audit/2026-11-05-hermes-oi179-cron-dead-alert.md` (L1, L14, L22, L31, L35 in two Sonnet seats, after the B-pass
fixes): no P0 or P1; one P2 and eight P3 records, every one given a terminal state (OI-473 filed; OI-199 extended;
the rest verified or fixed). Verdict accepted.
