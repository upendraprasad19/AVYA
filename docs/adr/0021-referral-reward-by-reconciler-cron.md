---
adr_id: 0021
title: The referral reward is paid by an hourly reconciler job reading the payment rows, not by a trigger or a hook in the payment functions
status: accepted
date: 2026-10-12
deciders: Upendra
---

# ADR-0021: The referral reward is paid by an hourly reconciler job reading the payment rows, not by a trigger or a hook in the payment functions

## Status

Accepted 2026-10-12 (founder decision; plan `docs/plans/referral-pay-on-conversion.md`). Applied live 2026-10-13 (cloud version 20261013040701; live verify 86 of 86 ok; nine hourly runs succeeded).

## Context

Migration 158 credited a referrer with 7 PRO days the moment a friend applied their code, capped at 7 credited referrals
per rolling 90 days (49 PRO days per 90 days per referrer). On 2026-10-12 the founder judged that loss-making and decided
that the friend still gets 7 days at once while the referrer is rewarded only when that friend PAYS: 7 days for a monthly
payment, 30 for a yearly one, with no cap on invites. The reward therefore has to be triggered by a payment.

Two Edge Functions write a paid `subscriptions` row, `razorpay-webhook` and `verify-payment` (one INSERT per captured
payment, `razorpay_payment_id` set, plan `monthly` or `yearly`). Both are in the catastrophic review tier. Neither
handles refund events, and no function updates a `subscriptions` row afterwards.

## Decision

An hourly pg_cron SQL function, `private.process_referral_conversions` (job `referral_conversions_hourly`, minute 41),
reads the rows those two functions already write. It RECONCILES every unrewarded redemption inside a 97-day scan to the
referee's earliest qualifying payment (plan `monthly`/`yearly`, payment id present, status `active`, not cancelled, made
within 90 days after the code) and then CREDITS the referrer once that payment has stood 7 days. `referrer_rewarded`
changes meaning to "the reward has been credited". The grant is one helper, `private.grant_referral_days`, shared with
the redemption itself. The job never waits for a row or advisory lock (try-lock, `SKIP LOCKED`, `NOWAIT`, a key-share `NOWAIT` on the
referrer's `users` row; it still takes ordinary table-level locks, and no function-level `lock_timeout` is set on purpose); the
redeem function may wait for a running job. At most 50 rewards are credited per run.

## Alternatives considered

- **A hook in `razorpay-webhook` / `verify-payment`.** A referral failure would sit inside a payment write: it could block
  or roll back the friend's payment, and the edit would be in the two highest-risk files in the repository.
- **A trigger on `public.subscriptions`.** It runs inside every payment INSERT, with the same failure coupling, and it adds
  a hidden writer to a table whose writers are few and enumerated (SoT concept `subscription_state`).
- **Reward at payment time with no vest.** A refund or cancellation minutes later would already have paid the referrer.

## Consequences

- No payment function is edited; the referral logic cannot affect a payment. The cost is latency (the reward lands up to
  an hour after the 7-day vest) and the limits below.
- A payment cancelled before the vest voids the pending reward (the reconcile re-reads every hour); a later payment
  re-arms it. A cancel after the vest has no clawback.
- A refund or chargeback that never touches the `subscriptions` row is invisible, because neither payment function handles
  refund events. Closing that needs a Razorpay-verified vest or a webhook event handler, a founder decision recorded in
  the plan's section 6.
- The friend cannot buy while on the 7-day referral trial (`create-razorpay-order` answers 409 for any active row), so the
  reward lands about 14 days after the friend joins.
- Failure is observable: `referral_conversions_failed`, `referral_conversions_stalled` and `referral_conversions_volume` alerts
  (warn, 23-hour dedup), and a failed cron run is paged by migration 145. The stalled alert is counted at the START of every run,
  before the job lock, because a run that returns `{skipped: locked}` writes a `succeeded` row that migration 146 cannot see (a
  forgotten session holding the lock would otherwise stall every reward silently).

Plan, review rounds and the measured lock behaviour: `docs/plans/referral-pay-on-conversion.md`. Migration:
`supabase/migrations/159_referral_reward_on_conversion.sql`. SoT concept: `referral_reward_on_conversion`.

## Amendment 2026-10-16 (migration 160, OI-344) (applied live 2026-10-17, cloud version 20261017005132)

The mechanism is unchanged. Migration 160 closes four findings of the post-merge review of migration 159, in the same
file set and with the same ACL discipline:

- **Stale credit (c5e9a3).** The credit select now requires `rr.referee_id IS NOT NULL`; the reconcile already voids a row whose
  friend deleted their account, but a pending row could be selected before that void was visible to a concurrent session.
- **Lock wait became an error (f2d6b8).** `redeem_referral_atomic` retries the grant up to 3 times, 0.25 s apart, on
  `lock_not_available` only; any other error, and the third failure, still propagate unchanged. After each pause the paid-plan refusal is
  re-checked, so a payment that lands during the wait still refuses the trial (a retry must re-validate what it waited on).
- **Payment status is not the other party's business.** The SELECT policy shows a row to both parties, so `converted_at` would tell the
  REFERRER when each named friend paid, and `referrer_reward_days` on which plan. Column-level grants hide the five payment-status columns from `authenticated`; the
  referrer's counts are served by `public.referrer_summary()`, which filters by `auth.uid()` itself.
- **Promo ceiling.** `promo_codes.discount_pct` is capped at 90 by a CHECK (founder decision 2026-10-16).

Accepted unchanged: the credit-batch ORDER (`ORDER BY converted_at, id LIMIT 50`; starvation needs 50 or more stuck rows at once, today 0; ledger N2, `verified_clean`). Plan:
`docs/plans/referral-hardening-migration-160.md`. Migration: `supabase/migrations/160_referral_hardening.sql`. SoT concepts:
`referrer_summary`, `referral_reward_on_conversion`.
