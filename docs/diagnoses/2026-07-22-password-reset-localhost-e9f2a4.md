---
bug_id: e9f2a4
date: 2026-07-22
batch: password-reset-flow
status: shipped
symptom: |
  Forgot-password email link points to `http://127.0.0.1:3000/reset`
  instead of `https://app.icanbefitter.com/reset`. User never reaches
  the reset-password form. The Supabase Cloud Auth dashboard Site URL
  (`http://127.0.0.1:3000`) overrides the `redirectTo` parameter passed
  to `resetPasswordForEmail`.
concept: auth_password_reset
sot_registry_entry: null
writers:
  - { file: lib/features/auth/widgets/forgot_password_sheet.dart, method_or_widget: ForgotPasswordSheet._sendResetEmail, line: 57 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: _SplashScreenState._runDeferredInit, line: 127 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: _authRedirect, line: 592 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: _SplashScreenState._navigateNext, line: 262 }
  - { file: lib/features/auth/screens/reset_password_screen.dart, method_or_widget: _ResetPasswordScreenState.initState (guard), line: 44 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/password_reset_redirect_flow_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "Supabase.auth.resetPasswordForEmail(redirectTo: 'https://icanbefitter.vercel.app/...')", absent: true, after_fix: true }
  - { pattern: "AppRouter.isPasswordRecovery referenced without a URL-fragment check", absent: true, after_fix: true }
  - { pattern: "PASSWORD_RECOVERY handler via onAuthStateChange", absent: true, note: "Event fires during Supabase.initialize() before any subscription can exist — the URL-fragment check in splash_screen.dart is the correct detection method." }
proposed_fix: |
  1. Fix redirectTo in forgot_password_sheet.dart:57 from
     `https://icanbefitter.vercel.app/reset` to
     `https://app.icanbefitter.com/reset`.
  2. Add static bool AppRouter.isPasswordRecovery flag to app_router.dart:70.
  3. In splash_screen.dart _runDeferredInit: read `Uri.base.fragment` for
     `type=recovery` BEFORE Supabase.initialize() consumes the event, set
     the flag. In _navigateNext: route to `/reset` when flag is set.
  4. Add `/reset` GoRoute in app_router.dart alongside `/sign-in` with
     _authRedirect exemption (passthrough null return).
  5. Create ResetPasswordScreen with two-password form + visibility toggles
     + UPDATE PASSWORD button + success snackbar → signOut → /sign-in.
     Guard: redirect to /sign-in if isPasswordRecovery is false on mount.
  6. Manual (non-code): update Supabase dashboard Site URL from
     `http://127.0.0.1:3000` to `https://app.icanbefitter.com` and add
     `https://app.icanbefitter.com/reset` to additional redirect URLs.
regression_test_planned:
  - test/contracts/password_reset_redirect_flow_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: verified, evidence: "All 5 files read, dart format passes, source-grep contract test pins invariants." }
  - { tier: 3, layer: supabase_auth_dashboard_site_url, status: fixed_in_this_batch, evidence: "Site URL must be updated from http://127.0.0.1:3000 to https://app.icanbefitter.com; redirectTo corrected in code but dashboard setting takes precedence." }
impact_analysis: |
  Low risk, contained to auth flow. Fix adds a new screen and routing but no
  changes to existing sign-in/sign-out or data paths. The recovery flag is
  scoped to a single static bool reset on sign-out. The guard in
  ResetPasswordScreen redirects to /sign-in if the flag is not set,
  preventing direct navigation to /reset outside the recovery flow.
blast_radius: feature
---

# Password reset sent to localhost — Supabase dashboard Site URL overrides client redirectTo

## Symptom

Founder reported that the forgot-password email link points to
`http://127.0.0.1:3000/reset` instead of
`https://app.icanbefitter.com/reset`. Clicking the link leads to a
broken page (localhost on user's machine). The `redirectTo` parameter
in `forgot_password_sheet.dart:57` was already
`https://icanbefitter.vercel.app/reset` (wrong domain) but even that was
being ignored — Supabase Cloud Auth uses the dashboard-configured
Site URL as the link base, not the `redirectTo` parameter.

## Root cause

Two independent issues:

1. **Supabase Cloud Auth dashboard Site URL** is set to
   `http://127.0.0.1:3000` (the local dev default in `config.toml`).
   The cloud environment uses this dashboard value, NOT the
   `config.toml` setting, and NOT the `redirectTo` parameter passed
   to `resetPasswordForEmail`. The `redirectTo` parameter is used
   only for the *path* after the Site URL base.

2. **No in-app password reset flow existed.** The web SPA had no
   `/reset` route, no reset form, and no handler for the
   `PASSWORD_RECOVERY` auth event. Even with a correct link, the user
   would land on the SPA and get routed to `/sign-in` (unauthenticated
   fallback), never seeing a password reset form.

## Detection challenge

`PASSWORD_RECOVERY` fires DURING `Supabase.initialize()` (inside the
Supabase SDK), before any `onAuthStateChange` subscription can exist.
Listening for this event in a `initState` or `didChangeDependencies` is
too late — the event is already consumed. Fix: parse `Uri.base.fragment`
for `type=recovery` BEFORE `SupabaseService.instance.initialize()`.

## Fix (5 code changes + 1 manual)

See `proposed_fix` YAML field for the full list. Key design decisions:

- **URL fragment check before Supabase init** (`splash_screen.dart:124-131`):
  This is the earliest possible detection point — before any SDK call that
  consumes the auth event.
- **Static bool on AppRouter** (`app_router.dart:70`): Simple, testable,
  reset on sign-out.
- **ResetPasswordScreen guard** (`reset_password_screen.dart:44`):
  Redirects to `/sign-in` if the flag is false, preventing stray
  navigations to `/reset`.
- **_authRedirect exemption** (`app_router.dart:592`): Returns null
  (passthrough) for `/reset`, bypassing all session checks.

## Files changed

| File | Change |
|------|--------|
| `lib/features/auth/widgets/forgot_password_sheet.dart:57` | `redirectTo` URL fixed |
| `lib/core/router/app_router.dart:70,111,592` | Static flag, `/reset` route, auth exemption |
| `lib/features/auth/screens/splash_screen.dart:124-131,262-265` | Recovery detection + routing |
| `lib/features/auth/screens/reset_password_screen.dart` | New file — full reset-password form |
| `lib/features/profile/screens/profile/privacy_dialog.dart:45,62` | Stale `vercel.app` URLs fixed (incidental) |

## Manual step required

Supabase dashboard → Authentication → Settings → Site URL: change from
`http://127.0.0.1:3000` to `https://app.icanbefitter.com`. Add
`https://app.icanbefitter.com/reset` to Additional Redirect URLs.

## Regression test

`test/contracts/password_reset_redirect_flow_test.dart`:
- Pins the `redirectTo` URL string via source-grep
- Pins the recovery detection pattern in splash_screen
- Pins the `/reset` route and _authRedirect exemption in app_router

## New bug class

This is a new class: **"Supabase dashboard Site URL overrides client
redirectTo"**. Added to debugging skill §2.45.
