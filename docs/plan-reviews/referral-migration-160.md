---
branch: referral-migration-160
plan: docs/plans/referral-hardening-migration-160.md
date: 2026-10-17
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0a4a05302eab-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-16-hermes-referral-hardening-migration-160.md
---

# Plan review - migration 160 (referral hardening: stale credit, redeem lock wait, hidden payment-status columns, referrer_summary, 90 percent promo ceiling)

Founder decisions (2026-10-16, chat): accept the credit-batch order residual (N2); percent-off promo codes get a technical ceiling of 90 percent (free-access codes are a separate feature, OI-347); the referrer sees AGGREGATES ONLY (friends joined, subscribed, PRO days earned, a pending count) and is told of a credit in-app; Unit C's first run is silent. Founder go 2026-10-17 ("apply migration") for the live apply and ("Commit, push and merge") for this branch.

## Review rounds

- **Plan round 1** (fresh, context-blind): 0 P1, 7 P2, 6 P3. The grant list leaked per-friend payment status through two flag columns; the stale-credit test had no mechanism; the replica lacked Supabase's default function privileges so a mutant was unkillable; OI-344 and N2 terminal states hid two open items; test cases and mutants missing; no API-level check; no sweep of pins that cite the 159 definitions. Folded into v2.
- **Plan round 2** (review #2 on the post-#1 plan): 0 P1, 3 P2, 5 P3. C14 did not guarantee the reconcile skips the target before it updates the decoy, so the mutant could survive; the plan committed before the live apply, which the migration gates forbid; N2 and the X7 residual lost their board owner when OI-344 is archived; classification and mutant details. Folded into v3.
- **Plan round 3**: 0 P1, 3 P2, 4 P3. The OI-336 / X7 / U2 ownership contradicted the Unit C plan; the "retry widened to WHEN OTHERS" mutant had no killer; the retry tests' observation mechanism was not implementable as written; self-check details and the compound search_path mutant. v4 converged: nothing material left, the unit stayed one batch.
- **B-pass** (`docs/reviews/0a4a05302eab-review.md`), two fresh context-blind Sonnet seats on the built tree: 0 P0, **1 P1** (live-verify Q9 inserted into live `promo_codes` without the NOT NULL `valid_until`, so the post-apply gate would have gone red on a correct migration: a replica-fidelity defect the replica hid), 2 P2 (the referee-only mirror case of `referrer_summary`; two false registry statements), 13 P3. All fixed or verified clean.
- **Hermes pass** (`docs/audit/2026-10-16-hermes-referral-hardening-migration-160.md`), four fresh Sonnet seats on the post-B-pass tree: 0 P0, 0 P1, 8 P2, 19 P3, every finding fixed, verified clean or tracked (the 90 percent versus break-even question is the founder's, OI-342). The migration was re-proven on the replica after each round.
- **Convergence, stated plainly.** Plan rounds 1 to 3 kept finding P2s in the PLAN (harness mechanics, ownership of rows); the P1 that mattered was found only by a reader of the built tree, and it was a defect of the proof, not of the migration. Nothing in the plan changed shape after round 3.

## Ground truth

- Read, in the worktree and live (read-only, project `dedsavbjuwgarrhphgnl`, 2026-10-16 and 2026-10-17 before the apply): the 159 function bodies and their md5s (redeem d7e350b5, job d24f4326), the live `relacl` (`arwdDxtm` for anon and authenticated, grantor postgres, no column ACL), the single SELECT policy, the three live promo codes (30, 20, 15 percent, none outside 1..90), `promo_codes.valid_until` (`date NOT NULL`, no default), the cron job (jobid 48, `41 * * * *`), latest migration 159, 3 redemptions.
- Run: the replica proofs (live-verify 111 of 111, deletion D1-D7, concurrency C1-C17 including the executed rollback), more than 50 mutants (all red except two argued behaviourally equivalent and pinned by exact text), the Dart contract tests (57 + the pin test), the pre-commit gate loop on the apply commit `8d70bc77`.
- Applied live 2026-10-17 06:21 IST (cloud version 20261017005132); post-apply catalog and function md5s equal the sandbox apply; the live verify passed 111 of 111 as eight aborting chunks (the Supabase tool rejected the single 91 KB request: requests of about 12 KB and more fail). The hourly job succeeded three times on the new body.

## Section 4.6 / registry `requires: feature_flag` - position

No runtime flag, on purpose: the change narrows access and adds one predicate and one retry to SECURITY DEFINER bodies; a flag inside them would be a second code path. The old path stays reachable as the inline rollback, which was executed and diffed on a replica (C17). It must be coordinated with the Unit C client release.

## What this record does NOT cover

- Unit C (the client that calls `referrer_summary()`), OI-341 Piece A, and the PostgREST-level smoke with a real user JWT (closure row PX, `blocked_on_user`).
- The OI-342 economics floor (closure row EC): the 90 percent ceiling is above the monthly (76.7) and yearly (88.4) break-even; the founder decides.
- Merge of the pull request: only via `sh scripts/safe_pr_merge.sh <pr>`.
