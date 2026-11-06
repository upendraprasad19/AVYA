---
hermes_pass_id: 2026-09-29-hermes-oi-182-202-subscription-state
ran_at: 2026-09-29T20:30:00+05:30
batch_scope: working tree of branch oi-182-202-subscription-state (staged, uncommitted) vs main
lens_set: [L1, L21, L22, L23, L29, L35]
agents_dispatched: 6
findings_total: 14
findings_by_severity: { P1: 1, P2: 6, unrated: 7 }
verdict: accepted
---

# Hermes Pass: oi-182-202-subscription-state

Batch: OI-182 (payment grace window derived from the retry schedule, Flutter) and
OI-202 (drop the `users.subscription_status` / `users.subscription_expires_at` mirror
columns, the trigger and two functions; entitlement derives from `public.subscriptions`).
Blast radius catastrophic (razorpay-webhook, verify-payment, admin-*, a SECURITY DEFINER
rewrite). Six context-blind Opus agents, one per lens, each given the staged tree and no
database write access.

## Provenance note

The L1, L21 and L23 hand-backs arrived before a context compaction, and their raw
severity ratings did not survive it. Their findings are listed below with the fix artifact
that closes each one (all re-verifiable in the tree), and their severity column is left
`unrated` rather than reconstructed. L22, L29 and L35 were read after the compaction and
carry their own ratings.

## Summary

- 14 findings, all terminal: 12 fixed in this batch (finding 4 closed by Commit 2 after the live apply), 2 `verified_clean` (8 and 12: the deployed bot does not exist, per the founder). One
  further pre-existing observation (the `receive_email` flaw) is recorded on OI-227 and not counted.
- No `false_alarm` and no `spawn_followup_batch`.
- Ship-blockers before the live steps: none open. The P1 from L35 (live schema ahead of
  `main`) is closed by a plan change, not a code change.

## Findings by lens

### L21 Edge Function semantic correctness
1. **razorpay-webhook double promo redemption** (unrated). A 23505 on the `subscriptions`
   insert (a concurrent verify-payment already wrote the row) fell through to
   `redeemPromo`, so a retry could redeem twice. **Fixed:** `alreadyProcessed = true` on
   23505 (`razorpay-webhook/index.ts`), pinned presence-only in
   `test/contracts/razorpay_webhook_promo_double_burn_guard_test.dart`.

### L23 service-role paths
2. **`fetchLatestActiveEndByUser` had no page bound** (unrated). **Fixed:** `maxPages: 200`
   and a `console.warn` canary at >= 5000 rows; failure still returns `null`, never an empty map.
3. **Stale or wrong comments** on the mirror and the response key (unrated). **Fixed** in
   `razorpay-webhook`, `verify-payment`, `subscription.ts`, docs.
4. **The new `private.founder_metrics()` must have its REVOKE/GRANT lines pinned**
   (unrated). **Fixed in Commit 2 (2026-09-30), after the founder-authorized live apply:**
   `test/contracts/migration_152_drop_subscription_mirror_test.dart` pins the REVOKE ... FROM
   PUBLIC, anon, authenticated and the GRANT to service_role, in order after the create;
   mutation M5 (REVOKE removed) reddened 1 test. Live ACL after the apply: postgres + service_role only.

### L1 writer/reader drift
5. **`expiry-reminder` was a reader of the same semantic the inventory missed** (unrated).
   It scanned `subscriptions` per row, so a renewed user could be reminded as expiring.
   **Fixed:** it now uses `fetchLatestActiveEndByUser` + `usersWithLatestEndIn`, and a null
   read throws so the cron records "failed"
   (`test/contracts/expiry_reminder_latest_end_test.dart`). It joins the deploy list (six EFs).
6. **SoT registry prose** (unrated). The admin snapshot concept and the referral writer
   still described the mirror. **Fixed** in `docs/sot_registry.yaml`, including a
   "CHANGED MEANING" note on the expiry tab.
7. **`/user` showed a lapsed active-status row as PRO** (unrated). **Fixed:**
   `telegram-admin-bot` prints `free (<plan> lapsed <date>)` when `end_date` has passed
   (mutation `sub && true` reddened 1 test).

### L22 schema-vs-payload parity (clean in the repo)
8. **The running Telegram coach bot is outside the repo** (P2, PARTIAL). `telegram-bot/bot.py`
   here is patched, but a deployed VPS copy would be unreachable from this batch and, if it
   read `users.subscription_status`, would show every PRO user as free after the drop.
   **verified_clean:** the founder states the bot is not deployed and the feature is hidden
   (2026-09-29), consistent with OI-227 (connect entry points removed 2026-09-21). Not
   independently checkable from this host. Checked clean in the repo: 954 column refs, all
   `users` call sites, RPC callers, RETURNS TABLE parity proven in a throwaway local Postgres,
   no released client reads either column.

9. **The quota budget was claimed in the plan but written nowhere** (P2, REAL). One payment
   is at most 16 verify-payment executions against a per-user limit of 20 (Phase 2 + 3
   retries, each up to 4 handler runs through the cold-start loop). **Fixed:** section
   "Server quota budget" in diagnose f2a6d1 and a QUOTA CAVEAT in
   `lib/core/constants/payment_timing.dart`.
10. **`maxPages: 200` was in the working tree but not staged** (P2, PARTIAL). **Fixed:**
    re-staged; `git show :supabase/functions/_shared/subscription.ts | grep -c maxPages` = 1.
    Two pre-existing points recorded, not changed (an old retry loop can spend a new user's
    quota after an account switch; `gate()` goes 21m45s instead of 10m without a verify cache
    during grace, against an unlimited endpoint).

### L35 migration reversibility and forward-compat
11. **Live schema would be ahead of `main` between the apply and the merge** (P1, REAL).
    `origin/main` still carries the mirror write in both payment functions, so a deploy from
    a `main`-lineage tree after the drop makes every webhook delivery return 500, and other
    sessions are demonstrably deploying from `main`. **Fixed in the plan (step 1b):** Commit 1
    is merged to `origin/main` with CI green BEFORE the dry-run, the deploys and the apply;
    a `git grep` precheck on `origin/main` must return nothing before the apply; Commit 2 goes
    by a second `--no-ff` merge of the same branch.
12. **Same as 8** (P2): the external bot is outside the deploy and verify ordering. **verified_clean** with 8.
13. **`SET LOCAL lock_timeout` is a no-op outside a transaction** (P2, PARTIAL). Measured
    locally: a WARNING and an unbounded lock wait. **Fixed:** the draft uses
    `SET lock_timeout = '5s'` and a closing `RESET lock_timeout`; the Commit-2 migration-text
    test pins both.
14. **The inline rollback did not restore the orphan** (P2, PARTIAL). Measured locally:
    pre-152 `pro_expired 2 / free 30` came back as `1 / 31`. **Fixed:** the block now restores
    `4d27a40b` from the snapshot and carries no BEGIN/COMMIT of its own.

## Action items (one terminal state each)

- [x] 1, 2, 3, 5, 6, 7 fixed in this batch, each with a test or a re-checkable artifact.
- [x] 9, 10 fixed in this batch.
- [x] 11, 13, 14 fixed in this batch (plan step 1b; migration draft).
- [x] 4 fixed: Commit-2 migration-text test (13 tests, 10 mutations reddened).
- [x] 8, 12 verified_clean: bot not deployed (founder, 2026-09-29).
- [x] Pre-existing, out of scope: `bot.py` `receive_email` links a chat to an account from an
      unverified typed email (P2, dormant while the bot is off). Recorded on OI-227 as a phase-2
      constraint (the linking-token handshake replaces the email prompt); no new OI.

## Self-evolution

- 2026-09-29, oi-182-202-subscription-state, lenses L1/L21/L22/L23/L29/L35, 14 findings,
  six agents, 490 s to 963 s each, 280k to 349k tokens each.
- Signal-to-noise: every lens returned at least one real finding except L22, whose one
  finding was the bot gap outside the repo (its in-repo checks were clean).
- **Lesson: for any live-change-then-merge sequence, ask what a deploy from `main` does
  AFTER the live step.** Four plan-review rounds and a B-pass audited the plan's own ordering
  (EFs before the drop) and none asked the mirror question; L35 found it by asking what the
  tree other sessions deploy from looks like once the schema has moved.
- **Lesson: a "readers of the dropped columns" inventory misses readers of the derived
  semantic.** `expiry-reminder` never named either column and was still wrong about renewals.
- No new lens proposed.
