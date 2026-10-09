---
branch: progress-photos-pro-server-rule
date: 2026-10-08
blast_radius: catastrophic
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/cd4d17def84a-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-06-hermes-progress-photos-pro-server-rule.md
recorded_at: 2026-10-08T19:30:00+05:30
---

# Plan-review record — progress-photos-pro-server-rule (unit B1: the PRO rule for new progress photos)

Founder decisions of 2026-10-06 (six, including decision 6: INSERT only, a lapsed user may still view and delete). Plan: `docs/plans/progress-photos-pro-server-rule.md` (after round 5), live evidence E1-E29 in `docs/plans/progress-photos-pro-server-rule.evidence.md`. Blast radius `catastrophic` (the glob `supabase/migrations/*rls*.sql`), fix tier L.

## Review rounds
- **R1-R3** — plan review by fresh, context-blind seats (smaller models), each on the plan after the previous round's folds; findings folded into plan v3 (single DO block, whole-expression pins, tripwire).
- **R4** — Hermes pass, seven lens seats (`docs/audit/2026-10-06-hermes-progress-photos-pro-server-rule.md`): 0 P0, 0 P1, 2 P2, 22 P3; all defects of this unit fixed, the rest `verified_clean` with live evidence E27-E29 or filed as OI-320/321/322. Disclosure: those seats ran as Opus, before the founder's Sonnet-only rule of 2026-10-07.
- **R5** — B-pass (`docs/reviews/cd4d17def84a-review.md`, plan section 9f): five findings B1-B5, all fixed in the contract test and mutated. The seat's model is not asserted.
- **Execution:** inline, one worktree. A production always-aborting dry run, then the founder's live apply in the dashboard SQL editor on 2026-10-07 (the Claude Code classifier denied `apply_migration` as a production deploy and that was not worked around), then live-verify 30 of 30 and the arbiter 28 of 28.

## Ground truth
Live catalog read-backs and the before/after live-verify are the evidence; the draft-time sandbox was a supabase/postgres 17.6 container holding the live objects. Numbers and statements in the migration header were checked against the live catalog, not against memory.

## Reservation
`mig/154` was reserved with `scripts/mint_migration.sh` and is now consumed by `supabase/migrations/154_progress_photos_pro_insert_rls_rule.sql`; the remote reservation ref is left for the founder's cleanup (no remote branch is deleted by the session).

## Founder-owned, recorded in the ledger
S9 (the out-of-repo Telegram bot must not insert progress_photos rows), OI-320 (referral cap, a product decision), OI-321 (an Edge Function deploy). OI-322 is fixed in unit B2.
