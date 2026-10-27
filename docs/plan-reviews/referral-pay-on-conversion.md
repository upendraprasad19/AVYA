---
branch: referral-pay-on-conversion
plan: docs/plans/referral-pay-on-conversion.md
date: 2026-10-13
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/62365c1cfd95-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-13-hermes-referral-pay-on-conversion.md
---

# Plan review - unit S1 of the referral pay-on-conversion plan (migration 159: the referrer is rewarded when the friend pays)

Founder decision (2026-10-12, chat): the friend still gets 7 PRO days when they apply a code; the referrer is rewarded only when that friend pays, 7 days for a monthly plan and 30 for a yearly one, with unlimited invites; supersedes the 7-per-90-days cap of migration 158 (OI-320) and re-scopes OI-336. Defaults accepted 2026-10-12/13: a code is applied once ever, only in the first 7 days of an account, never by an account that has ever paid; 90-day attribution; the reward vests 7 days after the payment; promo-discounted payments count; no top-up on a monthly-to-yearly upgrade. Plan: `docs/plans/referral-pay-on-conversion.md` (v4, with the section 10 build record). Unit S1 is migration 159, its replica proof files, the contract test and the docs; unit S2 (the Edge Function guard) and unit C (the client) have their own branches and records.

## Review rounds

- **Plan round 1** (fresh, context-blind, with sandbox access): 3 P1, 8 P2, 7 P3 (legacy rows credited, an infeasible live-step order, a compare-and-swap miss marking a reward done, invisible failures, Gate 31 and the cron minute, the referee's payment id readable by the referrer, test and registry inventory).
- **Plan round 2**: 3 P1, 7 P2, 8 P3 and "Unit S is not one batch" (a deleted referee's reward credited while the prose said voided, unbuildable failure-path tests, equivalent and missing mutants, an hourly rewrite of every row). The unit was split into S1, S2 and C.
- **Plan round 3**: 0 P0, 1 P1, 6 P2, about 12 P3; "sound with fixes, S1 is one batch, nothing needs a re-split". Measured: a real job-versus-account-deletion deadlock without `FOR KEY SHARE NOWAIT` on the users row. v4 is converged-after-fold (a self-attestation: no fourth plan round; the B-pass and hermes read the real SQL).
- **B-pass** (`docs/reviews/62365c1cfd95-review.md`) on the real working tree: **no P0/P1, four P2 and five P3**, every one resolved (a stalled reward was invisible and got a third alert placed BEFORE the job lock; the live verify could be silenced by the bug it should catch; a concurrency case could not see a job-side deadlock; documentation rot; two positions recorded).
- **Hermes pass** (`docs/audit/2026-10-13-hermes-referral-pay-on-conversion.md`), four fresh Sonnet seats (SQL and locking; tests and mutation adequacy; docs and gates; abuse, privacy and the apply protocol) on the post-B-pass tree: **no P0/P1**, every finding resolved in the batch or given a terminal state in `docs/audit/referral-pay-on-conversion.closure.yaml` (a batch cap of 50 per run, an alert context with counts, wording of the lock claim, the live promo read).
- **Convergence, stated plainly.** The plan rounds found P1s until the fold; the B-pass and the hermes seats, reading the real diff, found none. The migration changed after the B-pass (the stall watch, the batch cap, the volume-alert context, comment wording) and the final file (sha256 `74631ee7d4ba2d3fe1b0b3b54a98ddae84652d38e8957fe66a115b09f6740df1`) was then re-proved in full: 86 live-verify cases (89 after hermes round 2, 2026-10-16), D1-D7, C1-C13, the inline rollback, 104 mutants with 0 survivors.

## Ground truth

- Read at base `aa4da6a4` and the working tree by the plan reviewers, the B-pass, the hermes seats and the author: the migration, the function's 158 body (live md5 `e69618b8bdabe6ef495a0a463efd51e0`, equal to the replica baseline), the two writers of a paid `subscriptions` row (`razorpay-webhook`, `verify-payment`; each inserts one `monthly`/`yearly` row per captured payment with `razorpay_payment_id` set and `start_date = now`), `create-razorpay-order`'s 409 guard, `backups/live_schema_columns.json`, the SELECT policy of the redemption table.
- Live, read-only, project `dedsavbjuwgarrhphgnl` (2026-10-12/13): RLS on both tables with SELECT-only policies; 3 redemptions ever, none inside 97 days; `promo_codes` 3 active codes, maximum discount 30 percent; the dry-run of the reconcile over live rows reads 0 candidates; the auth config (`mailer_autoconfirm` false, phone auth off).
- Run, not just read: the replica proof files, the mutation matrix, the rollback, the full Dart suite (9365 passed, the 2 reds were the expected pre-apply ones, now green), and after the apply the same live-verify file on the real project (`SUMMARY ok=86 fail=0 skipped=0`, nothing left behind) with nine hourly cron runs `succeeded`.

## Section 4.6 / registry `requires: feature_flag` - position

No new runtime flag, on purpose (plan section 2.1): the redeem change is a refusal plus the removal of the referrer credit, and a flag inside a SECURITY DEFINER function would be a second code path whose "off" state is the cap-less 158 behaviour this batch exists to replace. The off state of the reward is `UPDATE cron.job SET active = false` for `referral_conversions_hourly` (migration 146 re-surfaces a switched-off job weekly; pending rows stay and keep vesting). The off state of the redeem change is the inline rollback block, verified byte-for-byte on a fresh replica (function md5, columns, constraints, private functions, cron, ACL).

## What this record does NOT cover

- Merge of the S1 pull request: its own founder go, only via `sh scripts/safe_pr_merge.sh <pr>`. Unit S2 can merge only after S1 is on `main` (its cross-pin test reads migration 159). Unit C starts after S1 is merged.
- Five open edge cases the founder asked to have filed: OI-339 (refund), OI-340 (chargeback), OI-341 (purchase during the referral trial, with the founder's decision to enable it and stack the paid cycle after the current PRO), OI-342 (promo-discount floor), OI-343 (throwaway accounts; email confirmation is on, phone auth is off).
- Deviations from the plan text, recorded in the closure ledger (X8) and the migrations ledger entry: the apply was 34 minutes before a `:41` tick, not right after one, and the live verify ran about nine hours after the apply because its first call failed with a transport error before anything ran.
