---
adr_id: 0022
title: Android sells PRO through Play Billing (RevenueCat); Razorpay stays web-only; an interim no-purchase Android build is the fallback
status: accepted
date: 2026-11-20
deciders: Upendra
---

# ADR-0022: Android sells PRO through Play Billing (RevenueCat); Razorpay stays web-only

Amends ADR-0005 (billing architecture; its "Play Store requires IAP" revisit trigger has fired) and extends ADR-0019
(web checkout; unchanged). Closes checklist item 0.1 in `docs/operations/GO_LIVE_CHECKLIST.md`.

## Context

- The Android app is distributed through Google Play, whose payments policy requires Play Billing for digital
  subscriptions sold inside the app. `GO_LIVE_CHECKLIST.md` section 0 verified the India carve-out against Google's
  own policy page: an alternative billing system is allowed only ALONGSIDE Play Billing, needs PCI DSS certification
  and a fraud-reporting mechanism, and lowers the fee by 4 points only. Auto-renewing subscriptions pay Google 15%
  from day one, so the Razorpay cost advantage ADR-0005 assumed (2-3% against "15-30%") is much smaller than it
  looked.
- Today the Android build sells PRO through Razorpay (native `razorpay_flutter`). The AAB `1.0.0+49` that carries this
  is already in a production-access application with Google. If Google refuses it, a build without any in-app
  purchase is the way through.
- Two Play Console facts found on 2026-11-20 shape the order of work: (1) Console > Monetize > Subscriptions does not
  let the developer create a subscription until a build that includes the Play Billing library (the `BILLING`
  permission) has been uploaded; (2) the BillDesk merchant onboarding for Google Play India payment acceptance is
  stuck because it needs a public store page, and the store page needs a production release. A build with the
  billing library, uploaded to an internal-testing track, is therefore the first thing to ship, and it does not
  depend on Google's verdict on `+49`.
- The `subscriptions` table is the only entitlement source the client gate trusts (CLAUDE.md section 4.4 rule 19);
  the Razorpay webhook and `verify-payment` write it.
- The app is not live in any store; every account is a tester (CLAUDE.md section 1). There is no existing-user
  migration to design.

## Decision

1. **Android: Play Billing, through RevenueCat, auto-renewing subscriptions.** RevenueCat (`purchases_flutter`) is the
   Android purchase layer; the Play Console products are auto-renewing base plans (monthly, yearly), not prepaid.
   Founder choice 2026-11-20, after comparing it with a hand-built integration.
2. **Web stays on Razorpay** with one-time orders (ADR-0019, unchanged). Razorpay is never offered inside the Play
   build. ADR-0019 rejected RevenueCat for WEB only (RevenueCat web billing does not support Razorpay); that rejection
   still stands and does not conflict with this decision.
3. **The `subscriptions` table stays the gate's single source.** RevenueCat is a purchase and renewal engine, not the
   entitlement authority: a RevenueCat webhook (a new Edge Function) mirrors each Android entitlement event into
   `subscriptions`, and the client keeps reading only the server-verified row (`verifyFromServer()`, rule 19). RevenueCat
   App User ID = the Supabase user id (set at configure time, never an anonymous id). Design in the plan, section 8.
4. **Promotions on Android:** our own free-days codes (OI-347) are redeemed through our own server, not through Play;
   percent-off codes (`validate-promo`) stay web-only. A Play introductory offer is not set at launch (the free
   Phase 1 is already the trial); offers are Console-only, so this is reversible without a build.
5. **A user who is already PRO** (any source) sees "PRO until <date>" on the Android paywall and cannot buy. This
   prevents a double subscription across web and Play. A referral-trial user may buy on Android at any time; the paid plan starts at once and the
   leftover free days are absorbed (founder 2026-11-20), unlike the web, which stacks them after the trial.
6. **Interim: a no-purchase Android build.** If Google refuses `+49` because the app sells through Razorpay, the
   replacement AAB shows no price, no plan card, no promo box and no purchase button on Android, and does not name
   the website (Play steering rules). A user who is already PRO (bought on the web) keeps PRO by signing in with the
   same account. This build carries the dormant billing library, so the same AAB can also be the first internal-testing
   upload. A compile-time release flag, `ANDROID_PURCHASE_MODE` (`razorpay` | `none` | `play_billing`), selects the
   behaviour; the web build ignores the FLAG (it is always `razorpay`). The dependency itself is NOT inert on web: see the
   last item under Consequences. Design and tests in the plan, sections 3 to 7.
7. **App name (founder, 2026-11-20): the brand is "AVYA".** The Play Console title and the manifest label both read
   "AVYA Fit" today (confirmed from the Console dashboard) and stay "AVYA Fit" until BillDesk clears, because the BillDesk
   form must match the Console title exactly and the title must not change while BillDesk reviews. The package stays
   `com.icanbefitter.icanbefitter` (permanent, never shown to users). Nothing in the app needs to change for the name.
   The Play policy allows all capitals in a title only when they are part of the brand name; "AVYA" is the brand, and
   title case is the fallback if a store review objects. After BillDesk clears, the title may be reconsidered (for
   example "AVYA: Workout & Diet Coach"); that is optional and the founder's call.
8. **Not decided here (open):** the exact Play price (founder, 2026-11-20: decided later; default the same 349 / 2,999
   rupees), and Apple (checklist 0.3, a separate decision; RevenueCat would also serve it).

## Alternatives considered

1. **Hand-built Play Billing** (`in_app_purchase` + Google Play Developer API verification + Real-time Developer
   Notifications through Pub/Sub). Rejected by the founder after the comparison, though it was the lean of the
   brainstorm. It means owning receipt verification, the renewal / grace / account-hold / pause / refund state machine,
   and a Pub/Sub receiver, and it would be redone for Apple. RevenueCat absorbs those at the cost of a third-party
   dependency and a revenue-based fee (the fee schedule is NOT verified in this ADR; confirm current terms before
   launch).
2. **Razorpay only, subscribe on the web (the "Netflix model").** Rejected: a launching app with no brand pull cannot
   rely on users leaving the app to subscribe, and the external-link rules are unsettled and differ by region. Kept as
   the shape of the interim build only in the sense that web purchases still unlock PRO.
3. **India alternative billing alongside Play Billing, with Razorpay as the alternative.** Rejected: needs PCI DSS
   certification and a fraud-reporting mechanism, saves 4 points, and still requires the full Play Billing integration
   next to it. Two purchase paths in one build double the entitlement surface for little.
4. **Prepaid (non-renewing) Play plans.** Rejected: the web is already one-time orders; auto-renew on Android is the
   reason to take the Play integration at all, and churn handling by expiry date alone would waste Play's lifecycle.
5. **Ship nothing purchasable on Android and wait.** Rejected as the end state (Android is the launch platform), but
   adopted as the interim fallback in Decision 6.

## Consequences

Good:
- Policy-clean Android distribution; the same account unlocks PRO from web or phone; no PCI scope of our own.
- Server-verified entitlement is preserved: the client gate never trusts a RevenueCat client-side flag.
- The first billing build (dormant library) unlocks Play Console subscriptions and license testers independently of
  the production verdict.

Bad:
- Three purchase sources feed one table (Razorpay one-time, referral trial, Play via RevenueCat). The renewal and
  revoke path that ADR-0019 deferred (OI-213) is needed for Android auto-renew; the webhook design must cover it.
- Android purchases cost 15% to Google plus RevenueCat's fee; the price decision above is open.
- A third-party SaaS (RevenueCat) sits in the entitlement path; its webhook must be authenticated, idempotent and
  replay-safe, and its outage must not lock a paid user out (the gate reads our table, which keeps the last state).
- In the interim build a free Android user sees a paywall surface with no way to buy. That is the cost of passing
  review, and it is why the interim build is a fallback and not the plan.
- **The dormant package is not dormant on web (found by the B-pass, 2026-11-20).** `purchases_flutter` 11.0.4 declares a
  web plugin; its `registerWith` runs when the app starts and appends a `<script>` for the vendored
  `purchases_js_hybrid_mappings.js` (about 1 MB, shipped in `build/web`), even though no file under `lib/` imports the
  package. Vercel builds web from `main`, so the first web deploy after this lands loads that script on every page view.
  It is asynchronous, cached after the first view and does nothing until `Purchases.configure` is called, and today every
  account is a testing account. **The founder accepted this cost until the web launch (2026-11-20)**; a pubspec
  dependency cannot be limited to one platform. Reopen when the web app launches (closure ledger entry `WEB-SCRIPT`).
- `razorpay_flutter` stays in the Android build until a separate, checked removal (checklist 2.6: it is the likely
  source of the `NFC` and `READ_BASIC_PHONE_STATE` permissions); the web build needs none of it.

- **Built for +51 (OI-519, 2026-11-24).** Decision 8's price is decided: Play ₹449 / ₹3,499 (founder Q5, 2026-11-23);
  the web keeps ₹349 / ₹2,999. Referral days for a Play subscriber defer Google's next charge (Q1 = B). Sandbox
  purchases grant PRO but never count as paid. Every MRR figure stays web-only; Play subscribers are counted apart (Q4).
  The `play_billing` build is the one that sells; `none` stays the fallback. Plan:
  `docs/plans/2026-11-23-revenuecat-play-billing-51.md`; flow: `docs/architecture/payment.md` "Google Play (OI-519)".

## Status

Active. Amends ADR-0005; ADR-0019 unchanged. Implementation plans:
`docs/plans/2026-11-20-android-play-billing.md` (the purchase mode, the `none` build) and
`docs/plans/2026-11-23-revenuecat-play-billing-51.md` (the Play Billing build, OI-519).

## See also

- `docs/operations/GO_LIVE_CHECKLIST.md` section 0 (0.1 closed by this ADR; 0.2 is the plan's section 8)
- ADR-0005, ADR-0019, `docs/architecture/payment.md`, `docs/architecture/subscription.md`
- OI-213 (auto-renew and revoke), OI-347 (free-days codes)
