---
branch: oi-182-202-subscription-state
date: 2026-09-29
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/8c18c99a0443-review.md
hermes: accepted
hermes_report: docs/audit/2026-09-29-hermes-oi-182-202-subscription-state.md
---

# Plan-review record: OI-182 grace window + OI-202 subscription mirror (catastrophic)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `catastrophic`, COMPUTED** over the branch range
(`git diff --name-only origin/main...HEAD | dart run scripts/blast_radius_from_diff.dart -`),
driven by path globs (razorpay-webhook, verify-payment, admin-*) and by the SECURITY DEFINER
rewrite of `private.founder_metrics()` in the migration-152 draft.

## What this branch is

Commit 1 (`4f5429bb`) of two:

1. **OI-182** (Flutter): the payment grace window is derived from the verify-payment retry
   schedule and bounded per-call timeouts (1305 s), and the retry success path writes PRO state
   before clearing the grace marker.
2. **OI-202 code half** (Edge Functions, `bot.py`, docs): entitlement and expiry derive from
   `public.subscriptions`; the webhook and verify-payment stop writing
   `users.subscription_status` / `subscription_expires_at`; six Edge Functions were redeployed
   from the committed tree (versions 27, 23, 10, 7, 8, 24).

Commit 2 (after the live apply, in a second merge of this branch): migration 152, the
applied-migrations ledger entry, the regenerated live schema snapshot and the migration-text test.

## Review rounds (honest count: three, no round four)

- **Round 1 and 2** (plan v1 to v3): context-blind plan reviewers, the second on the hardened
  plan. They shaped the derive-and-drop design, the null-not-empty failure contract for the
  reduction helper, the DO-block dry-run, and the deploy-before-drop order.
- **Round 3** (plan v4): caught the write-before-clear order of the retry side effects and the
  need for a separately injected clear callback so the order is testable.
- **B-pass** (two reviewers on the diff, Flutter half and EF/SQL half): 11 findings, all fixed,
  `docs/reviews/8c18c99a0443-review.md`.
- **Hermes** (six lenses L1, L21, L22, L23, L29, L35): 14 findings, all terminal,
  `docs/audit/2026-09-29-hermes-oi-182-202-subscription-state.md`. Its P1 (live schema would sit
  ahead of `main`) is why this branch is merged to `main` BEFORE the migration is applied.

## Ground truth

Live state was queried on 2026-09-29 (38 users, 8 mirror rows, 5 live active subscriptions,
`founder_metrics()` 38/5/3/30, all six Edge Function versions and `verify_jwt` flags read from
`list_edge_functions` before and after the deploys). The full Flutter suite (7105) and the full
deno suite (748, 2 known port-8000 failures in untouched files) were run on the staged tree;
`deno check` is clean for the whole functions tree.

## Not done yet, stated so it is not read as done

The migration is drafted outside the tree and NOT applied. The dry-run, the apply, Commit 2 and
the post-apply smoke are ahead, each behind its own founder go. OI-202 stays OPEN until then.
