---
scope: auth
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-09-16
status: active
---

# Auth + Session — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/auth/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/auth/` owns sign-in / sign-up / sign-out + the post-auth boot
sequence. Four screens:

- `sign_in_screen.dart` — Email + Google OAuth + Phone OTP entry surface.
- `splash_screen.dart` — Initial decision: signed-in → restore route, signed-out → Welcome.
- `confirm_email_screen.dart` — Landing for the signup confirmation link `/confirm?token_hash=...` on `app.icanbefitter.com`. Calls `AuthNotifier.confirmEmail` (`verifyOTP(tokenHash:, type: OtpType.signup)`, not PKCE-bound), success → `/restoring`. Android: `autoVerify` intent-filter + `web/.well-known/assetlinks.json`. **Web needs its own `vercel.json` redirect to `/#/confirm`** (HashUrlStrategy; see the bare-path pitfall row).
- `restoring_screen.dart` — Post-auth branded gate: runs `AuthSessionBootstrapper.resolveDestination()` + `SyncService.restoreFromCloudForUser()` in parallel (NOT `hydrateFromCloud()`), then routes home / resume-onboarding / mission-brief. Allowlisted `next` param (only `/admin`) guarded by `RestoringScreen.resolveRestoreDestination`.
The core service-layer pieces that this feature wires through:

- `lib/core/services/auth_session_bootstrapper.dart` — pure-logic
  `resolveDestination(row) → AuthDestination` (audit 2026-05-20 / A1+A9). Decision
  tree extracted from the widget for testability.
- `lib/core/services/hive_user_session.dart` — cross-account ownership lock.
- `lib/core/services/subscription_service.dart` — cross-account isPro guard.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `auth_hive_owner_agreement` | `hive_user_session.dart` + `wrapUserScopedBox` (every Hive call) | every WriteService + every Hive-touching provider. **Layer A** = `wrapUserScopedBox` compares `Supabase.auth.currentUser.id` against `HiveUserSession.currentOwnerFullId`; on disagreement returns `GuardedBox.empty(authUid)`. **Owner-NULL-but-authenticated** (sign-out→sign-in gap / cold-boot deep-link before `openForUser`) ALSO serves `GuardedBox.empty` (b8e3f1) — the disagreement branch only covers owner≠null, so the null case used to `throw` → **blank Home**; the loud throw is kept only when UNAUTHENTICATED. Kill-switch `configBox['disable_null_owner_serve_empty']`. **Layer B** = providers receive auth-state-changed invalidation (`authUserIdTokenProvider`). Belt: `app_router._authRedirect` routes authenticated-owner-null → `/restoring` (onboarding-exempt, `shouldGateOnSessionOpen`) so the empty-serve never mis-routes an onboarded user to `/onboarding`; `RestoringScreen._onContinueAnyway` opens the session before nav. Removing any layer breaks the APK Test #15.4 / B1 leak guard. |
| `onboarding_completed_at` | `onboarding_provider.completeOnboarding` (Hive) + cloud trigger on user_profile sync | `restoring_screen.dart` post-auth decision via `AuthSessionBootstrapper.resolveDestination`. **NULL + populated Hive profile** → Plan A self-heal (re-stamp NOW); **NULL + empty Hive profile** → resume mid-onboarding; **non-null** → go home. |
| `user_full_name` | `users.full_name` cloud column + `userBox['profile']['full_name']` | `_restoreUserProfile` reads from `users`, NOT `user_profile`. Field lives on auth-adjacent table. |
| `muster_to_profile_bridge` | `InductionService.recordMusterAnswer` bridges only `body_part_priorities` → `profile['physique_focus']`; the other 5 muster-style keys throw `ArgumentError` (injuries and wake/workout-time are onboarding's/Edit Profile's job only; diagnose d6f1b8). | profile screen via `userProfileProvider`; `ai_snapshot_builder.dart` reads the other fields straight off the profile (see `lib/features/ai_coach/CLAUDE.md`). |

## Post-auth flow (canonical)

```
[sign-in OK]
  ↓
splash_screen.dart routes to /restoring
  ↓
RestoringScreen._kickoffRestore mounts, runs in parallel:
  - AuthSessionBootstrapper.resolveDestination(userId)   — pure read, no Hive writes
  - SyncService.restoreFromCloudForUser()                — cancellable
  ↓
resolveDestination(row) returns one of:
  - GoHome                         — onboarding_completed_at != NULL
  - GoHome (Plan A self-heal)      — onboarding_completed_at NULL, Hive profile populated → re-stamp NOW
  - ResumeOnboarding(firstMissingStep) — onboarding_completed_at NULL, Hive partially populated
  - StartMissionBrief              — no user_profile row at all → new user
  - DestinationUnknown(reason)     — the read DID NOT ANSWER (c2e9f4, 2026-08-10)
  ↓
Timeout safety (TWO stages, not one — restoring_screen.dart:72-73):
  15s (`_softHintAfter`) → a soft "still working" HINT appears
  30s (`_ctaAfter`)      → the CONTINUE escape BUTTON surfaces
  Either way the restore keeps running in the background.
```

**`hydrateFromCloud()` is NOT called by `RestoringScreen`.** Its only call site is `auth_provider.dart`'s `_ensureLocalUser` (email + phone-OTP only, which get a synchronous `response.user`). **`signInWithGoogle()` never reaches it** (OAuth redirect), so anything wired only into `hydrateFromCloud` silently never runs for Google. `RestoringScreen` (`_goHome`'s fast branch and the end of `_ensureOwnershipBeforeHome`, AFTER `HiveUserSession.openForUser`) is the real OAuth convergence point. Detail: `docs/architecture/auth-detail.md`.

Cross-account guard (race scenario — user A signs out, user B signs in
before all Hive boxes finish swapping):

- **Layer A** (correctness): every `wrapUserScopedBox` call short-circuits to
  `GuardedBox.empty(authUid)` if the box's owner is stale → all reads return null/empty/0/false/true. No data leak even if Layer B fails.
- **Layer B** (liveness): `authUserIdTokenProvider` re-emits on `authStateProvider`
  + `hiveSessionOwnerProvider` so every Hive-backed provider re-renders from the
  new owner's box once the swap completes. Its `authUid` is read **LIVE** from
  `SupabaseService.currentUser` (the SAME source `wrapUserScopedBox` uses), NOT the cached
  `currentUserProvider` (which never invalidates → stuck `'<anon>'` skeleton on an in-session account switch, OBS-6 a7f2e1). Kill-switch `configBox['disable_live_auth_token_read']` (default OFF = fix ON).

Both layers are **intentionally redundant**. Never remove either half. Never
read user-scoped Hive without going through `wrapUserScopedBox`.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| User A's data leaks into user B's session after live sign-out + sign-in | `wrapUserScopedBox` enforces Layer A; auth-state-changed providers enforce Layer B. APK Test #15.4 / B1 root cause: providers held stale Hive refs. Both layers must remain in place. | `auth_hive_owner_agreement` SoT + `test/contracts/auth_hive_owner_agreement_behavioral_test.dart` |
| Restoring screen never advances on cold start | `restoreFromCloud()` is `since='2020-01-01'` (full history, NOT 30/90-day window — that hallucination is in `feedback_mistake_restore_window.md`). A soft hint shows at 15s and the CONTINUE escape button at 30s (`_softHintAfter` / `_ctaAfter`, restoring_screen.dart:72-73), letting the user reach home; restore keeps running. | `feedback_mistake_restore_window.md` |
| Returning user waits >1 min on cold start | `_goHome` sends a RETURNING user to the **background-restore** path by default (opt-OUT `disable_bg_restore`); fresh installs block on full restore; the `openForUser` ownership gate stays BLOCKING. Restore writers are additive/local-wins (`lib/core/services/CLAUDE.md`). Diagnose c5a1f2. | `restore_local_wins_additive_test.dart` |
| Sub-route `/onboarding/goal` bounces back to Welcome | `GoRouter._authRedirect` uses `location.startsWith('/onboarding')` (NOT `==`). Sub-routes must match the prefix. Fixed commit `17faa86`. | `lib/features/onboarding/CLAUDE.md` |
| Phone OTP fails silently in prod | Twilio account created but not yet wired to Supabase Auth dashboard. See `project_pending_twilio_setup.md`. | `project_pending_twilio_setup.md` |
| Forgot-password sends magic-link to wrong domain | `forgot_password_sheet.dart` uses `Supabase.auth.resetPasswordForEmail(redirectTo: …)`. The redirect URL is the prod Web build origin, NOT localhost. Supabase dashboard Site URL overrides client `redirectTo` — BOTH must be correct. See diagnose e9f2a4. | `docs/diagnoses/2026-07-22-password-reset-localhost-e9f2a4.md` |
| Password-reset link recognized for one Supabase auth-flow shape but not another | `PasswordRecoveryDetector.detect` (`lib/core/utils/password_recovery_detector.dart`, called from `main.dart` before `runApp()`) must recognize BOTH the implicit-flow fragment (`#type=recovery&access_token=...`) AND the PKCE `?code=...` shape (scoped to `/reset`). Re-verify both after any Supabase SDK upgrade. Diagnose b7d4e2. | `docs/diagnoses/2026-07-23-password-reset-pkce-code-not-detected-b7d4e2.md` |
| Screen ends a Supabase session in place and expects `_authRedirect` to notice | GoRouter has NO `refreshListenable` tied to `onAuthStateChange`; `signOut()` alone never re-runs `_authRedirect`, and `/reset` is exempt from the guard. Any screen that signs out in place must navigate explicitly (`context.go`). Diagnose c8f1d3. | `docs/diagnoses/2026-08-01-password-reset-stuck-screen-c8f1d3.md` |
| Google sign-in stuck / never returns to the app | Two gaps, both required: (1) `AndroidManifest.xml` needs a `BROWSABLE`/`VIEW` intent-filter for `io.supabase.icanbefitter://login-callback/`; (2) `signInWithGoogle`'s `redirectTo` must branch on `kIsWeb`, and the web value must be on Supabase's Redirect URLs allowlist. Also needs account-side Google Cloud OAuth Web client linked into Supabase Auth. Diagnose f2b8a1. | `docs/diagnoses/2026-08-02-google-oauth-web-redirect-mobile-scheme-f2b8a1.md` |
| A Hive write inside `catch (_) {}` never actually lands | Any write to a user-scoped box MUST happen after `HiveUserSession.openForUser` has resolved for this session (before it, the box getter throws `StateError` — `terms_accepted_at` was 100% NULL for 2.5 months). Verify the call site; source-grep tests cannot catch this. Diagnose b3f9e7, debugging skill bug-class 2.47. | `docs/diagnoses/2026-08-02-terms-accepted-dead-write-b3f9e7.md` |
| A failed `user_profile` read routes an onboarded user into onboarding | `resolveDestination` returns `DestinationUnknown` (not `StartMissionBrief`) when the read did not answer — SELECT throws, OR HTTP 200 + zero rows (own-row RLS filtered a stale token) — after `ensureFreshToken()` + one hard-refresh retry; `sealed` makes an unhandled branch a COMPILE error. All not-onboarded branches consult `hasLocalOnboardedEvidence` (`lib/core/services/local_onboarding_evidence.dart`) **after** `ensureOpenedForCurrentSession()` (under owner-null the read silently returns "no evidence"). Kill-switches `disable_resolve_destination_unknown` / `disable_local_onboarded_evidence`. Third instance of this misroute class (1bfeed → a3f6d9 → c2e9f4). | `docs/diagnoses/2026-08-10-resolve-destination-failed-read-means-new-user-c2e9f4.md` + debugging skill bug-class 2.49 |
| Consent is collected on the EMAIL path and nowhere else | `_privacyAccepted` gates ONLY the email CREATE ACCOUNT button; Google converges on `ensureTermsConsentFallback` (auto-stamps `terms_accepted_at`, no gesture). Do NOT copy the checkbox into the OAuth card without deciding where consent belongs (founder row 3.5, `docs/operations/GO_LIVE_CHECKLIST.md`). | diagnose `d8f2c1` |
| "Every post-auth path converges on `hydrateFromCloud`" is FALSE for Google OAuth | See the paragraph under "Post-auth flow". Verify with `grep -rn "hydrateFromCloud(" lib` (expect exactly 1 real call site) before assuming a universal hook. | diagnose b3f9e7 plan-review round 1 (`docs/plan-reviews/terms-accepted-fix.md`) |
| Signup confirmation email never arrives, or its link opens a browser | (1) No custom SMTP → spam/never sent (`auth.users.confirmation_sent_at` vs `email_confirmed_at`). (2) App Links need `.well-known/assetlinks.json` live (not swallowed by `vercel.json`'s SPA rewrite), the `autoVerify` intent-filter, AND the Supabase template pointing at `app.icanbefitter.com/confirm`. Real signed build only. | `confirm_email_screen.dart` |
| A deep-link screen's `initState`-only guard drops a SECOND, different deep link | go_router's `pageKey` derives from the matched PATH only, so a second `/confirm?token_hash=B` reuses the State and calls `didUpdateWidget`, not `initState`. Key the guard on the request VALUE (`_startedFor == tokenHash`) and re-check in `didUpdateWidget` (`_maybeStartVerification` is the reference). | `docs/reviews/email-confirm-ux-bpass.md` Finding 1 |
| An already-authenticated user opening a `/reset` or `/confirm` link gets silently switched account | Accepted tradeoff (OI-205). `/confirm` is `autoVerify` so exposure is broader; cross-account guard prevents a Hive leak. Interim: `confirmEmail` refuses via `AuthNotifier.confirmEmailAuthGuardState` when authenticated. | OI-205 |
| A new screen's direct `AuthNotifier.signOut()` call site lacks the OI-51 device-identity-release guard | Wrap: `try { await signOut(); } catch (e) { ...; await releaseDeviceSessionIdentity(); }` (see `settings_screen.dart` `_SignOutButton`). Enforced by the DERIVED test `signout_unbinds_sdk_identity_test.dart` at `flutter test` time. Open: `_teardown()` TIMEOUT (bug-class 2.65, OI-208). | diagnose `d4a8f6` |
| A non-error `AuthState2` message renders in the red error SnackBar | Use `AuthStatus.info` for an expected next-step message and render through `authToastStyleFor(status)` (info → Wardroom gold), never a hardcoded `AppColors.bad`. A genuine conflict stays `error`/red. | `test/contracts/auth_toast_info_status_test.dart` |
| A brand-new bare-path GoRoute dead-ends on the WEB build | HashUrlStrategy: GoRouter only resolves `/#/<path>`. **Any new bare-path route MUST add its own `vercel.json` redirect in the SAME commit as the GoRoute** (`/admin` precedent). | `confirm_web_redirect_test.dart` |
| A user whose confirmation email is lost/expired has no in-app recovery | `AuthNotifier.resendConfirmationEmail` + `isEmailNotConfirmedMessage` gate an inline "Resend it" link. OI-244 fixed: `ConfirmLinkDetector` (f92d17) and `ensureSupabaseReady()` in `confirmEmail` (42a98d). Open: Android App Links claim (founder's Play Console signing-key check). | diagnoses f6c2a9, f92d17, 42a98d in `docs/diagnoses/` |

## Tests pinning the rules here

- `test/contracts/`: `auth_hive_owner_agreement_behavioral_test`, `wrap_user_scoped_box_disagreement_test`, `auth_invalidation_contract_test`, `auth_invalidation_timing_test`, `session_token_stale_authuid_recovery_test` (OBS-6), `auth_session_bootstrapper_test` (pure `resolveDestination` table), `auth_provider_error_surfacing_test`, `full_name_backfill_test`, `terms_acceptance_behavioral_test` (real Hive round-trip), `confirm_email_error_mapping_test`, `confirm_email_readiness_behavioral_test` (42a98d), `confirm_web_redirect_test` (pins `vercel.json` `/confirm` redirects + `/admin` + `.well-known/` exclusion), `auth_toast_info_status_test`, `is_email_not_confirmed_message_test`.
- `test/auth/confirm_email_screen_test.dart`, `test/auth/sign_in_screen_resend_confirmation_test.dart` (widget tests; mutation-proven, diagnose f6c2a9).

## See also

- `lib/features/onboarding/CLAUDE.md` — stepped flow + state passing via GoRouter extras.
- `lib/features/profile/CLAUDE.md` — settings includes Delete Account (DPDP §17).
- `docs/architecture/auth-detail.md` — moved-out history, provenance and per-test descriptions for this file.
- `docs/architecture/sync.md` — restoreFromCloud + sync schedule.
