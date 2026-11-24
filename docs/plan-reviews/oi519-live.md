---
branch: oi519-live
date: 2026-11-24
blast_radius: catastrophic
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/f415470375b9-review.md
hermes: accepted
hermes_report: docs/audit/2026-11-24-hermes-oi519-play-billing.md
---

# Plan-review record: OI-519 live steps L2-L4 (records only)

This branch carries no new code. It records the live steps L2-L4 of the OI-519 plan
(`docs/plans/2026-11-23-revenuecat-play-billing-51.md`, section 29), each done with the founder's go of 2026-11-24.

The two SQL files are `git mv` of the reviewed drafts, byte-identical (R100):
- `supabase/migrations/187_play_upsert_start_date.sql` (the hermes H1-3 draft; reviewed in the hermes pass and in both
  B-pass rounds of `docs/reviews/f415470375b9-review.md`, plan section 28; local proof
  `test/sql/play_upsert_start_date_local.sh`).
- `supabase/migrations/188_revenuecat_reconcile_cron.sql` (the U6 draft; reviewed in `docs/reviews/667e533689bd-review.md`
  and the hermes pass, which added its 120 s timeout).

The plan's six review rounds, the code reviews and the hermes pass are the record of
`docs/plan-reviews/oi519-revenuecat-plan.md` (PR #334, merged `4afa580d`); the counts above are those. The rest of the
diff is records: the ledger entries for 187 and 188, the deploy tool's rotated payload archives (from `main` `4afa580d`),
the CRON_REGISTRY row, the closure ledger (L2-L4 closed), plan section 29, and the local proof's path to the moved file.

Ground truth: every live claim was read back from project `dedsavbjuwgarrhphgnl` (function versions and verify_jwt,
md5(prosrc) before and after 187, the cron job row, the first tick in `cron_call_log`, the two `subscription_events`
rows, the switch's stored digest).
