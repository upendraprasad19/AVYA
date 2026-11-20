# Android purchase surface: the no-purchase fallback build, the dormant billing build, and the RevenueCat design (v3, after review rounds 1 and 2)

Branch `play-billing-fallback`, base `a1849656` (origin/main, 2026-11-20). Decision record: `docs/adr/0022-android-play-billing-via-revenuecat-web-stays-razorpay.md`.
Tier **L** (CLAUDE.md 4.12.6: payment). Blast radius: **platform** for the client diff (measure with positional paths
through `scripts/blast_radius_from_diff.dart` before the first reviewer dispatch; the root `CLAUDE.md` row in U6 makes
that unit platform by itself). Section 8 (the Edge Function and schema) is **catastrophic** class and gets its OWN plan
with its own x2 review and a hermes pass; it is design-only here. Execution mode (4.12.7): **inline**, one worktree, one
writer. Commit types: `feat(payment)` for the flag and the surfaces (no defect is fixed there); two small `fix(profile)` commits in U4a (the PRO subscription sheet text, and the referral share link's wrong Play package id), each with a slim diagnose-doc and a regression test (rule 22). The closure ledger is
`docs/audit/2026-11-20-android-play-billing.closure.yaml` (more than 4 units, rule 4.2), created only once every entry is
terminal.

**Nothing in this plan is committed, pushed or built.** Review history: round 1 on v1 (22 findings: 4 P1, 9 P2, 9 P3) folded into v2; round 2 on v2 (19 findings: 2 P1, 9 P2, 8 P3, verdict NOT CONVERGED until folded) folded into this v3. Both disposition tables are in section 13.

## 0. Founder decisions (binding) and what is still open

Decided 2026-11-20 (memory `project_play_billing_decisions_2026_11_20`):
- Option A: Play Billing on Android, Razorpay web-only. RevenueCat is the Android purchase layer; auto-renewing subscriptions.
- Promos on Android: our free-days codes (OI-347) and, optionally, a Play intro offer (leaning none at launch; Console-only, reversible). Percent-off codes stay web-only.
- An already-PRO user on the Android paywall sees "PRO until <date>" and cannot buy.
- `+49` (Razorpay AAB) is already submitted for production. If Google refuses, the replacement AAB has no purchase on Android.
- The fallback screen design in section 4 (copy is a DRAFT: Wardroom voice and the psychology-pass review come before it ships).

Open, none blocks the no-purchase build:
- App name (checklist 2.4: "Avya Fit" listing, "AVYA Fit" manifest, ICANBEFITTER package and legal links). **Decided 2026-11-20 (founder): "AvyaFit"**; applying it to the manifest and the Console is a separate step. No code in this plan uses a product name on purpose.
- Play price (default: same 349 / 2,999 rupees).

## 1. Facts (verified in this worktree at `a1849656` on 2026-11-20 unless marked)

- F1. `lib/shared/widgets/paywall_sheet.dart` (862 lines) is the one paywall (rule 7). `showPaywallSheet` is `:23-35`; `PaywallSheet.build` renders, in order: letterhead eyebrow `'GO PRO'` (`:446`), subtitle, the `WHAT YOU UNLOCK` benefit card, two `_PricingCard`s built from `AppConstants.monthlyPriceInr` / `yearlyPriceInr` (`_PricingCard` labels `:519`, `:533`), the referral-trial stacking line (`:552`), the promo box (`_buildPromoCodeSection` `:616`, `_validatePromoCode` `:205` calls `validate-promo`), the `UPGRADE TO PRO` button (`:568`, handler `_handleUpgrade` `:277`), `MAYBE LATER` and `RESTORE` (`_handleRestore` `:340`, which calls `subscriptionServiceProvider.refreshFromSupabase()` and reads `isPro()`).
- F2. `initState` logs `paywall_shown` (`message: feature=<raw>`); `dispose` logs `paywall_dismissed` unless `_upgradeTapped`. The raw strings `PRO` and `PRO Upgrade` are separate funnel buckets on purpose (`genericUpgrade` `:76`, `genericUpgradeProfile` `:92`; diagnose c2b8e5).
- F3. `showPaywallSheet(` has **32** invocations in `lib/` outside the sheet's own file (this count already includes the phase variant's own hand-over at `paywall_sheet_phase_variant.dart:131`, table row 32); the phase variant sheet is opened by 3 further `showPaywallSheetPhaseVariant(` callers listed in 5.2 (`paywall_sheet_phase_variant.dart` `paywall_sheet_phase_variant.dart`, 165 lines, which has its OWN price line `:153` and its own `UPGRADE TO PRO  →` button `:140`, and then hands over to `showPaywallSheet(feature: 'Phases 2-12')` at `:131`). The memory file said 38; the measured count is 32 `showPaywallSheet(` calls, counted with `grep -rn "showPaywallSheet("` minus doc comments and the definition. I could not reconstruct where 38 came from; the 32 below are each listed by file:line.
- F4. Purchase entry that does NOT go through `showPaywallSheet` does not exist: `openCheckout` is called only from `paywall_sheet.dart:324`. `RazorpayService.initialize()` runs in `main.dart:89`, `main_prod.dart:26`, `main_dev.dart:29` (native `Razorpay()` on non-web, `razorpay_service.dart:90-95`).
- F5. `pubspec.yaml:43` `razorpay_flutter: ^1.4.5`; no `purchases_flutter`, `in_app_purchase` or billing library; the Android manifest has no `BILLING` permission (grep of `AndroidManifest.xml` returned nothing). Version `pubspec.yaml:19` = `1.0.0+49`; `build.gradle.kts:40-41` reads `flutter.versionCode`. `minSdk = 26`.
- F6. `backups/built_versioncodes.json` (the file Gate 2.5 reads) holds `1.0.0+45` to `+49`, `+49` as `artifact: aab` built `2026-11-08T18:43Z`; `backups/apk_sizes.json` stops at `+39`. So `+50` is the next free code (the bump commit for `+49` is `fbeaddb6`); re-run `scripts/verify_versioncode_available.dart` at the bump.
- F7. The compile-time define pattern exists: `AppConstants.razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID')` (`app_constants.dart:196`), `bool.fromEnvironment('dart.vm.product')` (`ist_date.dart:21`).
- F8. `live_schema_columns.json` `subscriptions`: `id, user_id, plan, status, start_date, end_date, razorpay_order_id, razorpay_payment_id, razorpay_signature, created_at, razorpay_subscription_id, cancelled_at`. There is no `subscription_events` table (ADR-0019 deferred it to "the Play batch"). `unique_razorpay_payment_id` is the arbiter of migration 161 `record_paid_subscription`.
- F9. Unverified (needs a live check at U1/section 8, not assumed): that the `purchases_flutter` release available in November 2026 bundles a Billing Library version Google still accepts for new uploads, that its merged manifest carries `com.android.vending.BILLING`, and that Gradle/AGP in this repo accepts it.

## 2. Builds and versionCodes

Play requires a unique versionCode per uploaded bundle; the same bundle can be released to several tracks. Gate 2 / 2.5 of `/build-apk` apply to every row below; each bump is its own `chore: bump versionCode` PR (the founder's approved flow), merged with `scripts/safe_pr_merge.sh`.

| Build | versionCode | What it is | Track | Mode (`ANDROID_PURCHASE_MODE`) |
|---|---|---|---|---|
| Submitted | `+49` | Razorpay AAB, no billing library | production review (already applied) | `razorpay` (as built) |
| **No-purchase fallback + dormant billing library** | **`+50`** | U1-U6: the `purchases_flutter` dependency (never initialised), the resolver, PaywallSheet and every upgrade surface neutral on Android | internal testing first (device check, and it unlocks the Console); **production if Google refuses OR approves `+49` (Q3)** | `none` |
| **RevenueCat live** | **`+51`** (first of the section-8 builds) | Play Billing through RevenueCat, mirrored by webhook | internal, then closed, then production | `play_billing` |

**Founder decision 2026-11-20 (Q1): ONE build.** `+50` serves both purposes (one AAB: the Console unlock and the fallback). The cost, accepted: Monetize > Subscriptions and license testers stay locked until U1-U6 are reviewed, merged and built. Mitigation if the wait hurts: U1 alone can be built as a throw-away internal AAB at the next free versionCode (it behaves as `+49`), but that spends a versionCode and is NOT planned.

Rules that follow:
- Each versionCode bump is its own `chore: bump versionCode` PR (Gate 2 / 2.5 of `/build-apk` apply), merged with `scripts/safe_pr_merge.sh`; `+50` and `+51` are never reused or re-uploaded.
- Founder, 2026-11-20: Android testers seeing no Razorpay purchase is accepted (that is the direction of travel), so a closed-testing release of `+50` is allowed too. Tracks are independent in Play Console and a bundle can sit on several. Still unverified: whether an internal-track upload alone unlocks Monetize > Subscriptions (if not, release the same bundle to closed), and how a new closed-track release interacts with the pending production application, so hold the closed track until Google answers `+49`.
- `+50` goes to internal testing first. If Google refuses `+49`, the SAME bundle is released to production (a bundle can be released to several tracks), so no second AAB is needed.
- **If Google APPROVES `+49`** (founder Q3, 2026-11-20): release `+50` to production right away, so no public Android build sells through Razorpay.
- **A production release of `+50` is the store launch for Android** (CLAUDE.md section 1: accounts stay testers until the store launch). So the server-sent copy decision in 5.4 must be taken BEFORE `+50` goes to production (round 2 #2); it does not block the internal upload.
- The release default of the flag is `none` (section 3, founder-approved Q7), so a forgotten define can never put a purchase UI in a store build. `+49` predates the flag.

## 3. The release flag

**Design.** A compile-time define, not a Hive key and not RemoteConfig: the fallback is a different binary, the behaviour must be fixed at build time, and a runtime flag could be flipped on a device that is already in review. §4.6's "old path preserved, reachable when the gate is closed" is satisfied by mode `razorpay`, which keeps today's code path byte-for-byte.

```
enum PurchaseMode { razorpay, none, playBilling }

PurchaseMode resolvePurchaseMode({
  required bool isWeb,              // kIsWeb
  required bool isRelease,          // bool.fromEnvironment('dart.vm.product')
  required String raw,              // String.fromEnvironment('ANDROID_PURCHASE_MODE')
})
```
Truth table (no platform input: the repo's own `dart.vm.product` is false in `flutter test` and in debug, so tests and the `debugDefaultTargetPlatformOverride = windows` widget tests keep today's behaviour; round 1 #2, #8):
- web: always `razorpay` (the web checkout is unchanged, ADR-0019; the define is ignored).
- non-web with a valid define (`razorpay` | `none` | `play_billing`): that value.
- non-web, define absent or unrecognised: **release builds -> `none`; debug, profile and tests -> `razorpay`**, on every platform. Safe by default for a store build.

Getters (round 1 #1): `showsPurchaseUi` and `showsRazorpay` are true ONLY in `razorpay`. `playBilling` is a value the resolver accepts but, in the `+50` code, behaves exactly as `none` (no reader of `showsPlayBilling` exists until section 8 is built); `/build-apk` refuses `--purchase-mode=play_billing` until section 8's plan is accepted. Defence in depth: `RazorpayService.openCheckout` (`razorpay_service.dart:117`) returns through `onFailure` before it creates an order when `showsRazorpay` is false (web is always `razorpay`).

Files: `lib/core/constants/purchase_mode.dart` (the pure resolver, a thin `PurchaseMode.current` that reads `kIsWeb`, `bool.fromEnvironment('dart.vm.product')` and `String.fromEnvironment('ANDROID_PURCHASE_MODE')` at call time, and a `@visibleForTesting` override). The mode is a build-time constant, not state, so there is NO provider (round 2 #8): the stateless widgets that need it (`ProPillButton`, `ProLockedOverlay`, the phase-variant body, which have no `ref` and are pumped without a `ProviderScope`, e.g. `pro_pill_button_test.dart:22-29`) read `PurchaseMode.current` directly, and the banner provider reads it the same way. There is no `lib/core/providers/` directory either. `PurchaseMode.current` must not use `dart:io Platform` or `defaultTargetPlatform` (CI runs on Linux, so `Platform` would put every existing test in `none`). No widget reads `kIsWeb` for this decision.

**Verification handle on the device.** Round 1 #3: Settings is NOT linked from the app (`settings_screen.dart:42-47`: reachable only by its route), so the line cannot live there. Instead a ghost line at the bottom of the Profile tab, `v1.0.0+50 · purchases: none` (all modes; `profile_content.dart`), so the founder can see which binary is on the phone; the sign-in screen footer (`sign_in_screen.dart:515`) already prints the version and is left alone. (Founder agreed to a build line in Q5; its place moved from Settings to the Profile tab because Settings is unreachable. Round 2 #13 noted the line also shows to a Play reviewer: kept on purpose, it is a ghost mono version string like the sign-in footer's, and it is the only on-device proof of the binary's mode.)

**Build wiring.** `/build-apk` passes `--dart-define=ANDROID_PURCHASE_MODE=<mode>` and, for `--bundle`, REQUIRES a `--purchase-mode` argument (hard fail, no default; `play_billing` refused until section 8 is accepted), records it beside the AAB's size and md5 in the ledger entry, and refuses `razorpay` for a `--bundle` unless the argument is `--purchase-mode=razorpay --i-know-this-sells-on-android`. A release APK built WITHOUT the define now has no purchase either, so a founder device check of the Razorpay path on a release build needs `--purchase-mode=razorpay` (round 2 #18; debug builds and the Patrol device tests, which run debug per `scripts/run-device-tests.sh:66-71`, are unaffected). (Edit to `.claude/commands/build-apk.md` in U6; the founder initiates every build.)

## 4. The fallback PaywallSheet (mode `none`)

`PaywallSheet.build` returns `PaywallUnavailableBody` (new, `lib/shared/widgets/paywall_unavailable_body.dart`) when `showsPurchaseUi` is false (modes `none` and `playBilling`). It is the SAME sheet entered through the SAME `showPaywallSheet` (rule 7: still one paywall), so the 32 call sites need no edit. In mode `razorpay` the build method is untouched (a source pin and the existing paywall tests prove it).

| Element | Today | Mode `none` |
|---|---|---|
| Eyebrow | `GO PRO` | `PRO` (neutral; no call to action) |
| Title | `paywallLetterheadTitle(feature)` | unchanged (names the locked feature) |
| Subtitle | per-feature copy; default `Upgrade to PRO and unlock your full potential.` | per-feature copy kept (descriptive); only the default (`paywall_sheet.dart:172`, `Upgrade to PRO and unlock your full potential.`) loses the verb; the `Higher daily AI coach limit` subtitle (`:141-142`) has none |
| Benefit card | `WHAT YOU UNLOCK` + 9 bullets | kept; label becomes `WHAT PRO INCLUDES` |
| Plan cards, price, `SAVE n%`, `₹x/mo` | shown | **removed** |
| Referral-trial stacking line | shown to a trial user | **removed** (it talks about buying) |
| Promo box + `validate-promo` | shown | **removed**; no network call |
| Primary button | `UPGRADE TO PRO` | **removed** |
| Neutral card | none | DRAFT: `PRO isn't available to buy in this app yet. Already PRO? Sign in with the same account.` |
| Buttons | `MAYBE LATER`, `RESTORE` | `CHECK MY PRO STATUS` (the existing `_handleRestore` logic: `refreshFromSupabase`, then `PRO restored successfully` / `No active subscription found...`), `CLOSE` |
| Website, price, store mention | n/a | **none** (Play steering rules) |

Telemetry: `paywall_shown` and `paywall_dismissed` keep their exact messages in every mode (the funnel series do not break); mode `none` adds one extra event, `paywall_unavailable_shown` (`feature=<raw>`), so the dead-end rate is measurable. `_upgradeTapped` is never set in mode `none`.

The copy is a DRAFT. Before U2 ships: Wardroom voice (`lib/shared/widgets/wardroom/CLAUDE.md`, no em dashes in new copy) and `psychology-pass-fitness`, because this card is the last thing a free user sees at a locked feature and a bare "not available" reads as a broken app. The founder approved the sentence and `CLOSE` as drafted (Q4b). One note for the copy pass (round 1 #18): the sentence says "Sign in with the same account" to a user who is already signed in; the pass should decide whether to keep it (it still reads right to someone who bought on the web under another email) or rephrase.

The phase variant sheet (`showPaywallSheetPhaseVariant`) gets the same treatment inside its own file: no price line, no `UPGRADE TO PRO  →`; its button becomes the same neutral body, so U2 owns both files.

## 5. Audit of every upgrade surface

### 5.1 The 32 `showPaywallSheet(` call sites (all land on the one sheet; behaviour in mode `none` = section 4)

| # | File:line | Reached by | Feature string | Visible label BEFORE the tap | Disposition |
|---|---|---|---|---|---|
| 1 | `home/screens/home_screen.dart:614` | expiry banner RENEW | `PRO` | `RENEW` | surface suppressed (5.3) |
| 2 | `profile/screens/profile/subscription_section.dart:195` | FREE PLAN `UPGRADE` chip | `PRO` | `UPGRADE` | surface suppressed (5.3) |
| 3 | `profile/screens/profile/profile_content.dart:221` | PRO pill, free user | `PRO Upgrade` | `GO PRO` pill | label becomes `PRO` info (5.2) |
| 4 | `profile/screens/profile/profile_content.dart:322` | Weekly report card | `Weekly AI Report` | `Upgrade for weekly reports` | copy neutral (5.2) |
| 5 | `profile/screens/profile/profile_content.dart:398` | locked notification row | per row | row lock glyph | none (sheet only) |
| 6 | `profile/screens/settings_screen.dart:26` | locked notification row (settings) | per row | row lock glyph | none |
| 7 | `profile/screens/reports_screen.dart:230` | server refusal after the one free report | report title | Generate button | none |
| 8 | `profile/screens/reports_screen.dart:1029` | generate again, not PRO | report title | Generate button | none |
| 9 | `profile/screens/progress_photos_screen.dart:263` | refusal path, not PRO | `Progress Photos` | none (action) | none |
| 10 | `profile/screens/progress_photos_screen.dart:420` | Add photo, lapsed | `Progress Photos` | Add button | none |
| 11 | `profile/screens/progress_photos_screen.dart:470` | `ProLockedOverlay` | `Progress Photos` | `Upgrade to PRO` (default `ctaText`) | copy neutral (5.2) |
| 12 | `profile/screens/edit_profile_screen.dart:1489` | strategy chip, free | `Diet Strategy` | chip | none |
| 13 | `profile/screens/edit_profile_screen.dart:1845` | body-fat assessment | `AI Body Composition Assessment` | button | none |
| 14 | `profile/screens/edit_profile_screen.dart:1890` | server `pro_required` | same | none (action) | none |
| 15 | `nutrition/widgets/food_logger_section.dart:162` | AI food analysis, limit | `AI Food Analysis` | button | none |
| 16 | `nutrition/widgets/scan_meal_section.dart:181` | scan meal, free | `Scan Meal` | button | none |
| 17 | `nutrition/widgets/cart_auditor_section.dart:165` | cart auditor, free | `Cart Auditor` | button | none |
| 18 | `nutrition/services/diet_strategy_actions.dart:136` | strategy gate | `Diet Strategy` | chip | none |
| 19 | `nutrition/services/diet_supplements_actions.dart:53` | supplements gate | `Diet Supplements` | switch | none |
| 20 | `ai_coach/screens/ai_coach/screen.dart:252` | send at the free cap | `Higher daily AI coach limit` | none (action) | none |
| 21 | `ai_coach/screens/ai_coach/input_bar.dart:276` | counter row link | same | `GO PRO` | link hidden (5.2) |
| 22 | `ai_coach/screens/ai_coach/input_bar.dart:377` | limit-state composer tap | same | `Daily limit reached — Go PRO` (`:313`) | copy neutral (5.2) |
| 23 | `ai_coach/screens/ai_coach/status_pill.dart:48` | status pill, free | same | `UPGRADE` | copy neutral (5.2) |
| 24 | `ai_coach/screens/ai_coach/compact_header.dart:138` | overflow menu | same | `Upgrade to PRO` (`:279`) | **menu item removed** (5.2) |
| 25 | `ai_coach/screens/ai_coach/media_picker.dart:18` | paperclip | `Photo Analysis` | glyph | none |
| 26 | `ai_coach/screens/ai_coach/media_picker.dart:163` | pick image gate | `Photo Analysis` | none (action) | none |
| 27 | `ai_coach/screens/ai_coach/attach_button.dart:48` | locked tile | `Photo Analysis` | lock tile | none |
| 28 | `train/screens/train/phase_unlock_card.dart:81` | unlock card | `Phases 2-12` | card text (label audited in U1: not in the upgrade-literal list) | none |
| 29 | `train/widgets/plan_expired_card.dart:112` | plan-expired card button | `Phases 2-12` | `Deploy to Phase $nextPhase — go PRO →` (`:264`) | copy neutral (5.2); event `phase_1_day_29_upgrade_tapped` unchanged |
| 30 | `train/screens/graduation_screen.dart:347` | graduation gate | `Phases 2-12` | none (action) | none |
| 31 | `train/widgets/swap_picker_sheet.dart:232` | spent-swaps sheet `See PRO` | `Day Swaps` | `See PRO` | copy neutral (5.2) |
| 32 | `shared/widgets/paywall_sheet_phase_variant.dart:131` | variant button | `Phases 2-12` | `UPGRADE TO PRO  →` | the variant itself changes (section 4) |

"none" means: the control that opens the sheet is a feature control (a button, chip or lock), not an upgrade call to action, so nothing outside the sheet changes. Rows 3, 4, 11, 21-24, 29 and 31 carry upgrade wording and are in 5.2.

### 5.2 Surfaces that carry upgrade wording (the "other surfaces" the memory file asked for)

| Surface | File:line | Wording | Mode `none` |
|---|---|---|---|
| Profile PRO pill | `shared/widgets/pro_pill_button.dart:45`, used `profile_identity.dart:257` | `GO PRO` | label `PRO` for free users; tap still opens the neutral sheet (a free user can still read what PRO includes) |
| Profile free-plan card chip | `subscription_section.dart:202` | `UPGRADE` | chip hidden; the usage meters stay |
| PRO card (paid user) | `subscription_section.dart:109`, `wardroom_copy.dart:518,617` | `RENEWS <date>` / `ACTIVE · RENEWS ... · {price}` | out of scope: paid-state display; the `{price}` token on `:617` belongs to `settingsSubStatusTemplate` (`:616-617`), which has no reader in `lib/` or `test/` (round 2 #14): nothing to do |
| Subscription card widget | `profile/widgets/subscription_card.dart:95,216` | `Renews on`, `Upgrade to PRO` | **no construction site** (rounds 1 and 2 and my grep agree): delete in U1 as dead code (4.6.4); its reader-allow entry `docs/sot_registry.yaml:9966` goes in the same commit |
| Deep analysis card (dead twin) | `ai_coach/widgets/deep_analysis_card.dart:24,173` | `UPGRADE TO PRO` | **no construction site in `lib/` or `test/`, and left alone**: it belongs to OI-304 (`docs/audit/open_issues.md:5144`, blocked on founder decision D2, mount or delete, together with `InsightCard`); the closure ledger records it `verified_clean` (unreachable). The card the welcome view really builds is `CoachDeepAnalysisCard` (`welcome_view.dart:21`), which has no upgrade text and routes to `/profile/reports` (`coach_deep_analysis_card.dart:27`); a free user's Generate tap there reaches the neutral sheet (rows 7 and 8) |
| Plan-expired button | `train/widgets/plan_expired_card.dart:264` | `Deploy to Phase $nextPhase — go PRO →` (round 1 #4) | `Deploy to Phase $nextPhase →`, same tap |
| PRO subscription detail sheet | `profile/screens/profile/screen.dart:278-281` | `Your PRO subscription is handled by Razorpay and auto-renews by default...` (round 1 #7) | WRONG in every mode today (ADR-0019: one-time orders do not auto-renew) and Razorpay-specific. Fixed in all modes by the `fix(profile)` commit U4a: `Your PRO plan is managed on your account. To change it or ask for a refund, reach out to us and we'll sort it within 24 hours.` The web copy changes with it, which is why U4a is a `fix:` with a diagnose-doc (round 2 #11) |
| Delete-account screen | `delete_account_screen.dart:285,315` | `Cancel your active subscription (no refund...)`, `Your Razorpay payment receipts (Razorpay retains these...)` | **kept unchanged**: factual data-retention text for a web-paid user, no price and no purchase path (round 2 #11); revisited with the Play-subscription case in the section 8 plan (board card `l3-delete`) |
| Profile website row | `profile_content.dart:477-481` | `icanbefitter.com`, `Visit the website` | hidden in `none` (round 2 #10, conservative: a store reviewer may read any website link as steering; the privacy and terms links are separate rows and stay) |
| Phase unlock card, phase 2 preview card | `phase_unlock_card.dart:59-70` (`UNLOCK PHASE 2`), `phase2_preview_card.dart:217-227` (`WHAT PHASE 2 UNLOCKS`, `Phases 2-12 unlock full 48-week journey`), kept paywall subtitles `paywall_sheet.dart:138,142` (`Unlock progressive phases...`, `Unlock advanced reasoning...`) | feature descriptions and gate entries (round 2 #7) | **stay**: they describe locked content and their tap opens the neutral sheet; the copy pass confirms the wording; test 4 has a row for the unlock button reaching the neutral sheet |
| Home expiry banner | `shared/widgets/subscription_expiry_banner.dart:36-37,89,100`; provider `home_provider.dart:550` | `RENEW`, `RENEW TO STAY PRO` | suppressed at the PROVIDER (`subscriptionExpiryBannerProvider` returns `show: false`), not in the widget, so no caller can render it |
| Locked overlay | `shared/widgets/pro_locked_overlay.dart:43,55` | default `ctaText = 'Upgrade to PRO'` | default becomes `See what PRO includes`; the only caller is `progress_photos_screen.dart:465` |
| Coach status pill | `status_pill.dart:7,63` | `UPGRADE` | `PRO` info pill, same tap |
| Coach counter link | `input_bar.dart:279,313` | `GO PRO`, `Daily limit reached — Go PRO` | link text hidden and hint `Daily limit reached`; the `if (isWarning) ...[` shape and the limit-state composer tap that opens the (neutral) sheet stay, so the source pin of `coach_go_pro_cta_reachable_test.dart:46` holds |
| Coach overflow menu | `compact_header.dart:273-279` | `Upgrade to PRO` | item removed |
| Weekly report card | `profile/widgets/weekly_report_card.dart:68,106` | `Upgrade for weekly reports` / `Upgrade for Reports` | `Weekly reports are a PRO feature` |
| Prediction card | `profile/screens/profile/prediction_card.dart:38` | `Upgrade in Profile → Subscription` | `Prediction refresh is a PRO feature` |
| Day-swap sheet | `swap_picker_sheet.dart:232` | `See PRO` | unchanged (already neutral) |
| Phase roadmap CTA + locked rows | `phase_roadmap_screen.dart:183,175,294` | `UPGRADE TO PRO  →` | label neutral; opens the neutral variant |
| Preview-workout CTA | `preview_workout_screen.dart:232,224` | `UPGRADE TO PRO  →` | same |
| Phase variant price line | `paywall_sheet_phase_variant.dart:152-160` | `₹349 / month · ₹2,999 / year (save 28%)` | removed |
| Nutrition limit message | `nutrition_provider.dart:962` | `...or upgrade to PRO.` | `Try again tomorrow.` |
| Coach error strings | `ai_coach_provider.dart:843,1253` | `Photo analysis is a PRO feature. Upgrade to unlock it.` / `This feature requires PRO. Upgrade to unlock it.` | drop the second sentence |
| Coach canned replies (client twins) | `ai_coach/copy/coach_replies.dart:24-35,112` | `[Upgrade to PRO →]` | **not changed** (round 2 #1): `test/contracts/coach_replies_test.dart` pins every server key to a byte-identical client twin, and only `chatRateLimitedFromError` is called from `lib/` (`ai_coach_provider.dart:1245`); the text really reaches users from `ai-media-proxy`. Handled with the server surfaces in 5.4 |
| Coach canned replies (server) | `supabase/functions/_shared/coach_replies.ts:19,62,65` | `[Upgrade to PRO →]` | **ships to every client**: the server copy cannot know the build; see 5.4 |
| Payment copy | `core/copy/payment_copy.dart:20` | `You can subscribe once they end.` | unreachable in mode `none` (purchase never starts); leave |

### 5.3 Where each suppression lives (single writer rule)

One writer per decision, so a new caller cannot reintroduce a surface: the mode is read in exactly two kinds of place, (a) a provider or pure function that decides WHETHER a surface exists (`subscriptionExpiryBannerProvider`, a pure function `showsUpgradeAffordance()` in `purchase_mode.dart` (reads `PurchaseMode.current`) for the chip / pill / menu item) and (b) the strings in a new `lib/core/copy/purchase_copy.dart` (const-only, no em dashes) keyed by mode. Widgets call the copy file; none compares the mode itself except `PaywallSheet.build`.

### 5.4 Server-sent surfaces (cannot see the build)

- Server-sent copy reaches every client and cannot see the build: `_shared/coach_replies.ts:14,19,62,65,67` (`[Upgrade →]` / `[Upgrade to PRO →]`, sent by `ai-media-proxy/index.ts:334,382,1089`), `expiry-reminder/index.ts:171` (`Renew to keep your data and features.`) and, round 1 #6, the AI coach system prompt `_shared/captain_manual.ts:111,130` (it quotes `PRO: ₹349/month or ₹2,999/year`, used by `ai-proxy`, so the coach can answer "how do I upgrade" with a price). The client twins of the canned replies are pinned byte-identical to the server file, so they cannot change alone.
- **Round 2 #2: this is NOT a pre-launch-only matter.** A production release of `+50` is the Android store launch (section 2), so these strings reach a store build whose paywall promises "no price, no link". Fixing them means an Edge Function change (a mode-aware prompt: the client sends `purchase_mode` in the snapshot and `captain_manual.ts` drops the price lines; neutral wording for the canned replies and the expiry push) plus a deploy, each with its own explicit go (CLAUDE.md 4.3) and its own plan. That work is NOT in units U1-U6 and this plan does not pretend it is.
- Terminal state in the closure ledger: `blocked_on_user`, reason: the founder decides, BEFORE any production release of `+50`, between (a) a separate Edge Function plan that makes the server copy neutral first, and (b) accepting the server-sent wording in the store build. It does not block the internal-testing upload. I add it to `GO_LIVE_CHECKLIST.md` section 0 as item 0.4 in U6 and as a board card.
- `create-razorpay-order` stays callable by a build that has no purchase UI; that is fine (it needs a token and the 409 guard) and is not removed.

### 5.5 Entry points that are NOT upgrade surfaces and stay

Referral redemption (free 7 days; `referral_copy.dart:11-19` says a friend "subscribes", which describes the referral reward and names no price or place: kept, noted for the copy pass; the share message in `lib/features/profile/screens/invite_friends_sheet.dart:153-158` has no purchase wording), restore (`CHECK MY PRO STATUS`), account sign-in (an existing web-bought PRO user signs in and `refreshFromSupabase` unlocks it). The PRO user's own subscription detail sheet is NOT in this list any more: its text is wrong today and is fixed in U4a (5.2). The Profile website row moved to 5.2 (hidden in `none`). A tester who paid before the update: the retries in `RazorpayService` are in-memory timers (`razorpay_service.dart:980-982`) lost when the app is killed; the real recovery is `refreshFromSupabase` at launch, and that is unchanged.

## 6. Units

Order and dependencies: U1 -> (U2, U3, U4 in any order) -> U5 -> U6. Each unit is committed separately, only when the founder asks.

| Unit | Content | Files (new unless marked) |
|---|---|---|
| **U1** | `purchases_flutter` dependency (EXACT version, chosen after F9 is verified), `PurchaseMode` resolver + `current` + override (no provider), the `openCheckout` guard, the Profile footer line, delete the dead `SubscriptionCard` (and its registry entry), merged-manifest check for `BILLING` | `pubspec.yaml` (mod), `pubspec.lock`, `lib/core/constants/purchase_mode.dart`, `razorpay_service.dart` (mod), `profile_content.dart` (mod), `subscription_card.dart` (deleted), `docs/sot_registry.yaml` (mod) |
| **U2** | `PaywallSheet` none-body, phase-variant none-body, telemetry | `paywall_sheet.dart` (mod), `paywall_unavailable_body.dart`, `paywall_sheet_phase_variant.dart` (mod) |
| **U3** | Suppress or neutralise 5.2 surfaces in `lib/features/{profile,home,ai_coach,train,nutrition}`, `purchase_copy.dart`, `showsUpgradeAffordance()`, banner provider | list in 5.2 |
| **U4** | `payment_copy.dart` review and the coach error strings (`ai_coach_provider.dart:843,1253`), the nutrition limit string; each extracted into a pure copy function so test 4 can reach it | `lib/core/copy/*`, `ai_coach_provider.dart`, `nutrition_provider.dart` |
| **U4a** (two `fix(profile)` commits, each with a slim diagnose-doc and regression test, rule 22) | (1) the PRO subscription detail sheet text (5.2); (2) the referral share link names Play package `com.icanbefitter.avya` (`invite_friends_sheet.dart:154`) but the app's applicationId is `com.icanbefitter.icanbefitter` (`android/app/build.gradle.kts:20,35`; the Rate App row `profile_content.dart:590` already uses the right one), so a shared link points at the wrong listing: found by review round 2, fixed here, not deferred (4.2) | `profile/screen.dart`, `invite_friends_sheet.dart`, `docs/diagnoses/*` |
| **U5** | Tests (section 7), SoT registry entry, blast-radius check | `test/**` |
| **U6** | Docs: `docs/architecture/payment.md` + `subscription.md` (mode section), `GO_LIVE_CHECKLIST.md` (0.1 closed, 0.4 added), `docs/naming_conventions.md` (`PurchaseMode`, `ANDROID_PURCHASE_MODE`, `PaywallUnavailableBody`), root `CLAUDE.md` section 2 Payments row, `.claude/commands/build-apk.md` (mode argument), `docs/sot_registry.yaml` (the new concept AND a recompute of EVERY existing range for EVERY file an earlier unit edits, round 2 #9: per file the registry holds `paywall_sheet.dart` several entries (round 1 found `:1302`, `:18658`, `:19618-19621`), `razorpay_service.dart` 10, `profile/screen.dart` 10, `home_provider.dart` 26, `ai_coach_provider.dart` 19, `nutrition_provider.dart` 23, `profile_content.dart` 3, `home_screen.dart` 18, `delete_account_screen.dart` 2; re-grep, compute from anchors; plus the `subscription_card.dart` entry that U1 removes), `docs/audit/...closure.yaml` | docs |

The one thing U1 must not do: call `Purchases.configure` or import `purchases_flutter` from any file under `lib/`. A source pin (U5) fails if `lib/` imports the package before section 8's plan is accepted; that is what "dormant" means here, and it is why `+50` behaves as `+49`.

Not in this plan: removing `razorpay_flutter` (checklist 2.6; it needs the web and any later iOS path checked, and the `NFC` / `READ_BASIC_PHONE_STATE` permissions are only a suspected consequence). Closure ledger entry: `upstream_blocked`, `reopen_when: the +50 bundle is accepted by Play and web / any later iOS dependence on the plugin is checked`; filed as an OI with `scripts/mint_oi.sh` at close. U6 also adds to `.claude/commands/build-apk.md` the note that a release APK needs `--purchase-mode=razorpay` for any Razorpay device check.

## 7. Tests (rule 21: each must FAIL without the change; each is mutated once)

1. `test/contracts/purchase_mode_resolver_test.dart`: the full truth table of section 3 (web x release x raw, including unrecognised raw, empty raw and `PLAY_BILLING` upper-case; `playBilling` yields `showsPurchaseUi == false`). Mutants: web returns `none`; release default `razorpay`; unknown raw accepted; `showsPurchaseUi` true for `playBilling`.
1b. `test/contracts/purchase_mode_current_wiring_test.dart` (source, comment-stripped, presence only with a reason; round 1 #2): `PurchaseMode.current` reads `kIsWeb`, `bool.fromEnvironment('dart.vm.product')` and `String.fromEnvironment('ANDROID_PURCHASE_MODE')`, and contains no `dart:io` import, no `Platform.` and no `defaultTargetPlatform`. It also pins the call's named arguments (`isWeb: kIsWeb`, `isRelease: bool.fromEnvironment('dart.vm.product')`, `raw: String.fromEnvironment('ANDROID_PURCHASE_MODE')`). Mutants: hard-code `isRelease: false`; drop the define read; use `Platform.isAndroid`; swap `isWeb` and `isRelease`. The behavioural proof of the real binary is the on-device footer line (section 3) and section 10.
2. `test/contracts/paywall_mode_none_behavioral_test.dart`: pump the real `PaywallSheet` with the override `none` and again with `playBilling`: no `₹`, no `UPGRADE TO PRO`, no `TextField`, no promo `APPLY`; one `CHECK MY PRO STATUS` that calls `refreshFromSupabase` once (fake service) and shows the PRO / not-PRO snackbar; zero `openCheckout` calls and zero `validate-promo` calls (as built, 2026-11-20: no counted `callFunction` seam was needed, because the none-mode build returns before the promo field and every purchase button exist, so those calls are unreachable from the widget and the test pins their absence from the tree plus the `openCheckout` guard in test 2b; the `implements` + `noSuchMethod` fakes cover the private-constructor services); `paywall_shown` message byte-equal to today's; `paywall_dismissed` fires on close in `none` (so a mutant that sets `_upgradeTapped` reddens it, `paywall_sheet.dart:116,195`); the extra event fires once. Same file, mode `razorpay`: both plan cards, the promo box and the button are present. This pins the shipped behaviour of mode `razorpay`; it is NOT the 4.12.4 ship-dark proof, because the release default is `none`, not `razorpay` (stated deviation from 4.6: the old path stays reachable by the explicit define and is the test default; round 1 #19).
2b. `test/contracts/razorpay_open_checkout_mode_guard_test.dart`: with the override `none`, `openCheckout` calls `onFailure` and makes no order-create call. Mutant: remove the guard.
3. `test/contracts/paywall_phase_variant_mode_none_test.dart`: no price line, no purchase button, in `none`; present in `razorpay`.
4. `test/contracts/purchase_surfaces_mode_none_test.dart` (round 1 #9: every 5.2 row is listed, none left to "etc."): behavioural rows for the Profile PRO pill label, the Profile chip, the expiry-banner provider (`show == false`), the locked overlay default text, the coach status pill, the coach counter link and limit hint, the coach overflow menu, the weekly report card, the prediction card, the phase roadmap CTA, the preview-workout CTA, the plan-expired button, the Profile website row, the phase unlock button reaching the neutral sheet, and the Profile footer line; each also asserted unchanged in `razorpay`. Rows with no testable widget seam (the nutrition limit string, the two coach error strings, the client canned replies) are tested as the pure copy function that returns them, which U3 / U4 must extract so the string has one source.
5. `test/contracts/purchase_literal_inventory_test.dart` (source, presence only, comment-stripped; a TEST, not a gate, no `check_*.dart` script, so rule 24 does not apply; rounds 1 #10, 2 #6): it counts, per file under `lib/`, only the words that sit INSIDE string literals (so identifiers like `needExerciseUpgrade` in `seed_service.dart:264-294` are not counted), case-insensitive: `go pro`, `upgrade`, `renew`, `subscribe`, `unlock`, `purchase`, `₹` and `\u20B9` (both spellings, `paywall_sheet.dart:538,807,822` use the escape), `monthlyPriceInr`, `yearlyPriceInr`. The expected counts live in a table inside the test; a new file, a changed count or an unlisted file fails with a message that says "classify this surface in section 5.2 and update the table". A literal restored inside an allowlisted file changes that file's count and fails. Measured size on `a1849656`: 300 raw hits in 71 files, 137 lines in 40 files after comment stripping; the in-literal subset is smaller and is measured in U5 before the table is written. Behavioural counterpart: test 4. Registered in `docs/sot_registry.yaml` with `behavioral_test_path:` pointing at test 4.
5b. U4a regression tests: `test/contracts/profile_subscription_sheet_copy_test.dart` (the pure copy function no longer says `Razorpay` or `auto-renews`; mutation: restore the old sentence) and `test/contracts/referral_share_play_id_test.dart` (the Play id in `invite_friends_sheet.dart` equals `applicationId` in `android/app/build.gradle.kts`; mutation: restore `com.icanbefitter.avya`).
6. `test/contracts/purchases_package_dormant_test.dart` (source): no file under `lib/` imports `purchases_flutter`; `pubspec.yaml` pins an exact version. Presence only (a reason in the registry).
7. Existing tests: they run with `dart.vm.product` false, so the resolver returns `razorpay` and they stay green by construction EXCEPT where they pin source text. The 4.1.5 sweep runs BEFORE U2 starts over `test/` and `supabase/functions/`; the set found so far (round 1 #8) is: `coach_go_pro_cta_reachable_test` (`:46` pins `if (isWarning) ...[`), `progress_photos_screen_gate_test` (`:534-541` desktop override, expects `Upgrade to PRO`, `ctaText` is a `const` default so U3 makes it a nullable parameter resolved in `build`), `pro_pill_button_test` (`:29`, `GO PRO`), `coach_composer_speech_test` (`:313`), `telegram_surface_removed_test` (`:168,219,233`, pins `UPGRADE TO PRO` / `Upgrade to PRO` on the compact header menu), `coach_replies_test` (NOT repointable and not edited: it pins the client twins to the server file, 5.4), `subscription_expiry_banner_test` (`:143`) and `_behavioral_test`, `swap_picker_sheet_test` / `day_swap_copy_test` (`See PRO`, unchanged), `paywall_feature_label_test`, `paywall_generic_upgrade_title_behavioral_test`, `razorpay_web_kill_switch_test`, `paywall_trial_stacking_notice_test`. Any source-grep that pins a changed label is REPOINTED, never loosened.
8. Mutation matrix (self-attested, applied and confirmed with `grep -c`): U2 remove the `showsPurchaseUi` branch (tests 2, 3 red); U3 return `show: true` in `none` (test 4 red); U3 restore one literal inside an allowlisted file (test 5 red); U1 import `purchases_flutter` in a `lib/` file (test 6 red); U1 flip the release default (test 1 red); U1 hard-code `isRelease: false` in `current` (test 1b red); U1 remove the `openCheckout` guard (test 2b red).

Verification before review dispatch (4.12.8): `flutter analyze --no-fatal-infos` on the WHOLE project, the pre-commit gate loop, and the full suite from CI (PR, `sh scripts/land_pr.sh <pr> --ci-only` in the background). On-device: build with `--dart-define=ANDROID_PURCHASE_MODE=none` and walk the 32 sites (the OI-348 style table, new rows A23+) before `+50` is uploaded; plus one check on the AAB: its merged manifest contains `com.android.vending.BILLING` (bundletool or `aapt2 dump`), and the Console Subscriptions page lets the founder create a product after the upload.

## 8. RevenueCat plus Play Billing (DESIGN ONLY; its own plan, review and hermes pass before any code)

Class: **catastrophic** (a new payment writer, a schema change, entitlement). Nothing here is built by units U1-U6.

**8.1 Products and identity**
- Play Console: one subscription `pro` with base plans `monthly` and `yearly` (auto-renewing). RevenueCat: entitlement `pro`, one offering `default` with two packages. Intro offer: none at launch (Q2).
- RevenueCat App User ID = the Supabase user id: `Purchases.configure(PurchasesConfiguration(<public Google SDK key>)..appUserID = <uid>)` after a session exists; `Purchases.logIn(uid)` on a user switch; `Purchases.logOut()` on sign-out. The app never runs anonymous: no session, no purchase UI (the sheet shows the sign-in prompt path that exists today). The public SDK key is a public identifier by design (rule 9 is about secrets); it goes through `--dart-define-from-file=.env` like the Razorpay key id, plus `.env.example` and `AppConstants`. The RevenueCat secret REST key and the webhook auth value exist only as Edge Function secrets.
- Prices on the Android sheet come from the store (`StoreProduct.priceString`), never from `AppConstants`: Play shows the localised price and the sheet must match it.

**8.2 Entitlement stays server-owned (rule 19)**
The client never grants PRO from the RevenueCat `CustomerInfo`. After `purchasePackage` returns, the sheet polls the server-verified row (the same pattern as Razorpay's confirmation poll, `payment_timing.dart` constants) and `gate()` keeps calling `verifyFromServer()`. A Play `pending` purchase (cash, delayed methods) shows a "pending" state and unlocks nothing until the row exists.

**8.3 `revenuecat-webhook` Edge Function (new, verify_jwt = false)**
- Auth: a shared secret in the `Authorization` header configured in RevenueCat, compared constant-time; unset secret fails closed.
- **The webhook is a trigger, not the truth:** on each event the function re-reads the subscriber from RevenueCat's REST API (secret key) and writes from THAT, so order of delivery, retries and duplicates cannot produce a wrong end date. Idempotency additionally by `event.id` (unique) in a new `subscription_events` ledger.
- Event handling (the table the plan must pin with live SQL tests): `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE` extend or update the row; `CANCELLATION` (auto-renew off) keeps access to `end_date`; `UNCANCELLATION` restores renewal; `BILLING_ISSUE` keeps access through the grace period RevenueCat reports; `EXPIRATION` ends access; a refund or revoke ends access at once; `SUBSCRIPTION_PAUSED` ends access until resumed; `TRANSFER` is logged and alerted (App User ID is ours, so it should not occur); `TEST` is acknowledged. SANDBOX events are written with `environment = 'SANDBOX'` (license testers are the founder before launch).
- Kill switch: an exact-`"true"` secret `ENABLE_PLAY_BILLING_WEBHOOK` (the existing `isEnvExactlyTrue` rule); unset means acknowledge with 200 and write nothing. Cron-style telemetry is not needed (not cron-dispatched); the paid-but-no-row alert (`_shared/payment_alert*.ts`, B1) is reused for a purchase RevenueCat reports and we could not record.

**8.4 Schema (migration, rehearsed in local docker first, then its own go to apply)**
- `subscriptions`: add `source` (`razorpay` | `referral` | `play`, default `razorpay`), `store_product_id`, `store_original_transaction_id` (partial UNIQUE where not null), `auto_renew_enabled`, `last_event_ms`, `environment`. A Play subscription is ONE row updated in place on renewal (Razorpay is one row per payment: the arbiter `unique_razorpay_payment_id` does not apply). A Play row carries `plan` = `monthly` | `yearly` (the same values as Razorpay), `source = 'play'` and NULL `razorpay_*` columns, The three `razorpay_*` columns are already nullable (migration `094_subscriptions_razorpay_nullable.sql:31-33`; `referral_trial` rows already carry NULLs; the comment at `verify-payment:577` is stale); the live constraints are still read first, no migration step is planned for it.
- **Readers that define "paid" by `razorpay_payment_id IS NOT NULL` and would miss a Play row** (round 1 #12; each needs a `source`-aware predicate in that plan): `redeem-referral/index.ts:132` (a Play subscriber could redeem a code meant for non-payers), `supabase/migrations/160_referral_hardening.sql:86,117,202` (migration 160 REPLACED the 159 bodies of `redeem_referral_atomic` and `process_referral_conversions`, the "last CREATE OR REPLACE wins" pitfall of CLAUDE.md 4.9: the section 8 plan reads the LIVE bodies with `pg_get_functiondef`; a Play friend would never reward the referrer), `admin-dashboard-data/index.ts:159-161` (buckets by plan), `delete-account/index.ts:242-246` (reads `razorpay_subscription_id`). `create-razorpay-order/index.ts:241-242` already treats any plan other than `referral_trial` as paid, so its 409 for a Play row may already hold (to be tested, not assumed).
- **A writer that changes `end_date` in place** (round 1 #11): `private.grant_referral_days` (`159_referral_reward_on_conversion.sql:89-122`) does `UPDATE subscriptions SET end_date = end_date + days` on the latest active row. If that row is a Play row, the next webhook rewrites `end_date` from RevenueCat and the added referral days vanish. Design rule for that plan: referral, free-days-code and trial days are always SEPARATE rows (`source` referral / code), `grant_referral_days` and every other in-place `end_date` writer must skip `source = 'play'` rows, and the client already reads the latest-ending active row (`subscription_service.dart:895-935`), so the entitlement is the union. Existing readers of `razorpay_*` columns (`delete-account/index.ts:228-246` and others) and the NOT NULL / CHECK state of the live table must be read from `information_schema` and `pg_constraint` at that plan's start (**not verified here**).
- New `subscription_events` (provider, provider event id UNIQUE, user id, type, product, environment, the minimal payload, received at); RLS deny-all to clients; `backups/live_schema_columns.json` regenerated in the same commit; migration number only from `scripts/mint_migration.sh`.

**8.5 Already-PRO block and the three sources**
- Client: in mode `play_billing` the sheet reads the server-verified state; an active paid or code row shows `PRO until <date>` and no purchase button. A trial user (`referral_trial`) may buy (ADR: Play cannot start later than now, so there is NO stacking on Android; the sheet says the Play subscription starts today; Q6).
- Server: `create-razorpay-order`'s door treats an active `play` row as a paid row (409 `already_pro`), so a web purchase cannot double a Play one. The webhook cannot stop a Play purchase made while the user already has web PRO (Google owns that payment); it records it and alerts, and support refunds. This is a known residue, stated, not hidden.

**8.6 Free-days codes (OI-347)** are redeemed through our own Edge Function (`source = 'code'`), identical on web and Android, no store involvement; **Razorpay on web keeps everything it does today** (one-time orders, percent-off promo, referral-trial stacking, the live-key flip of checklist section 1), and the referral reward reconciler (ADR-0021) must be extended to count `play` rows when a friend subscribes on Android (a section-8 unit).

**8.7 Other consequences to cover in that plan:** `delete-account` for an active Play subscription (tell the user to cancel in Google Play; call RevenueCat's subscriber delete for DPDP); restore = re-read the server row (the account is the identity, so there is no device-bound restore); license-tester flow and the closed-test path; rollback = unset the webhook switch (server) and ship the `none` build (client); founder metrics and `subscriptions` readers audited for `source`.

## 9. Ledger of changes to repo-wide docs this plan makes (U6) and the ones it does not

Makes: ADR-0022 (written), ADR-0005 status line ("Amended by ADR-0022"), `docs/adr/INDEX.md` (regenerate with `scripts/build_adr_index.dart`), the files in U6. Does not touch: any migration, any Edge Function, any `supabase/` file, the web build. (U2 shifts line ranges in `paywall_sheet.dart`: the registry recompute in U6 covers it.)

## 10. What "done" is for this plan

`+50` uploaded to internal testing, the merged manifest shows `BILLING`, the Console lets the founder create a subscription, and `+50` walked on a phone in mode `none` with every row of 5.1 and 5.2 checked off; the closure ledger terminal for every entry: section 8 `upstream_blocked` with `reopen_when: the founder gives the go for the RevenueCat account and F9 is verified`; the server-sent copy `blocked_on_user` (5.4); `DeepAnalysisCard` `verified_clean`; `razorpay_flutter` removal as in section 6.

## 11. Review plan (4.12)

Two independent, context-blind reviewers, sequentially (Review 2 runs on the post-review-1 plan), each briefed with `docs/agent_brief_preamble.md`, Sonnet only, allowed commands listed exhaustively, verifying every claim in sections 1, 5 and 7 against the code at file:line and the lens list from `docs/audit/LENS_REGISTRY.md` (payment, writer/reader, copy, test-mutation lenses named in the brief). A plan-review record `docs/plan-reviews/play-billing-fallback.md` with `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged` and, at platform tier, `bpass: accepted` after the `/code-review` B-pass before the merge. Round 1 and round 2 ran 2026-11-20 (a fresh context-blind Sonnet reviewer each, read-only); both reports are folded in section 13. Round 2 returned 2 P1 and 9 P2, all folded below with no design change to the units except U4a and the 5.4 terminal state; the changes since round 2 are mechanical or are decisions recorded with their reason, so no round 3 is run (precedent: `docs/plan-reviews/web-razorpay-checkout.md`, round 2 with one P1 folded).

## 12. Questions for the founder

Answered 2026-11-20 (folded into the plan above): **Q1** one build, `+50` only. **Q4 (entry points)** keep as `PRO` info: Profile pill stays as `PRO`, AI Coach pill stays as `PRO` info, the Deep analysis button and the Profile chip, expiry banner and overflow menu item are hidden. **Q5** yes, the `Purchases: <mode>` footer line. **Q7** release default `none`, `/build-apk --bundle` requires `--purchase-mode`.

Answered 2026-11-20 (second round): **Q2** no Play intro offer at launch (Console-only, can be added later without a build). **Q3** if Google approves `+49`, release `+50` to production right away so no public build sells through Razorpay on Android. **Q4b** neutral card sentence as drafted (`PRO isn't available to buy in this app yet. Already PRO? Sign in with the same account.`) and the dismiss button `CLOSE`; the Wardroom voice / psychology pass (board card p06) still runs before U2 ships. **Q6** pattern 1: a referral-trial user may buy on Play at any time; the paid plan starts today and the leftover free days are absorbed (no stacking on Android). The sheet says so in one line ("Your paid plan starts today."). Stacking through Google's defer-billing call is not planned; ledger entry `upstream_blocked`, `reopen_when: the founder asks for stacking after Play purchases are live and the defer call is verified`.

Nothing is open for the no-purchase build. Remaining non-code decisions: the app name (checklist 2.4) and Play price (default 349 / 2,999 rupees). Q5 moved: the build line lives in the Profile tab footer, not Settings (Settings is not linked).

## 13. Review round 1 dispositions (reviewer: context-blind Sonnet, 2026-11-20; every finding below was checked against the code by me before folding)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | `play_billing` mode undefined in the +50 code | FIXED: behaves as `none`; `/build-apk` refuses it; `openCheckout` guard + test 2b (section 3) |
| 2 | P1 | Release-default wiring untestable; `Platform` would break CI | FIXED: no platform input; source pin test 1b with three mutants (sections 3, 7) |
| 3 | P1 | Settings footer unreachable | VERIFIED (`settings_screen.dart:42-47`); FIXED: Profile footer line (section 3) |
| 4 | P1 | `plan_expired_card.dart:264` `go PRO →` missed | VERIFIED; added to 5.2 and row 29 |
| 5 | P2 | Deep analysis row wrong; `DeepAnalysisCard` dead | VERIFIED; row replaced, both dead widgets deleted in U1 |
| 6 | P2 | `captain_manual.ts` quotes the price | VERIFIED; added to 5.4 as a launch row |
| 7 | P2 | Subscription detail sheet text is Razorpay-specific and wrong | VERIFIED (`profile/screen.dart:278-281`); fixed in all modes in U4 |
| 8 | P2 | "Existing tests unchanged" false / list incomplete | FIXED: 7.7 rewritten with the found set and the lazy-read decision |
| 9 | P2 | Test 4 covers 7 of 21 rows | FIXED: every row named |
| 10 | P2 | Test 5 per-file allowlist cannot catch an in-file restore; gate in disguise | FIXED: per-file counts; stated as a test |
| 11 | P2 | `grant_referral_days` rewrites `end_date` in place | VERIFIED (`159:89-122`); design rule in 8.4 |
| 12 | P2 | "Paid" readers keyed on `razorpay_payment_id` | VERIFIED; inventory + `plan` value in 8.4 |
| 13 | P2 | Registry ranges for `paywall_sheet.dart` will shift | FIXED: U6 recomputes them |
| 14 | P3 | Internal contradictions (Q2/Q3, row 2) | FIXED |
| 15 | P3 | F6 wrongly "unverified" | VERIFIED (`built_versioncodes.json:43-46`); F6 corrected |
| 16 | P3 | Subtitle claim, row 7 and row 21 text | FIXED |
| 17 | P3 | Retry wording | FIXED (5.5) |
| 18 | P3 | Sign-in sentence shown to a signed-in user | NOTED for the copy pass (section 4); founder's wording kept |
| 19 | P3 | Test 2 claimed a 4.12.4 proof | FIXED: claim removed, deviation from 4.6 stated |
| 20 | P3 | `lib/core/providers/` does not exist | VERIFIED; provider goes in `service_providers.dart` |
| 21 | P3 | Website row and referral copy not classified | FIXED (5.5) |
| 22 | P3 | Section 8 / plugin removal read as deferrals | FIXED: terminal `upstream_blocked` entries with `reopen_when` named in 6 and 10 |

## 14. Review round 2 dispositions (reviewer: a fresh context-blind Sonnet, 2026-11-20; each finding checked against the code by me before folding)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | Client canned-reply edit breaks the byte-identity twin test and needs an EF deploy; the twins are mostly uncalled | VERIFIED (`coach_replies_test.dart:6,201`; only `ai_coach_provider.dart:1245` calls the class); row removed from U4, moved to 5.4 |
| 2 | P1 | Parking server copy "until store launch" contradicts releasing `+50` to production | VERIFIED; 5.4 rewritten, ledger state `blocked_on_user`, decision needed before a production release (a question to the founder) |
| 3 | P2 | 8.4 cites superseded migration bodies | VERIFIED (`160:61,129`); re-cited |
| 4 | P2 | `razorpay_signature NOT NULL` claim stale | VERIFIED (`094:31-33`); corrected |
| 5 | P2 | Deleting `DeepAnalysisCard` pre-empts OI-304; registry entry for `SubscriptionCard` | VERIFIED (`open_issues.md:5144`, `sot_registry.yaml:9966`); `DeepAnalysisCard` left alone, `SubscriptionCard` removed with its registry entry |
| 6 | P2 | Test 5 incomplete and brittle | FIXED: in-literal counts, both `₹` spellings, wider word list, measured in U5 |
| 7 | P2 | `UNLOCK PHASE 2` and `unlock` subtitles unclassified | FIXED: 5.2 row, they stay, test 4 row |
| 8 | P2 | Mode-read seam unspecified; stateless widgets, no `ProviderScope` | FIXED: static `PurchaseMode.current`, no provider |
| 9 | P2 | Registry recompute names only `paywall_sheet.dart` | FIXED: every edited file, counts listed |
| 10 | P2 | ADR/plan disagree on website mention | FIXED: Profile website row hidden in `none`; referral copy kept (no price, no place) |
| 11 | P2 | "No defect fixed" contradicts the sheet-text rewrite; delete-account copy unwritten | FIXED: U4a `fix(profile)` commits with diagnose-docs; delete-account text kept unchanged with the reason |
| 12 | P3 | `telegram_surface_removed_test` missing from the sweep | FIXED |
| 13 | P3 | Footer visible to a Play reviewer | REJECTED with reason (section 3): it is the only on-device proof of the mode |
| 14 | P3 | `settingsSubStatusTemplate` has no reader | FIXED: step dropped |
| 15 | P3 | Wrong cite for `invite_friends_sheet.dart`; Play id in the share URL | VERIFIED: a real bug (`com.icanbefitter.avya` vs `com.icanbefitter.icanbefitter`); cite fixed, bug fixed in U4a |
| 16 | P3 | Mutation gaps (dismiss event, swapped args) | FIXED in tests 1b and 2 |
| 17 | P3 | Two sentences read as deferrals | FIXED: `reopen_when` text named |
| 18 | P3 | Release APK without the define has no purchase | FIXED: documented in 3 and U6 |
| 19 | P3 | `32 + 3 = 35` prose | FIXED |

