---
hermes_pass_id: 2026-10-21-hermes-oi341-piece-b2-door
ran_at: 2026-10-21T16:00:00+05:30
batch_scope: branch oi341-piece-b2-door (from main b8385b6c), staged tree after the B-pass fixes; whole-file reads of supabase/functions/create-razorpay-order/index.ts, razorpay-webhook/index.ts, verify-payment/index.ts, _shared/payment_alert.ts and _shared/subscription_stacking.ts, plus plan docs/plans/oi341-piece-b2-door.md section 4 (the live sequence)
lens_set: [L1, L2, L21, L22, L23, L29, L40]
agents_dispatched: 4
model_deviation: "Sonnet, one wave of 4, not the skill's Opus default: the founder's standing rule (2026-09-26, 2026-10-07) overrides it."
findings_total: 13
findings_by_severity: { P0: 0, P1: 0, P2: 6, P3: 7, false_alarm: 0 }
verdict: accepted
---

# Hermes E-pass: OI-341 Piece B2a (the purchase door, the switch-mismatch alarm, the replay window, both flips)

## Summary

- 0 P0, 0 P1, 6 P2, 7 P3 records (12 distinct: the deleted-account residual was raised by seats 1 and 2).
- Ship-blockers: none.
- Every finding is terminal in `docs/audit/oi341-piece-b2-door.closure.yaml` (rows `HM-*`).
- The pass ran AFTER the B-pass fixes (rows `BP-*`), on the post-fix staged tree.

Seats: 1 = L21 + L1; 2 = L23 + L40; 3 = L22 + L2 + the live sequence; 4 = L29 + abuse. Every seat was read-only (file
reads, read-only git, the five named Deno suites), with no database statement, no network tool and no script run. Seats 2,
3 and 4 used shell `grep`/`sed` for reading because the Grep tool was unavailable to them (disclosed in their reports).

## Findings by lens

### L21 + L1 (seat 1): 0 P0/P1/P2, 2 P3
- P3: a captured event for an account deleted since the payment now retries for up to the 24 h window (HM-S1-F1; stated).
- P3: the alarm's worst case is about 3 s, not 1 s (HM-S1-F2; stated).
- Clean: TDZ/ordering in all three files; the OFF branch's three outcomes are exclusive, so the alarm runs only after this
  request's own insert; the shut door equals origin's `order desc limit 1`; every server reader of `subscriptions` tolerates
  a user with a trial row and a paid row (all use `limit(1)` with an order, or read all rows).

### L23 + L40 (seat 2): 0 P0/P1/P2, 1 P3
- P3: the same deleted-account residual.
- Clean: every service-role read/write is scoped by a verified id (JWT, HMAC payload, Razorpay fetch + notes check);
  alerts carry user and payment ids only in `context_json`, which neither Telegram (`alert-critical-notify` sends source,
  summary, suggested_action) nor the founder digest reads.

### L22 + L2 + live sequence (seat 3): 0 P0/P1, 2 P2, 3 P3
- P2: tester accounts must be new (redeem window 7 days, never paid) and the step 4 trial needs a THIRD redeem
  (HM-S3-F1; plan fixed).
- P2: clean-up by DELETE inside the 24 h replay window can be undone by a redelivered captured event (re-insert, promo
  re-redeemed, referrer rewarded); clean-up is now a status change (HM-S3-F2; plan, payment.md, webhook comment).
- P3: a third alarm cause (a referrer's own credit landing mid-checkout) (HM-S3-F3); the code must be stored upper-case
  (HM-S3-F4); the door's first `_shared` import needs the host-shell deploy (HM-S3-F5).
- Clean: every column exists live; no source CHECK on `alerts`; R1/R2 are valid; the deploy and flip order is safe.

### L29 + abuse (seat 4): 0 P0/P1, 4 P2, 1 P3
- P2 FIXED: a captured payment whose amount matches no plan was a silent 400 (diagnose c3e7a1; both writers now page).
- P2 FILED: no rate limit on the door and promo limits enforced nowhere (OI-366); referral farming once the door is open
  (OI-367, a product call before store launch).
- P3 KEPT: the alarm pages while the door is shut (a real loss of trial days; a page is right).

## Founder triage

Pending the founder's read of this report with the B2a commit go.

## Action items

- [x] HM-S4-F4 fixed in this batch (c3e7a1, NM1-NM4 red) — coordinator
- [x] HM-S3-F1..F5, HM-S1-F1/F2 fixed in the plan/docs — coordinator
- [x] upstream_blocked: OI-366 (rate limit + promo enforcement; touches founder-digest and validate-promo) — founder to schedule
- [x] blocked_on_user: OI-367 (referral economics) — founder
- [x] verified_clean: HM-S4-F5, HM-SEAT2-CLEAN, HM-SEAT3-SCHEMA-CLEAN — coordinator

## Self-evolution

- Signal: seat 3 (live sequence) and seat 4 (abuse) carried every P2; seats 1 and 2 (code semantics, authz) found only
  stated residuals. For a batch whose risk sits in a LIVE-MONEY procedure, a seat that reads the procedure against the code
  is worth more than a second code-semantics seat.
- Lesson: a plan's clean-up step is code too. "Delete the tester rows" was safe under the old 5-minute window and became
  unsafe the moment this same batch widened the window to 24 h; the reviewer found it by reading the plan's step against
  the batch's own change. When a batch widens a time window, grep the plan and runbooks for every action that relies on
  the old window.
