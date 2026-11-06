---
branch: ops-alerting-batch-b
date: 2026-09-26
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3a9abffad52f-review.md
---

# Plan-review record — batch B1: restore nightly retention (migration 144)

Keystone record for the §4.12 merge gate. Platform tier (migration without
SECURITY DEFINER, classified on the written file) ⇒ ×2 review + B-pass; no Hermes.
Plan: `docs/superpowers/plans/2026-09-26-ops-alerting-batch-b.md`. Diagnose `d6b2f9`.

## Round 1 (context-blind, live-verified) — not converged, 1 material

- **F1 (P2, material):** the contract test's `$$`-only regex was blind to tagged
  dollar quotes — the repo's majority style for cron commands (`$job$` 24,
  `$cron$` 12), including 121, which created these very jobs. Fixed: tag-aware
  backreference regex + a synthetic `$job$` case; mutation (untagged regex) → 1 red.
- F2–F9 (P3, mechanical / hardening): exclusion pinned inside the alert's
  `cron_call_log` subquery; exclusion tied to the trigger-dispatched roster;
  `weekly-recalc` recorded as latent; wording (two added lines; libpq implicit
  transaction with `cron.use_background_workers=off`); registry jobids/columns;
  deadline wording; measured first-prune deltas; dated post-apply verification.
- Verified true live: pg_cron 1.6.4; jobid 41 5/5 failed; pre-141 jobs 15/15
  succeeded as single statements; alter_job signature; exclusion hides nothing.

## Round 2 (on the hardened plan) — converged, 0 material

- Regex probe over all 149 `.sql` files vs a real SQL lexer: 0 differences; `$1`
  cannot open a body. 144's alert body minus its 2 added lines has md5
  `1cc8a0fd…`, identical to live jobid 32.
- **F1 (P2, mechanical, acted on):** `weekly-recap-ready` (weekly; one success row,
  09-20 14:30) can trip a false critical at **2026-09-29 06:47 UTC** if its 09-27
  run leaves no success row and nothing prunes ⇒ apply target moved to **before
  2026-09-29 03:30 UTC**; header sentence "correct even if retention breaks" narrowed.
- F2/F3 (P3): span test now uses the LAST `FROM public.cron_call_log` before
  `GROUP BY` and requires an `AND` predicate; roster parse counts every quoted token.
  Mutations: `OR` predicate → 2 red; roster entry sharing a line → 1 red.
- F4/F5: stale counts corrected; Gate 31 input A cannot see the restored jobs —
  `backups/live_cron_jobs.json` regenerated in the apply commit is what does.

## B-pass (`docs/reviews/3a9abffad52f-review.md`) — accepted

1 finding (P3): rollback comment used a quoted `cron.unschedule('name')`; fixed to
the unquoted OI-193 form. Reviewer independently re-ran the guard mutations (2 and 2
red). Conduct note recorded in the code-review skill's tuning history (live writes
inside BEGIN…ROLLBACK against a read-only brief; verified nothing committed).

## Ground truth

Every fact in the plan re-derived live on project `dedsavbjuwgarrhphgnl` by the
coordinator and by both rounds independently; see the diagnose doc's
`touched_layers_checked`.
