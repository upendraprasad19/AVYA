# Go-Live Checklist — Play Store (Android) + App Store (iOS)

> **Created 2026-08-24.** Until this file existed there was no artifact anywhere in `docs/`
> answering "what is left before we can launch" — no `*launch*`, `*go_live*`, `*release*` or
> `*playstore*` file. The 63-item OI board is a *backlog*, not a launch checklist, and the two
> sets barely overlap: roughly 45 board items are engineering process and tooling debt that
> block no user.
>
> **How to use it:** this is the trigger, the way the §5 per-batch row is the trigger for
> worktree retirement. An item here is DONE only when its Evidence column names something
> checkable — a version, a dashboard state, a passing gate. "Looks fine" is not evidence.
>
> **Owner column:** `FOUNDER` = requires an account, dashboard, payment or hardware the agent
> cannot reach. `AGENT` = code or config work.

---

## 0. THE BLOCKER THAT GATES EVERYTHING ELSE — store billing

**Status: OPEN — needs a founder commercial decision before any code.**

Verified against Google's own policy page
([Play Console Help 13306652](https://support.google.com/googleplay/android-developer/answer/13306652?hl=en)),
not from memory:

- An alternative billing system in India is permitted **only alongside** Google Play's billing,
  never instead of it.
- Eligibility requires **PCI DSS certification** and a **fraud-reporting mechanism**.
- Choosing alternative billing reduces the service fee by **4%** — so Razorpay's cost advantage
  over Play Billing is far smaller than ADR-0005 assumed.

Current state: `grep -rniE "play billing|in_app_purchase|billing_client"` across `docs/ lib/
android/ pubspec.yaml` returns **zero matches**. Razorpay WebView is the only purchase path.
ADR-0005 predicted this and deliberately left it open — *"Play Store distribution may require IAP
for digital goods; that's a policy-driven future decision."*

**The economics, corrected.** ADR-0005 feared "15-30%":

| Path | Rate |
|---|---|
| Google Play — auto-renewing subscriptions | **15% from day one**, regardless of the Small Business Program |
| Apple IAP — Small Business Program (<$1M/yr) | **15%** |
| Razorpay on web | ~2% |

Android IAP therefore costs ~₹52 of each ₹349, not ₹105.

**How the industry splits**, and the dividing line is brand pull:

- **No IAP, subscribe on the web** — Netflix, Spotify, Amazon Kindle. Works only because users
  already know the brand. External-link rules are also unsettled: US link-out is currently 0%
  after the Epic ruling, Apple filed on 2026-08-14 proposing 15% standard / 5% small-business,
  and SCOTUS agreed in June 2026 to hear the case. Treat 0% as a window, not a rate.
- **Full IAP on both stores** — Duolingo, Strava, MyFitnessPal, Calm, Headspace, and the Indian
  fitness players. They pay the 15% because in-app conversion is worth more than the fee.

**Recommendation: full IAP on both stores, Razorpay retained for web.** A launching app with no
brand recognition cannot use the Netflix model — nobody visits a website to subscribe to an app
they just found. Budget for one entitlement layer serving three purchase sources; this is the
problem RevenueCat exists to solve and is worth evaluating rather than hand-rolling.

**This does NOT affect the live Vercel web app.** Play policy governs apps distributed through
Play. Razorpay on web is unaffected, and live Razorpay keys are needed for web regardless.

| # | Item | Owner | Evidence when done |
|---|---|---|---|
| 0.1 | Decide the billing architecture | FOUNDER | An ADR superseding or amending ADR-0005 |
| 0.2 | If IAP: implement Play Billing + server receipt verification + Real-time Developer Notifications, reconciled with the existing `subscriptions` table | AGENT | Behavioral test + a real sandbox purchase |
| 0.3 | If IAP: same for Apple | AGENT | Sandbox purchase on a real device |

---

## 1. Payments — cannot take money today

| # | Item | Owner | Evidence when done |
|---|---|---|---|
| 1.1 | Razorpay KYC / business verification → LIVE keys | FOUNDER | Live keys visible in the Razorpay dashboard |
| 1.2 | Set live `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET` as Supabase Edge secrets | FOUNDER | Dashboard (the CLI is authenticated to the WRONG account — CLAUDE.md §2a) |
| 1.3 | Register the LIVE webhook: `https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/razorpay-webhook`, events `payment.captured` + `payment.authorized` | FOUNDER | A test event delivered and 200-acked |
| 1.4 | **Set the dashboard webhook secret to the live `RAZORPAY_KEY_SECRET`, byte-identical** | FOUNDER | See the warning below — get this wrong and every payment silently fails |
| 1.5 | Flip `.env.prod` `RAZORPAY_KEY_ID` to the `rzp_live_` key | AGENT (needs 1.1) | Gate 24 (`check_razorpay_key_flavor.dart`) turns green — it hard-fails today, correctly |
| 1.6 | One real ₹349 transaction end-to-end | FOUNDER | A `subscriptions` row + `users.subscription_status='pro'` |

> ⚠ **1.4 is the trap.** `razorpay-webhook/index.ts` used to document a *separate*
> `RAZORPAY_WEBHOOK_SECRET` — *"NOT the Razorpay key secret; separate value"* — and list it under
> "Env secrets used". **That env var is read nowhere in the repo.** The code HMACs against
> `RAZORPAY_KEY_SECRET`. Prod worked only because the configured dashboard secret happened to
> equal the key secret. Creating the LIVE webhook prompts for a secret: enter the live key secret
> verbatim. A distinct value makes every live payment fail HMAC with a **400 — silently, no
> crash, no user ever upgraded**. The docstring was corrected 2026-08-24 (this batch); the
> underlying finding has been open since 2026-06-11
> (`docs/audit/2026_06_11_audit_closures.yaml:93`).

**Not a blocker today, book before recurring billing:** `razorpay_subscription_id` has readers
(`delete-account/index.ts:228,242,246`) and **zero writers**, so `delete-account`'s Razorpay-cancel
step is a permanent no-op. Harmless under one-time orders; a live-money defect the day autopay
ships.

---

## 2. Distribution — Play

| # | Item | Owner | Evidence when done |
|---|---|---|---|
| 2.1 | Create the Play Console app + developer account + merchant profile | FOUNDER | App entry exists |
| 2.2 | **Back up `android/app/release.jks` + `android/key.properties` offsite, TWICE — BEFORE first upload** | FOUNDER | Two copies in separate locations |
| 2.3 | Build an `.aab` | AGENT | `/build-apk --bundle` (added 2026-08-24); artifact at `build/app/outputs/bundle/prodRelease/app-prod-release.aab` |
| 2.4 | Decide the app name and make manifest + listing + policy pages agree | FOUNDER decides, AGENT applies | `AndroidManifest.xml:18` currently says `android:label="AVYA Fit"` while the package is `com.icanbefitter.icanbefitter` and every legal link points at `icanbefitter.com` |
| 2.5 | Store listing assets: short + full description, ≥2 screenshots, 512px icon, 1024×500 feature graphic | FOUNDER | Uploaded |
| 2.6 | Justify or prune the transitive `NFC` + `READ_BASIC_PHONE_STATE` permissions | AGENT | Neither is used by app code; both arrive via a plugin (likely Razorpay). Needs an SDK compatibility check before removal — Play flags unexplained phone-state access |

> Signing itself is already correct: `android/app/release.jks` exists, is untracked, and the build
> **hard-fails** rather than debug-signing if `key.properties` is missing.

---

## 3. Legal / review

| # | Item | Owner | Evidence when done |
|---|---|---|---|
| 3.1 | **Publish real `icanbefitter.com/privacy` and `/terms`** | FOUNDER | Both URLs return real DPDP-compliant documents |
| 3.2 | Play Data Safety form | FOUNDER | Submitted |
| 3.3 | **Health Connect / health-data declaration** (separate from 3.2) | FOUNDER | Submitted |
| 3.4 | Consent checkbox not pre-ticked (email path) | AGENT — **DONE 2026-08-25** | `sign_in_screen.dart:111` `_privacyAccepted = false`; pinned + mutation-proven in `test/auth/terms_skip_test.dart`. Diagnose `d8f2c1` |
| 3.5 | **Decide the Google-OAuth consent posture** | FOUNDER (product/UX) | See the warning below — this is an open pre-launch risk, not a done item |

> ⚠ **3.1 is load-bearing and currently unverified.** Six in-app links already point at those two
> URLs (`privacy_dialog.dart:45,62`; `sign_in_screen.dart:1396,1400`;
> `welcome_screen.dart:334,338`), and **this repo does not serve them** — `vercel.json` deploys
> the Flutter app to `app.icanbefitter.com`, a *different host*, behind a catch-all rewrite. Play
> also requires the privacy URL in the Console listing. Whether those pages exist is not
> verifiable from the repo; open them in a browser.
>
> The in-app privacy dialog also lists only 3 permission categories while the merged manifest
> ships 34. Whatever is published at 3.1 must cover what is actually requested.

> ⚠ **3.5 — TWO CONSENT REGIMES RUN AT ONCE, and the email fix sharpened the contrast.**
> `_privacyAccepted` gates exactly one widget: the email CREATE ACCOUNT button
> (`sign_in_screen.dart:1023`). **Google OAuth — the primary CTA (`:365`) — has no consent gate.**
> Those users instead hit the pre-existing `ensureTermsConsentFallback` (diagnose b3f9e7), which
> auto-stamps `terms_accepted_at` from `created_at` with **no user gesture at all**. So the app now
> asks for an explicit tick on the secondary route and nothing on the primary one. A DPDP or Play
> reviewer comparing the two flows sees an inconsistency that is harder to defend than the
> pre-ticked box was. Fixing it means deciding WHERE consent sits for a redirect flow (before the
> OAuth launch, or as a post-redirect step) — a UX decision, which is why it is a founder row
> rather than an agent one. Surfaced by the B-pass on `launch-blockers-1a` (Finding 1, P1).

**Permissions the Data Safety form must cover** (from the merged prod-release manifest): health &
fitness (`READ_STEPS`, `READ_WEIGHT`, `ACTIVITY_RECOGNITION`), camera + photos (`CAMERA`,
`READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE`≤32), microphone (`RECORD_AUDIO`), notifications
(`POST_NOTIFICATIONS`), plus the plugin-merged `NFC` and `READ_BASIC_PHONE_STATE`.

---

## 4. iOS — not "nearly there", it is zero

**There is no `ios/` directory in the repo at all.** The Flutter iOS platform has never been
generated. HealthKit appears only in Dart comments, via the cross-platform `health: ^13.3.1`
plugin.

| # | Item | Owner |
|---|---|---|
| 4.1 | A Mac with Xcode, or macOS CI (Codemagic / Bitrise) — **hardware blocker; the dev machine is Windows 11** | FOUNDER |
| 4.2 | Apple Developer Program ($99/yr) | FOUNDER |
| 4.3 | `flutter create --platforms=ios .` + HealthKit entitlements + privacy usage strings | AGENT |
| 4.4 | Apple IAP (see §0) | AGENT |
| 4.5 | Re-validate 728 unit tests + 32 integration flows on iOS | AGENT |

**Recommendation: sequence it — Android first, iOS as its own project after.** Landing both at
once roughly doubles the surface while §0–§3 are still open.

---

## 5. Build health at launch

| # | Item | Owner | Evidence |
|---|---|---|---|
| 5.1 | `main` CI-green on the exact SHA being shipped | AGENT | `gh run list --branch main` — all 7 jobs `success` |
| 5.2 | Working tree clean (Gate 1 hard-fails otherwise) | AGENT | `git status --porcelain` empty |
| 5.3 | `pubspec.yaml` versionCode bumped vs last shipped | AGENT | `backups/apk_sizes.json` last entry vs `pubspec.yaml` — versionCode has NO other source (`build.gradle.kts:41` = `flutter.versionCode`) |
| 5.4 | Record the shipped artifact's size + commit it | AGENT | `+38`'s ledger entry sat UNCOMMITTED in the working tree; do not repeat that |

---

## 6. Pre-launch manual QA

Walk `docs/qa_checklist_template.md` (12 flows) on the real artifact. One flow is non-negotiable
for this launch because it covers a fix made in the `launch-blockers-1a` batch:

- **Flow 9** (tap GO PRO) — confirm the paywall headline names a real feature and never reads
  "PRO is a PRO feature" (diagnose `c2b8e5`).

⚠ **STILL OPEN — the bodyweight-plan defect is NOT fixed.** A user who selects the **Bodyweight**
equipment tier is still prescribed `Chin Up` (needs a pull-up bar) and `Standing Calf Raise` (needs
a barbell). A first attempt keyed the guard on `equipment_tier`, but `docs/sot_registry.yaml`
declares that field deliberately over-tagged (*"over-tags tolerated"*) — four bundled rows are
tiered `bodyweight` while `equipment_needed` names real kit. The durable fix keys on
`equipment_needed` via `EquipmentVocab.fromProfile`. Tracked separately; do NOT tick a
bodyweight-plan QA row until it lands.

Also verify on-device, since neither is provable from CI:

- Google sign-in completes and navigates (diagnose `d3a7c9`) — this was broken for **every** user
  on every build since Google OAuth went live, and the fix is in the repo but was in no shipped
  APK as of `+38`.
- Email sign-in releases within 40s under a degraded backend (diagnose `a9c4e2`).

---

## What is deliberately NOT on this list

Stated so it is a decision rather than an oversight: the ~45 OI-board items covering gate scripts,
worktree hygiene, CI timings, test-runtime budgets and doc-citation drift. They are real work and
they block no user. Burning them down before launch would cost weeks and move nothing a customer
can see. They stay on `docs/audit/OPEN_INDEX.md`, which remains the source of truth for "what's
owed" — this file is only ever about "what stops us shipping".
