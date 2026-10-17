---
adr_id: 0019
title: Web payments launch on Razorpay Standard Checkout, one-time orders, test keys first
status: accepted
date: 2026-09-17
deciders: Upendra
---

# ADR-0019: Web payments launch on Razorpay Standard Checkout, one-time orders, test keys first

## Context

The webapp paywall was a dead end on web ("Payments are only available in the
mobile app") because `razorpay_flutter` is native-only. The founder wants
subscriptions purchasable in the browser. The multi-source billing brainstorm
(2026-08/09, ADR-0005's domain) had already locked the sequencing: web first
on the existing hand-rolled Razorpay pipeline (~10% of the work), Play
Billing second, schema migration with the Play batch. The un-designed piece
was the web checkout SDK layer itself, plus rollout posture (test vs live
keys, auto-renew vs one-time).

## Decision

1. **Razorpay Standard Checkout (checkout.js) via `dart:js_interop`** — a
   thin conditional-import bridge (pattern: `pwa_install_interop_*`),
   reusing the existing options map and the existing
   `create-razorpay-order` / `razorpay-webhook` / `verify-payment` Edge
   Functions unchanged. Encoded in
   `lib/core/services/razorpay_web_checkout*.dart` +
   `razorpay_service.dart`'s web branch, merged `02a7eba8` (2026-09-17).
2. **One-time orders now; Razorpay Subscriptions (auto-renew) deferred** —
   filed as OI-213. Renewal work needs the revoke/entitlement-takedown
   design first (nothing takes PRO away today) and a new webhook idempotency
   shape.
3. **Test keys on the public webapp at launch; live keys are a later founder
   flip** (one batch, full ×2 review per §4.6 — that is when real-user risk
   starts). The test-mode exposure — any visitor can mint a real PRO row
   with a Razorpay test card — is explicitly ACCEPTED by the founder
   (2026-09-17, on record in the spec).
4. **Rollback** = `disable_web_checkout` configBox kill-switch (per-browser
   on web; fleet rollback = redeploy) preserving the old paywall behavior
   verbatim.

## Alternatives considered

1. **RevenueCat for web.** Rejected — VERIFIED in the billing brainstorm:
   RevenueCat web billing supports only Stripe/Paddle/RevenueCat Billing;
   Razorpay is unsupported and RevenueCat Billing cannot operate in India
   at all (customer name/address requirement).
2. **Razorpay Payment Pages / Payment Links (hosted redirect).** Rejected —
   amounts/promos configured on Razorpay's side (drift from the
   plan-derived-from-amount security rule), user leaves the app mid-flow,
   in-app polling UX breaks.
3. **Community web-checkout pub package.** Rejected — tiny, uncertain
   maintenance for ~100 lines of owned interop.
4. **Auto-renew (Razorpay Subscriptions) at launch.** Rejected for now —
   bigger build (new EF, new webhook events, cancel path), and it interacts
   with the revoke path that does not exist yet. OI-213.
5. **Server-side test-mode allowlist** (only founder accounts can mint PRO
   from test payments). Rejected by founder — accepted the exposure instead,
   to keep the test loop unencumbered.

## Consequences

Good:
- The entire hardened verification pipeline (webhook idempotency, plan from
  amount, promo redemption, rate limits, grace window, H-20 guards) applies
  to web with zero server changes.
- Web checkout is live in prod immediately after the Vercel deploy of
  `main`; the founder can sell from the browser today.

Bad:
- Until live keys land, test-card PRO grants are possible on the prod DB
  (accepted; test rows cleaned after founder verification).
- Razorpay transactions between web launch and the Play Billing batch get no
  `subscription_events` ledger rows (billing brainstorm decision 7 — accepted).
- The kill-switch is per-browser; a fleet-wide rollback needs a redeploy.

## Status

Active. Amends ADR-0005's billing-architecture domain (web path now
concretely decided; Play Billing path unchanged).

## See also

- `docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md`
- `docs/plan-reviews/web-razorpay-checkout.md` (+ `docs/reviews/7446a3c8a418-review.md`)
- `docs/audit/open_issues.md` OI-213 (auto-renew)
- ADR-0005 (billing architecture), `docs/architecture/payment.md`
