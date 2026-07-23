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
  for `AuthSessionBootstrapper.hydrateFromCloud()` + `SyncService.restoreFromCloud()`
  in parallel, then routes to home / resume-onboarding / mission-brief based on
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
RestoringScreen mounts:
  - AuthSessionBootstrapper.hydrateFromCloud() (in parallel)
  - SyncService.restoreFromCloud() (in parallel; cancellable)
  ↓
AuthSessionBootstrapper.resolveDestination(row) returns one of:
  - GoHome                         — onboarding_completed_at != NULL
  - GoHome (Plan A self-heal)      — onboarding_completed_at NULL, Hive profile populated → re-stamp NOW
  - ResumeOnboarding(firstMissingStep) — onboarding_completed_at NULL, Hive partially populated
  - StartMissionBrief              — no user_profile row at all → new user
  ↓
15-second timeout safety: CONTINUE button surfaces; restore continues in background
```

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
| Restoring screen never advances on cold start | `restoreFromCloud()` is `since='2020-01-01'` (full history, NOT 30/90-day window — that hallucination is in `feedback_mistake_restore_window.md`). 15-second CONTINUE escape lets the user reach home; restore keeps running. | `feedback_mistake_restore_window.md` |
| Returning user waits >1 min on cold start | `_goHome` routes a RETURNING user (local profile present) to the **background-restore** path by default — home in ~3s, restore finishes in the background. Opt-OUT via `disable_bg_restore` kill-switch (was opt-in `bg_restore_enabled`; §4.6). Fresh installs (no local profile) still block on the full restore (nothing local to show). Ownership gate (`openForUser`) stays BLOCKING before nav (APK #15.4). Because restore now runs concurrently with logging, the loss-sensitive restore writers are **additive/local-wins** (see `lib/core/services/CLAUDE.md`). Diagnose c5a1f2. | `test/contracts/restore_local_wins_additive_test.dart` |
| Sub-route `/onboarding/goal` bounces back to Welcome | `GoRouter._authRedirect` uses `location.startsWith('/onboarding')` (NOT `==`). Sub-routes must match the prefix. Fixed commit `17faa86`. | `lib/features/onboarding/CLAUDE.md` |
| Phone OTP fails silently in prod | Twilio account created but not yet wired to Supabase Auth dashboard. See `project_pending_twilio_setup.md`. Email + Google OAuth work normally. | `project_pending_twilio_setup.md` |
| Forgot-password sends magic-link to wrong domain | `forgot_password_sheet.dart` uses `Supabase.auth.resetPasswordForEmail(redirectTo: …)`. The redirect URL is the prod Web build origin, NOT localhost. Supabase dashboard Site URL overrides client `redirectTo` — BOTH must be correct. See diagnose e9f2a4. | `docs/diagnoses/2026-07-22-password-reset-localhost-e9f2a4.md` |
| Password-reset link recognized for one Supabase auth-flow shape but not another | Recovery detection lives in `lib/core/utils/password_recovery_detector.dart` (`PasswordRecoveryDetector.detect`), called from `main.dart` before `runApp()`. It must recognize BOTH the implicit-flow fragment (`#type=recovery&access_token=...`) AND the PKCE query-param shape (`?code=...`, scoped to the `/reset` path) — supabase_flutter defaults to PKCE since 2.x, and a detector built for only one shape silently misroutes the other to `/restoring` → `/onboarding` instead of `/reset`. Re-verify both branches against a live link after any Supabase SDK upgrade. See diagnose b7d4e2. | `docs/diagnoses/2026-07-23-password-reset-pkce-code-not-detected-b7d4e2.md` |

## Tests pinning the rules here

- `test/contracts/auth_hive_owner_agreement_behavioral_test.dart`
- `test/contracts/wrap_user_scoped_box_disagreement_test.dart`
- `test/contracts/auth_invalidation_contract_test.dart`
- `test/contracts/auth_invalidation_timing_test.dart`
- `test/contracts/session_token_stale_authuid_recovery_test.dart` — OBS-6 residual: token reads LIVE authUid so it recovers on account-switch (a7f2e1); kill-switch + isolation.
- `test/contracts/auth_session_bootstrapper_test.dart` — pure-logic `resolveDestination` table.
- `test/contracts/auth_provider_error_surfacing_test.dart`
- `test/contracts/full_name_backfill_test.dart`

## See also

- `lib/features/onboarding/CLAUDE.md` — stepped flow + state passing via GoRouter extras.
- `lib/features/profile/CLAUDE.md` — settings includes Delete Account (DPDP §17).
- `docs/architecture/sync.md` — restoreFromCloud + sync schedule.
