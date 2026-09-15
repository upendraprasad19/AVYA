---
scope: auth
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Auth + Session — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/auth/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/auth/` owns sign-in / sign-up / sign-out + the post-auth boot
sequence. Three screens:

- `sign_in_screen.dart` — Email + Google OAuth + Phone OTP entry surface.
- `splash_screen.dart` — Initial decision: signed-in → restore route, signed-out → Welcome.
- `restoring_screen.dart` — The post-auth branded gate added in APK Test #2. Waits
  for `AuthSessionBootstrapper.resolveDestination()` + `SyncService.restoreFromCloudForUser()`
  in parallel (**CORRECTED 2026-08-02, diagnose b3f9e7 plan-review round 1** — this
  previously said `hydrateFromCloud()`, which `RestoringScreen` does NOT call; see the
  "Post-auth flow" section below for why that distinction matters), then routes to
  home / resume-onboarding / mission-brief based on
  the user_profile row classification. **2026-07-16 (b3f9a1):** also accepts an
  allowlisted `next` query param (`/restoring?next=…`, currently only `/admin`)
  so a cold-tab bookmark of the founder dashboard returns there instead of
  `/home`; `RestoringScreen.resolveRestoreDestination` guards the allowlist
  (any other/external value → `/home`) at all three terminal `context.go` sites.

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
| `muster_to_profile_bridge` | Q3..Q5 onboarding answers → profile fields via `userBox['profile']` write | profile screen reads via `userProfileProvider`. APK Test #15.4 / B2. |

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

**`hydrateFromCloud()` is a DIFFERENT, easily-confused method — `RestoringScreen`
never calls it (corrected 2026-08-02, diagnose b3f9e7 plan-review round 1; this
section previously said it did).** `hydrateFromCloud` has exactly one call site in
the whole repo: inside `auth_provider.dart`'s `_ensureLocalUser`, itself called only
from `signInWithEmail` / `signUpWithEmail` ×2 / `verifyOtp` — i.e. only email and
phone-OTP, which get a synchronous `response.user` right after `auth.signIn/signUp`.
**`signInWithGoogle()` never calls `_ensureLocalUser`** (OAuth is a redirect flow with
no synchronous response.user) — so anything wired only into `hydrateFromCloud`,
believing it to be "the place every post-auth path converges on," silently never runs
for Google OAuth. `RestoringScreen` — specifically `_goHome`'s fast branch and the end
of `_ensureOwnershipBeforeHome`, both AFTER `HiveUserSession.openForUser` is confirmed
— is the actual OAuth convergence point for anything that needs a live Hive session.
This was the second-round finding that caught Part B of diagnose b3f9e7 not actually
fixing Google OAuth's consent gap despite fixing phone OTP's identical-looking one.

Cross-account guard (race scenario — user A signs out, user B signs in
before all Hive boxes finish swapping):

- **Layer A** (correctness): every `wrapUserScopedBox` call short-circuits to
  `GuardedBox.empty(authUid)` if the box's owner is stale → all reads return null/empty/0/false/true. No data leak even if Layer B fails.
- **Layer B** (liveness): `authUserIdTokenProvider` re-emits on `authStateProvider`
  + `hiveSessionOwnerProvider` so every Hive-backed provider re-renders from the
  new owner's box once the swap completes. Its `authUid` is read **LIVE** from
  `SupabaseService.currentUser` (the SAME source `wrapUserScopedBox` uses) — NOT the
  cached `currentUserProvider`. **OBS-6 residual (a7f2e1, 2026-07-02):**
  `currentUserProvider` caches on first read + is never invalidated, so on an
  in-session account switch the token read a STALE uid → stuck `'<anon>'` → the
  `isSessionTearingDown` skeleton gate stuck on ALL 4 mixin tabs (Home/Train/
  Nutrition/Profile) until reload. Kill-switch `configBox['disable_live_auth_token_read']`
  (default OFF = fix ON) reverts to the cached read. Recurrence of b8e3f1 — that
  fix repaired the box read + blank-Home, not the token source.

Both layers are **intentionally redundant**. Never remove either half. Never
read user-scoped Hive without going through `wrapUserScopedBox`.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| User A's data leaks into user B's session after live sign-out + sign-in | `wrapUserScopedBox` enforces Layer A; auth-state-changed providers enforce Layer B. APK Test #15.4 / B1 root cause: providers held stale Hive refs. Both layers must remain in place. | `auth_hive_owner_agreement` SoT + `test/contracts/auth_hive_owner_agreement_behavioral_test.dart` |
| Restoring screen never advances on cold start | `restoreFromCloud()` is `since='2020-01-01'` (full history, NOT 30/90-day window — that hallucination is in `feedback_mistake_restore_window.md`). A soft hint shows at 15s and the CONTINUE escape button at 30s (`_softHintAfter` / `_ctaAfter`, restoring_screen.dart:72-73), letting the user reach home; restore keeps running. | `feedback_mistake_restore_window.md` |
| Returning user waits >1 min on cold start | `_goHome` routes a RETURNING user (local profile present) to the **background-restore** path by default — home in ~3s, restore finishes in the background. Opt-OUT via `disable_bg_restore` kill-switch (was opt-in `bg_restore_enabled`; §4.6). Fresh installs (no local profile) still block on the full restore (nothing local to show). Ownership gate (`openForUser`) stays BLOCKING before nav (APK #15.4). Because restore now runs concurrently with logging, the loss-sensitive restore writers are **additive/local-wins** (see `lib/core/services/CLAUDE.md`). Diagnose c5a1f2. | `test/contracts/restore_local_wins_additive_test.dart` |
| Sub-route `/onboarding/goal` bounces back to Welcome | `GoRouter._authRedirect` uses `location.startsWith('/onboarding')` (NOT `==`). Sub-routes must match the prefix. Fixed commit `17faa86`. | `lib/features/onboarding/CLAUDE.md` |
| Phone OTP fails silently in prod | Twilio account created but not yet wired to Supabase Auth dashboard. See `project_pending_twilio_setup.md`. | `project_pending_twilio_setup.md` |
| Forgot-password sends magic-link to wrong domain | `forgot_password_sheet.dart` uses `Supabase.auth.resetPasswordForEmail(redirectTo: …)`. The redirect URL is the prod Web build origin, NOT localhost. Supabase dashboard Site URL overrides client `redirectTo` — BOTH must be correct. See diagnose e9f2a4. | `docs/diagnoses/2026-07-22-password-reset-localhost-e9f2a4.md` |
| Password-reset link recognized for one Supabase auth-flow shape but not another | Recovery detection lives in `lib/core/utils/password_recovery_detector.dart` (`PasswordRecoveryDetector.detect`), called from `main.dart` before `runApp()`. It must recognize BOTH the implicit-flow fragment (`#type=recovery&access_token=...`) AND the PKCE query-param shape (`?code=...`, scoped to the `/reset` path) — supabase_flutter defaults to PKCE since 2.x, and a detector built for only one shape silently misroutes the other to `/restoring` → `/onboarding` instead of `/reset`. Re-verify both branches against a live link after any Supabase SDK upgrade. See diagnose b7d4e2. | `docs/diagnoses/2026-07-23-password-reset-pkce-code-not-detected-b7d4e2.md` |
| Screen ends a Supabase session in place and expects `_authRedirect` to notice | GoRouter has NO `refreshListenable` tied to `Supabase.auth.onAuthStateChange` anywhere in this app (`app_router.dart:84-89` / `app.dart:105`) — `signOut()` alone never re-runs `_authRedirect`. `/reset` is also deliberately exempt from the guard. `ResetPasswordScreen._updatePassword` used to comment "the router handles the navigation automatically" and just sat on `/reset` forever after a successful reset. Any screen that signs out in place must navigate explicitly (`context.go`), same pattern `sign_in_screen.dart`'s `ref.listen` already uses on success. See diagnose c8f1d3. | `docs/diagnoses/2026-08-01-password-reset-stuck-screen-c8f1d3.md` |
| Google sign-in stuck / never returns to the app | Two independent gaps, both required for the flow to complete: (1) `AndroidManifest.xml` needs a `BROWSABLE`/`VIEW` intent-filter for `io.supabase.icanbefitter://login-callback/`, or Android has nowhere to hand control back after Google consent; (2) `AuthNotifier.signInWithGoogle`'s `redirectTo` must branch on `kIsWeb` — a browser cannot resolve the mobile custom scheme, and the web value must be on Supabase's Redirect URLs allowlist (same class as the e9f2a4 password-reset bug below). Activating the provider ALSO requires account-side setup outside this repo: a Google Cloud OAuth 2.0 Web client (redirect URI = Supabase's `/auth/v1/callback`) linked into Supabase Auth → Providers → Google, and both redirect URLs added to the allowlist. See diagnose f2b8a1. | `docs/diagnoses/2026-08-02-google-oauth-web-redirect-mobile-scheme-f2b8a1.md` |
| A Hive write inside `catch (_) {}` never actually lands, forever | `terms_accepted_at`/`terms_version` were 100% NULL for every user for 2.5 months — the 2026-05-16 fix wrote to `HiveService.instance.userBox` at CREATE ACCOUNT tap time, before any Supabase session existed, so `HiveUserSession.openForUser` had never run and the box getter itself threw `StateError` (`guarded_box.dart:335`), silently swallowed. Any write to a user-scoped box (`userBox`/`coachBox`/etc.) MUST happen after `HiveUserSession.openForUser` has resolved for this session — verify the call site, don't assume a `try/catch` means "it's fine either way." Source-grep regression tests cannot catch this class; the write call being present and correctly ordered relative to sibling calls says nothing about whether the box was actually writable yet. See diagnose b3f9e7 + debugging skill bug-class 2.47 (write-side sibling of bug-class 2.21). | `docs/diagnoses/2026-08-02-terms-accepted-dead-write-b3f9e7.md` |
| A failed `user_profile` read routes an onboarded user into onboarding | `resolveDestination`'s catch used to return `StartMissionBrief` — presenting "could not read" as the positive fact "this user has no profile". **Two entrances, neither visible at the call site:** the SELECT throws, OR it returns **HTTP 200 with zero rows** because `user_profile_select_own` (own-row-only RLS) filtered a stale / not-yet-attached token, and `.maybeSingle()` then yields `null`, identical to "no such user". Now returns `DestinationUnknown` after `ensureFreshToken()` + one hard-refresh retry; the `sealed` hierarchy makes an unhandled branch a COMPILE error. All three not-onboarded branches consult `hasLocalOnboardedEvidence` (`lib/core/services/local_onboarding_evidence.dart`) **after** `ensureOpenedForCurrentSession()` — under owner-null `wrapUserScopedBox` serves `GuardedBox.empty` (`guarded_box.dart:333`) so the read silently returns "no evidence"; relying on the parallel `restoreFromCloudForUser` to have opened the session is a RACE (`sync_service.dart:454` is fire-and-forget). Third instance of this misroute class (1bfeed → a3f6d9 → c2e9f4); a3f6d9 fixed the writers, this fixes the classifier that decides which writer runs. Kill-switches `disable_resolve_destination_unknown` / `disable_local_onboarded_evidence`. | `docs/diagnoses/2026-08-10-resolve-destination-failed-read-means-new-user-c2e9f4.md` + debugging skill bug-class 2.49 |
| Consent is collected on the EMAIL path and nowhere else | `_privacyAccepted` (`sign_in_screen.dart:111`, default **false** since 2026-08-25 / diagnose `d8f2c1`) gates exactly ONE widget — the email CREATE ACCOUNT button (`:1023`). **`signInWithGoogle()` (`:365`) — the primary CTA — has no consent gate at all**, and phone OTP has the same gap dormant behind `_kEnablePhoneEnlist`. Google users converge instead on `ensureTermsConsentFallback` (`auth_session_bootstrapper.dart:294`, from b3f9e7), which auto-stamps `terms_accepted_at` from `created_at` with **no user gesture**. So the app runs two consent regimes: an explicit tick on the secondary route, a backdated timestamp on the primary one. Un-ticking the email box made the asymmetry sharper, not new. Do NOT "fix" this by copying the checkbox into the OAuth card without deciding where consent belongs in a redirect flow (before launch, or as a post-redirect step) — that is a UX decision, tracked as founder row 3.5 in `docs/operations/GO_LIVE_CHECKLIST.md`. | diagnose `d8f2c1` + B-pass on `launch-blockers-1a` (Finding 1) |
| "Every post-auth path converges on `hydrateFromCloud`" is FALSE for Google OAuth | `hydrateFromCloud` has exactly one call site in the repo — inside `_ensureLocalUser`, reachable only from email/OTP (methods that get a synchronous `response.user`). `signInWithGoogle()` returns immediately after starting the redirect and never reaches it; the post-redirect re-entry (`RestoringScreen`) calls `resolveDestination` + `restoreFromCloudForUser`, neither of which is `hydrateFromCloud`. A fallback/heal wired only into `hydrateFromCloud` silently never runs for Google OAuth users. Verify with `grep -rn "hydrateFromCloud(" lib` (expect exactly 1 real call site) before assuming it's a universal hook; `RestoringScreen`'s `_goHome`/`_ensureOwnershipBeforeHome` (after `HiveUserSession.openForUser`) is the actual OAuth convergence point. Caught only by an independent plan-review round, not the B-pass (which reviews line-level bugs, not call-graph reachability) — see `feedback_plan_review_twice.md`. | diagnose b3f9e7 plan-review round 1 (`docs/plan-reviews/terms-accepted-fix.md`) |

## Tests pinning the rules here

- `test/contracts/auth_hive_owner_agreement_behavioral_test.dart`
- `test/contracts/wrap_user_scoped_box_disagreement_test.dart`
- `test/contracts/auth_invalidation_contract_test.dart`
- `test/contracts/auth_invalidation_timing_test.dart`
- `test/contracts/session_token_stale_authuid_recovery_test.dart` — OBS-6 residual: token reads LIVE authUid so it recovers on account-switch (a7f2e1); kill-switch + isolation.
- `test/contracts/auth_session_bootstrapper_test.dart` — pure-logic `resolveDestination` table.
- `test/contracts/auth_provider_error_surfacing_test.dart`
- `test/contracts/full_name_backfill_test.dart`
- `test/contracts/terms_acceptance_behavioral_test.dart` — real Hive round-trip (throws before `HiveUserSession.openForUser`, persists after) + pure-logic `shouldStampFallbackTermsConsent` table.

## See also

- `lib/features/onboarding/CLAUDE.md` — stepped flow + state passing via GoRouter extras.
- `lib/features/profile/CLAUDE.md` — settings includes Delete Account (DPDP §17).
- `docs/architecture/sync.md` — restoreFromCloud + sync schedule.
