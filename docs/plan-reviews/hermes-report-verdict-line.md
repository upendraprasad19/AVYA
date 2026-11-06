---
branch: hermes-report-verdict-line
plan: docs/audit/2026-10-13-hermes-referral-pay-on-conversion.md
date: 2026-10-16
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/hermes-report-verdict-line-bpass.md
---

# Plan review - hermes round 2 on migration 159: new killer cases, ledger corrections, a recorded verdict

This branch is docs and tests only; migration 159 (applied live, hash-pinned) is untouched. It re-runs the four-seat hermes review of the referral reward, records a line-anchored `verdict: accepted` in the report, adds behavioural killer cases for mutants the first round called unkillable, corrects the closure ledger, and files OI-344 for the changes that do need a new migration. It reaches platform tier only through one stale clause fixed in `supabase/functions/CLAUDE.md`.

## Review rounds

Each round was a fresh, context-blind Sonnet reviewer, read-only, with no access to the author's reasoning. Most of them could not search (no Grep or Glob) and read the named files directly.

- **Round 1** (plan review) found two P2 contradictions the batch had left in its own records: the first round's "M22 and two other mutants are unkillable / equivalent" text survived in the round-1 report text and in ledger rows B5, D7, D8 and M1, although this batch had killed them (X5, H1, H2). Fixed in 4225209f, with five P3s (unanchored matches, N1-N4 not saying when the founder was asked, commit fields, a case count, an X5 precondition comment).
- **Round 2** (plan review, on the post-round-1 state) found one more P2 of the same class: the plan document (`docs/plans/referral-pay-on-conversion.md` lines 95, 185, 198, 200) still carried the old claim, plus P3s (the ledger header's commit-field comment, the founder-asked dates on X3, X7, U2, wording of N1-N4, a line saying what `accepted` does not mean). Fixed in f7f9f240.
- **Round 3** (mechanical sweep over the six documents that repeat the claims and over the ledger shape) found nothing stale and the ledger arithmetic right (56 rows, 56 terminal, no `deferred:` key). Two undated "86" mentions it listed are dated build statements, not contradictions.
- **B-pass** (`docs/reviews/hermes-report-verdict-line-bpass.md`) on the real diff: no P0/P1, five P3, each resolved or answered. Disclosed there: the reviewer used Bash for read-only commands because it had no Grep.
- The subject of this batch, migration 159, was itself reviewed by four seats on 2026-10-13 (round 1) and four more on 2026-10-16 (round 2); both reports are in `docs/audit/2026-10-13-hermes-referral-pay-on-conversion.md`.

Three rounds, not two, because rounds 1 and 2 each found a surviving copy of one corrected claim in a file the previous round had not swept. Round 3 swept all of them and the unit did not need splitting: every finding was text.

## Ground truth

- Re-read by the author against the files: migration 159 lines 203, 234, 275-281, 373-379; `redeem-referral/index.ts`; `razorpay-webhook/index.ts` lines 457-458; the ledger arithmetic; the registry ranges; the shell script's JSON key order.
- Read live (read-only SQL against project `dedsavbjuwgarrhphgnl`, 2026-10-16): the 3 legacy redemptions carry `referrer_rewarded = false` and `converted_at` NULL (ledger D4 had said true); `anon` and `authenticated` hold INSERT, UPDATE, DELETE and TRUNCATE on `referral_redemptions` with row security on and one SELECT policy; `promo_codes` has "Anyone can read active promo codes".
- Run on a fresh replica whose `process_referral_conversions` md5 equals the applied one (`d24f43267f2beb15ac569c73e7c54555`): live verify `ok=89 fail=0 skipped=0`; the concurrency script `CONCURRENCY OK` (bash, not sh); six new mutants applied and each reddening exactly its own case (X5, H1, H2, W14+W15, C13 twice); M02, M05, M17 and M22 re-run. The two referral contract tests (47 of 47) and the full local suite (9628 passed, 0 failed, at 4a189d5e) pass; pre-commit exit 0 on all three commits.

## Position on feature flags (CLAUDE.md 4.6)

Nothing here changes runtime behaviour, so there is no flag and nothing to roll back. The test cases run only against a disposable replica or inside an aborting transaction.

## What this record does NOT cover

- `verdict: accepted` in the hermes report means no P0/P1 and a recorded disposition for every finding. It does NOT close the `blocked_on_user` ledger items: refund and chargeback (X1, X2), the promo ceiling (X4, N5), the privacy exposure and Unit C (X7, U2), the purchase-during-trial build (X3), payment attribution (N6, N7) and migration 160 (N1-N4, OI-344). Each waits for the founder.
- The six new mutants are reproduced from the substitutions quoted in the report, not from a committed runner; the 104-row first-round matrix still lists only the cases it could attribute.
- Merge of this branch is the founder's go through `sh scripts/safe_pr_merge.sh 116` only.
