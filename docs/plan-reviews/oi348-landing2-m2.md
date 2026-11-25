---
branch: oi348-landing2-m2
date: 2026-11-25
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d3a7572413ed-review.md
hermes: accepted
hermes_report: docs/audit/2026-11-25-hermes-oi348-landing2-m2.md
---

# Plan-review record — OI-348 Landing 2 PR C (B2 M2, migration 189)

Plan: `docs/plans/oi348-walk-fixes-landing2.md`, Unit B2 step 2 (M2), v4 CONVERGED. M2 was part of
the B2 unit reviewed in the plan's three rounds (record for PR B:
`docs/plan-reviews/oi348-landing2-referral.md`): round 2 moved M2 into its own PR C (a migration
cannot ride without its ledger row, written only at apply) and required the web build carrying the
RPC to be live first (Vercel READY + `main.dart.js` grep); round 3 converged. PR C implements that
step as written: drop the INSERT policy, REVOKE ALL from PUBLIC/anon/authenticated, GRANT SELECT to
authenticated, a self-check DO block (the migration 160 pattern), an inline rollback.

## Ground truth verified (2026-11-25, live, read-only)
Precondition: PR B merged (main `a0a7037c`), Vercel production for it READY, live `main.dart.js`
contains `issue_referral_code`. `referral_codes`: relacl anon/authenticated/service_role/postgres
`arwdDxtm` (grantor postgres), no column ACLs, owner postgres, RLS on and not forced, policies SELECT
own + INSERT own, 3 rows; the only function naming the table is `issue_referral_code()` (SECURITY
DEFINER, owner postgres); no view, trigger, cron job or publication. Readers: the client restore read
(authenticated, SELECT kept), `redeem-referral` and `restore-user-snapshot` (service role).

## Execution
Inline, worktree `oi348-landing2-m2` (§4.12.7). Catastrophic tier by content: staged B-pass + Hermes +
local full suite; migration 189 applied only after both accepted and the founder go ('Apply 189 now',
2026-11-25), version 20261125023144, post-apply live verify 12/12.

## B-pass
`docs/reviews/d3a7572413ed-review.md`: two context-blind Sonnet seats (A SQL, B pin test + docs +
fallout). 7 findings (1 P2, 6 P3), all fixed and re-proven (live self-check mutants, pin mutants).
Verdict accepted.

## Hermes
`docs/audit/2026-11-25-hermes-oi348-landing2-m2.md`: L1, L2 (one Sonnet seat each) on the post-B-pass
staged diff. 4 P3: 1 fixed, 1 kept by design with the reason, 1 verified clean, 1 no action. Verdict
accepted.
