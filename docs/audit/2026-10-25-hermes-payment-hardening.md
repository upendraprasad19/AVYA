---
hermes_pass_id: 2026-10-25-hermes-payment-hardening
ran_at: 2026-10-25T02:30:00+05:30
batch_scope: bcb1af2a..e660e692 (branch payment-hardening, commits 1-5); fixes in commit 6 (1a2f72e9)
lens_set: [L1, L2, L21, L22, L23, L29, L40]
agents_dispatched: 4
findings_total: 19
findings_by_severity: { P0: 0, P1: 0, P2: 3, P3: 16, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass — payment-hardening

Four context-blind Sonnet seats (the founder's Sonnet-only rule overrides this skill's Opus default), the payment
lens set from section 2: seat A L21 (verify-payment, razorpay-webhook), seat B L21 + L29 (create-razorpay-order,
validate-promo, the client retry loop), seat C L2 + L23 (authorization and grants), seat D L1 + L22 + L40
(writer/reader drift, payload parity, PII in logs). Each read the whole diff `bcb1af2a..e660e692` and the
functions in full; none ran a database statement. The consolidated triage below was written after a context
compaction, so every finding was RE-CHECKED against the code (and H9's constraint live, read-only) before this
report, per this skill's 2026-10 lesson.

## Summary
- 0 P0, 0 P1, 3 P2, 16 P3, 0 false_alarm (19 distinct findings after deduplication across seats).
- Ship-blockers: none.
- Fixed in commit 6 (diagnose c7e3b1, B-pass `docs/reviews/59f092dc27a9-review.md`): H1, H2, H3, H6, H7, H8, H9, H10, H11, H12 (and A-F2 / D-L40-1, which are H10).
- Filed: H5 as OI-410, C-2 as OI-411, C-L23-1 residue as OI-409. C-L2 noted on OI-184.
- Kept, with reason: C-3, B-L21-2, B-L21-3 (B-3), B-L29-4 (B-4), D-L22-1.

## Findings by lens

### L21 — Edge Function semantic correctness (seats A, B)
- **H1 (P2, B-L21-1 = B-L29-1 = D-L1-3).** A refused Razorpay order answered 502 (`create-razorpay-order/index.ts:381`); the client's `callFunction` retries 502/503/504 three more times (`supabase_service.dart:528`) and each retry spends a `create_order` unit, so about 7 taps in a Razorpay outage lock a user out for up to an hour. **Fixed:** `err(guardsOn ? 500 : 502, ...)`; the switch keeps the origin's 502. The client shows the same text for 500 (`razorpay_service.dart:266`).
- **H5 (P3, A-F1).** verify-payment's second pre-select (`:606`) has no status filter, and its else arm answers 200 `verified:true` with that row's `end_date`, so the owner of a cancelled or refunded payment gets local PRO until the next server refresh (`razorpay_service.dart:915-921`). Pre-existing, outside the batch diff. Re-checked: the early `existingSub` read (`:369-375`) filters `status = active`, the second does not. **Filed OI-410.**
- **A-F2 (P3).** The outer catch-alls log the raw error. **Same as H10, fixed.**
- **B-L21-2 (P3).** The order unit is spent before the body, plan and 409 checks. **Kept:** counting every authenticated attempt, malformed ones included, is the limit's purpose (verify-payment and delete-account do the same), and a normal user cannot reach 30 an hour.
- **B-L21-3 = B-3 (P3).** An unreadable counter is a 429 `rate_limit_unavailable` with only a `console.error`, no `alerts` row. **Kept:** the same fail-closed shape as `verify_payment_rate_limit`; the 429's text is the honest "Could not start payment right now"; the outage would show in the function logs and the digest's empty counter lines.

### L29 — Rate-limit matrix (seat B)
- **H2 (P3, B-L29-2 = D-L1-1).** `DISABLE_ORDER_ABUSE_GUARDS` stops both counters but was not in `QUOTA_KILL_SWITCHES`, so the digest read "0" rather than UNMETERED. **Fixed.**
- **H3 (P3, B-L29-3).** validate-promo said "Try again in an hour" for a fixed UTC bucket that can end in a minute, and the switch name was spelled in two functions. **Fixed:** `_shared/order_abuse_guards.ts`; the reason names the minutes.
- **B-L29-4 = B-4 (P3).** Refusals are not counted in the digest (the counter stops at the limit). **Kept:** the `rate-limited (quota_key=...)` warn line exists per refusal; a digest count of refusals needs a ledger write on the refusal path, which the counter's design (no write past the limit) deliberately avoids.

### L1 — Writer/reader drift (seat D)
- **H6 (P3, D-L1-2).** The new counters counted as activity in Top users. **Fixed:** `NON_ACTIVITY_KEYS` gains the four abuse-limit keys (delete_account, verify_payment, create_order, promo_validate): they count attempts against a limit, not use.
- **H7 (P3, D-L1-4).** The `payment_log_safety` registry entry missed validate-promo and `payment_alert.ts` and carried an unread `behavioral_test_path_writers:` key. **Fixed.**
- **H8 (P3, D-L1-5).** The `payment_alert` runbook says to grep "does not match any plan" for the payment id, which those lines did not carry. **Fixed:** `payment_id=` on both.

### L22 — Schema vs payload (seat D)
- **H9 (P3, part of D-L22-1).** A repeat use of a code by the same user hits UNIQUE(code, user_id) on `promo_code_uses` (migration 025; re-checked LIVE 2026-10-25: `promo_code_uses_code_user_unique`) and the batch's R-6 check logged it as an error. **Fixed:** an info line for 23505 only.
- **D-L22-1 rest (P3).** The repeat use still increments `used_count`, which the strict order rule reads. **Kept:** `max_uses` caps uses, and a second purchase with the same code is a use; only the audit row is per user.

### L40 — PII in telemetry (seat D)
- **H10 (P3, D-L40-1 = A-F2).** The four outer catch-alls passed the error as a second argument; `req.json()`'s SyntaxError quotes about 10 characters of the body (seat D ran it). **Fixed:** `unhandled <name> at <frames>` via `stackFrames()`; the log contract has no exception list now.
- **H11 (P3, D-L40-2).** create-razorpay-order logged an unknown, client-typed code (bounded) on refusal. **Fixed:** `code_length=` only.

### L23 — Authorization on service-role paths (seat C)
- **H12 (P2, C-L23-1, first half).** The webhook captured a `payment.authorized` payment BEFORE refusing a missing or malformed `notes.user_id`. Recurrence of bug class 2.121 in the twin of the writer U1 fixed. **Fixed:** the two refusals moved ahead of the capture, unchanged; tested with zero capture POSTs and a frozen-origin positive control; the order is pinned in source.
- **C-L23-1 rest (P2).** On the shared Razorpay account (the website's orders land there too) the webhook cannot tell an app payment from another by anything but `notes.user_id`, and a payment with a valid user id whose amount matches no plan is still captured before the B2a `amount_no_match` alert (verify-payment has the same order). **Filed OI-409** (derive the plan before capturing, in both writers; and what a website payment's notes carry, checked live).
- **C-2 (P3, C-L23-2).** verify-payment's ownership proof is `notes.user_id`, a key the client's checkout options also set (`razorpay_service.dart:287-293`); if checkout notes override order notes, the check proves what the payer typed. No entitlement without paying was found (the plan comes from the amount). **Filed OI-411** (Razorpay's notes precedence, checked live).
- **C-3 (P3, C-L23-3).** validate-promo tells a signed-in caller a code's state. **Kept:** the paywall's four messages need it, checks are limited to 20 an hour, and before migration 163 the whole table was anon-readable.

### L2 — RLS and grants (seat C)
- **C-L2 (P3).** The raw table grants under RLS were never narrowed on `usage_counters` (OI-184) and probably not on `promo_code_uses` or `subscriptions` (not measured). **Noted on OI-184** (the two tables added as candidates to measure).

## After the fixes
Commit 6's own B-pass (two Sonnet rounds, 38 reviewer mutants) found 10 more, all in the fix code or its tests,
all fixed in the same commit: `stackFrames` let a body fragment through as a forged frame (P2), the catch-alls
had no behavioural test, two stale "an hour" texts, the H12 claim overstated its scope (now OI-409), the escape
classes were unpinned, and a throwing getter could make `stackFrames` throw. See
`docs/reviews/59f092dc27a9-review.md`.

## Founder triage
Self-triaged by the author under the founder's commit go for this batch (2026-10-24): every finding is fixed, filed
or kept with its reason above; no false alarm. The seats' signal: A 2 (both real, 1 pre-existing), B 6 (all real or
partial), C 5, D 8; no lens was noise.

## Action items
- [x] H1, H2, H3, H6, H7, H8, H9, H10, H11, H12 — fixed in commit 6 (1a2f72e9), diagnose c7e3b1, mutants in the diagnose.
- [x] H5 — filed as OI-410 on docs/audit/open_issues.md.
- [x] C-2 — filed as OI-411.
- [x] C-L23-1 residue — filed as OI-409.
- [x] C-L2 — note added to OI-184.
- [x] C-3, B-L21-2, B-3, B-4, D-L22-1 rest — verified_clean as design decisions, reasons above.
