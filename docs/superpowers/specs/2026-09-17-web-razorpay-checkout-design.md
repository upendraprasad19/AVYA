---
date: 2026-09-17
status: draft
blast_radius: platform (payment path on the public webapp — re-classify the real diff at plan-review time via scripts/blast_radius_from_diff.dart)
related: docs/architecture/payment.md, docs/architecture/subscription.md, lib/core/services/CLAUDE.md, docs/superpowers/specs/2026-04-17-sync-reliability.md
---

# Web Razorpay checkout — sell AVYA PRO in the browser (test keys first)

## Problem

The webapp paywall is a dead end. `paywall_sheet.dart:279-292` intercepts the
UPGRADE button on web, closes the sheet, and shows
*"Payments are only available in the mobile app. Download ICANBEFITTER to
upgrade."* — because `razorpay_service.dart:241` early-returns on web
(`if (kIsWeb) return;`) and `razorpay_flutter` is a native-only plugin
(`initialize()` is a deliberate no-op on web, `:66`).

The founder wants people to buy an AVYA PRO subscription from the webapp.
Everything needed except the checkout-open step already exists and is
platform-neutral (audited 2026-09-17):

- Order creation via `create-razorpay-order` EF with the 409 already-pro
  guard — `razorpay_service.dart:121-208`.
- The Razorpay options map (key, order_id, amount, name, description,
  prefill.email, notes, theme `#D4B270`) — `:225-239`. Byte-compatible with
  what Razorpay's web Standard Checkout JS expects.
- The full success path: JWT refresh → optimistic PRO activation
  (markPaymentInFlight / writeSubscriptionState / localActivationAt, each
  independently try/caught per APK Test #12.2 Task #5) → background
  `_pollAndActivate` (exact payment_id match, then plan-filtered fallback,
  then `verify-payment` EF) — `:346-457`, `:555-700`.

## Founder-locked decisions (chat 2026-09-17)

1. **One-time orders now** (₹349/month, ₹2,999/year — same AppConstants
   prices). Razorpay Subscriptions (auto-renew) is a later, separately
   designed batch — to be filed as an OI at batch close. This matches the
   prior multi-source billing brainstorm's decision #3/#8 (web first on the
   existing hand-rolled pipeline; the schema/`subscription_events` migration
   ships with the Play Billing batch, not this one).
2. **Test keys for now.** Live keys exist and are KYC-activated, but the
   public webapp launches checkout on `rzp_test_` keys. The live flip is a
   later founder decision.
3. **No allowlist guard.** The founder explicitly accepted the test-mode
   exposure: any webapp visitor can complete a test-card payment and receive
   a real PRO row in the production `subscriptions` table (webhook/
   verify-payment grant paths are unmodified). This is an accepted-risk
   record, not an oversight — see §6.
4. Web checkout is **visible and functional** — no feature flag hiding it,
   only a kill-switch for rollback (§4).

## Approach (locked by founder: Approach A)

Razorpay Standard Checkout via `checkout.js` + `dart:js_interop`, reusing the
existing options map and the existing verification pipeline unchanged.
Rejected: Razorpay Payment Pages/Links (hosted redirect — amount configured
server-side of us, breaks in-app polling UX, drifts from the
plan-derived-from-amount security rule) and community pub packages (tiny,
uncertain maintenance for ~100 lines of owned interop).

## Design

### 1. New web interop layer — modeled on `pwa_install_interop_web.dart`

Pattern precedent is already in-repo and modern:
`lib/shared/widgets/pwa_install/pwa_install_interop_web.dart` +
`pwa_install_interop_stub.dart`, selected by a conditional import keyed on
`dart.library.js_interop` (NOT the deprecated `dart:html` used by
`lib/features/dev/xls_saver_web.dart`).

- **`web/index.html`** — add
  `<script src="https://checkout.razorpay.com/v1/checkout.js"></script>`
  before `flutter_bootstrap.js` (`:158`).
- **`lib/core/services/razorpay_web_checkout_web.dart`** (web-only,
  `dart:js_interop`) — `@JS('Razorpay')` external interface; `open(options)`
  with `handler` (success) and `modal.ondismiss` injected into the options;
  success callback fields map 1:1 from Razorpay's standard web contract:
  `razorpay_payment_id` / `razorpay_order_id` / `razorpay_signature` — the
  same three values the native SDK's `PaymentSuccessResponse` carries.
  Defensive guard: if `window.Razorpay` is undefined (script blocked /
  offline), surface an actionable failure instead of throwing.
- **`lib/core/services/razorpay_web_checkout_stub.dart`** — non-web no-ops;
  MUST NOT import `dart:js_interop` / `dart:html` (same rule as the stub
  precedent, whose header documents exactly why).
- **`lib/core/services/razorpay_web_checkout.dart`** — the conditional
  import barrel + the pure, unit-testable mapping functions:
  - `webCheckoutOptionsFrom(Map<String, dynamic> base)` — injects
    `handler`/`modal` keys (the base map keeps parity with the native map).
  - `parseWebSuccessPayload(Map<String, dynamic> raw)` — pure
    `{paymentId, orderId, signature}` extraction (JSObject → Dart map via
    `toDart` in the thin web layer, then this pure function).

### 2. Shared success path — one verification pipeline, two SDKs

`_handlePaymentSuccess(PaymentSuccessResponse)` (`razorpay_service.dart:346`)
uses only `response.paymentId` / `.orderId` / `.signature`. Extract the body
into a platform-neutral method, e.g.
`handlePaymentConfirmed({required String paymentId, String? orderId, String? signature, required String plan})`:

- the existing native handler becomes a thin adapter calling it;
- the web success callback calls it with the parsed web payload;
- `_handlePaymentError` behavior is mirrored for web: `modal.ondismiss`
  maps to the existing `PAYMENT_CANCELLED` no-snackbar path (`:466`), and
  the web error callback maps to the existing error-snackbar path.

No duplicated verification logic; the poll/verify-payment/grace-window
behavior is byte-identical across platforms.

### 3. RazorpayService web branch

`razorpay_service.dart:241` (`if (kIsWeb) return;`) becomes:

```dart
if (kIsWeb) {
  if (isWebCheckoutDisabled()) { /* kill-switch: old no-op + onFailure */ return; }
  unawaited(RazorpayWebCheckout.open(
    webCheckoutOptionsFrom(options),
    onSuccess: (m) => handlePaymentConfirmed(
        paymentId: m.paymentId, orderId: m.orderId,
        signature: m.signature, plan: _pendingPlan ?? 'monthly'),
    onDismissed: /* PAYMENT_CANCELLED-equivalent */,
    onError: /* error-snackbar equivalent */,
  ));
  return;
}
```

`isWebCheckoutDisabled()` lives in `razorpay_service.dart` (platform-neutral,
so both the paywall check and the web branch read the same predicate) and is
a defensive configBox read following the established kill-switch convention
(`isSyncAutoDrainDisabled`, `sync_state_provider.dart:43,65-72`): **absent or
anything but `true` means web checkout is ACTIVE** (default), so a
missing/unopened configBox can never silently disable payments.

### 4. PaywallSheet web branch — old path preserved behind the kill-switch

`paywall_sheet.dart:279-292` is rewritten as:

- kill-switch ON → the existing mobile-app snackbar, verbatim (rollback
  path preserved per §4.6; reachable without a redeploy via configBox);
- kill-switch OFF → fall through to the normal mobile flow (sheet pops,
  `openCheckout` fires, web branch opens the JS checkout).

### 5. Server — zero changes

`create-razorpay-order`, `razorpay-webhook`, `verify-payment` are untouched.
Plan-derived-from-amount, webhook idempotency (pre-SELECT + 23505 + 5-min
replay window), promo redemption, and rate limits all already hold
(docs/architecture/payment.md §Security Rules 1-6). One founder-side
prerequisite at test time: the Razorpay dashboard's **test-mode webhook**
must point at the `razorpay-webhook` EF URL.

## Testing (rule 21 — behavioral where feasible, mutation-proven)

| Test | Kind |
|---|---|
| `test/contracts/razorpay_web_checkout_options_test.dart` — extracted options builder: web map carries `order_id` + the SERVER amount (never client-computed) + notes (`user_id`, `plan`, promo) | behavioral over the pure function |
| `test/contracts/razorpay_web_success_payload_test.dart` — `parseWebSuccessPayload`: exact field mapping, missing/null fields null-safe | behavioral |
| `test/contracts/razorpay_web_kill_switch_test.dart` — `isWebCheckoutDisabled`: absent ⇒ active, `true` ⇒ disabled, anything-else ⇒ active | behavioral |
| `test/contracts/web_checkout_paywall_dispatch_test.dart` — paywall web branch: kill-switch ON pins the old snackbar string; OFF pins that the branch no longer early-returns to it | source-grep + widget test if the GoogleFonts-harness pitfall permits (else `presence_only` documented) |
| Shared-handler extraction wiring — native `_handlePaymentSuccess` still reaches `handlePaymentConfirmed` | source-grep wiring test |

Each new protective test is mutation-proven before being believed (rule 21:
neuter the protection, watch the right assertions redden, confirm the
mutation applied).

## Accepted risk + live flip

- **Until the live flip**, the public webapp grants real PRO for test-card
  payments. Accepted by founder 2026-09-17 (decision 3). Mitigation after
  verification: the founder's test subscription rows get cleaned from
  `subscriptions`; new test rows stop once live keys land.
- **Live flip = one later batch**: swap `rzp_live_` keys into the web build
  config + remove nothing else. That commit carries the full ×2 review
  (§4.6 — real-user risk starts there), and `.env.prod` gains `rzp_live_`
  (also un-blocking Gate 24 for the AAB pipeline).

## Explicitly out of scope

Auto-renew / Razorpay Subscriptions (filed as OI at batch close) · refund /
revoke path (own design per the billing brainstorm — nothing takes
entitlement away today) · iOS · schema changes / `subscription_events`
(ships with the Play Billing batch) · pricing changes.

## Batch-close items

File auto-renew OI via `scripts/mint_oi.sh` · ADR amending ADR-0005 (web
launch on one-time orders) · SoT registry entry if a new writer/reader
contract emerges · in-flight memory transition (billing brainstorm: web
launch shipped, Play Billing still pending) · §5 checklist via
`/update-docs`.
