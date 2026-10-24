---
adr_id: 0005
title: Razorpay WebView checkout (vs native SDK)
status: accepted
date: 2026-04-18
deciders: Upendra
---

# ADR-0005: Razorpay WebView checkout (vs native SDK)

## Context

ICANBEFITTER is India-only at launch. Payment provider must:
- Support UPI, cards, net-banking, wallets (the Indian payment mix)
- Be PCI-compliant; we never want raw card data near our app
- Have a webhook for server-side verification
- Cost-competitive at scale (Razorpay vs PayU vs Cashfree)

Razorpay is the dominant choice in India. Two integration options:
1. **Native SDK** — `razorpay_flutter` plugin, opens native checkout
   sheet
2. **WebView** — embed `checkout.razorpay.com/v1/checkout.js` in a
   Flutter `webview_flutter` widget

## Decision

**WebView checkout.** Embed Razorpay's checkout.js inside a Flutter
WebView. Server creates the order via `create-razorpay-order` Edge
Function; client opens WebView with the order_id; on success, Razorpay
fires `payment.captured` webhook → `razorpay-webhook` Edge Function →
`subscriptions` row created → client polls until visible.

Encoded in CLAUDE.md §2 (Tech Stack: Payments row).

## Alternatives considered

1. **`razorpay_flutter` native SDK.** Rejected at this time.
   - More moving parts (platform channels for Android + iOS).
   - SDK has historically had Flutter compatibility lag — new Flutter
     versions sometimes break the plugin.
   - Smaller surface area for security audit (WebView runs Razorpay's
     own JS, which Razorpay maintains).
   - Less control over edge cases like deep-link returns, app
     resume during checkout.
   - The native SDK's UX advantage (one-tap re-pay) is minor at our
     PRO upgrade frequency.

2. **Cashfree / PayU.** Rejected. Razorpay is dominant in the
   developer-friendly India payment space. Documentation, webhook
   reliability, UPI Intent support all favor Razorpay. Cost is
   comparable.

3. **Stripe.** Rejected for India. Stripe India is real but UPI
   support is younger; merchant onboarding has more friction; the
   ecosystem (analytics dashboard, refund tooling) is less Indian-
   merchant-tuned than Razorpay.

4. **In-app purchase via Google Play.** Considered, may revisit.
   - Pro: managed by Google; built-in subscription lifecycle (auto-
     renewal, grace periods, refunds).
   - Con: 15-30% take rate vs Razorpay's ~2-3%. Material at ₹349/mo
     prices.
   - Con: locks pricing to Google's regional pricing model; Razorpay
     lets us A/B price natively.
   - May revisit when we'd take a 30% cut anyway (Play Store
     distribution may require IAP for digital goods; that's a
     policy-driven future decision).

## Consequences

Good:
- **Server-side verification is the source of truth.** Razorpay
  webhook → `verify-payment` → `subscriptions` row. Client UI is a
  follower of this state. Mitigates client tampering.
- **PCI is Razorpay's problem.** We never touch card data.
- **WebView is debuggable.** Inspect element, network tab, console
  logs — all available during development.
- **Tier upgrade flow is mostly cloud-driven.** Subscription state
  changes server-side; client polls. (Improved Test #12 with grace
  windows + state machine.)

Bad:
- **WebView is heavy.** Cold-start cost; some users see a brief
  loading state.
- **Deep-link return handling is fiddly.** UPI Intent flows leave the
  app and return; WebView state survival is brittle.
- **Razorpay-specific webhook semantics.** We've debugged TDZ
  + NOT NULL + fail-open bugs in razorpay-webhook (Hermes audit
  2026-05-17 / F1, F2, F4). The catastrophic-tier discipline applies
  here — `requires: hermes_pass` per `docs/blast_radius.yaml`.
- **No native one-tap re-pay UX.** Users who churn + return have to
  go through the full WebView flow again.

## Status

Active. Native SDK migration is a deferred option; revisit when:
- Razorpay's native SDK has 18+ months of stable Flutter compat
- We're at 1000+ paying users (UX friction starts to matter)
- Play Store requires IAP — at which point we'd evaluate IAP, not
  the native SDK

## See also

- CLAUDE.md §2 (Tech Stack)
- `docs/architecture/payment.md`
- `supabase/functions/razorpay-webhook/` (CATASTROPHIC tier)
- `supabase/functions/verify-payment/` (CATASTROPHIC tier)
- Test #11 / Theme I1 — webhook idempotency hardening
