---
bug_id: 9f5c41
date: 2026-07-23
batch: password-reset-flow
status: shipped
symptom: |
  Password-recovery email link lands on the SPA but GoRouter immediately
  routes to /sign-in instead of /reset. The URL hash containing
  `type=recovery&access_token=...` is consumed by GoRouter before
  SplashScreen can read it, so `isPasswordRecovery` is always `false`
  and the recovery routing branch in `_navigateNext` is never taken.
concept: auth_password_reset_timing
sot_registry_entry: null
writers:
  - { file: lib/main.dart, method_or_widget: "main() (recovery fragment capture)", line: 92 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "static isPasswordRecovery flag", line: 67 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: "_SplashScreenState._navigateNext", line: 262 }
  - { file: lib/features/auth/screens/reset_password_screen.dart, method_or_widget: "_ResetPasswordScreenState.initState (guard)", line: 42 }
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
  - { pattern: "Uri.base.fragment checked inside SplashScreen._runDeferredInit", absent: true, after_fix: true, note: "Moved to main() before runApp()" }
  - { pattern: "AppRouter.isPasswordRecovery set from empty fragment", absent: true, after_fix: true }
  - { pattern: "isPasswordRecovery checked without corresponding token stash", absent: true, after_fix: true, note: "recoveryAccessToken and recoveryRefreshToken ensure setSession can be called" }
proposed_fix: |
  1. In main(): read Uri.base.fragment BEFORE runApp(), stash access_token
     and refresh_token on AppRouter, set isPasswordRecovery=true.
  2. In AppRouter: add static String? recoveryAccessToken and
     static String? recoveryRefreshToken fields.
  3. In SplashScreen._runDeferredInit: remove the now-too-late
     fragment check. After SupabaseService.instance.initialize(),
     call auth.setSession() with the stashed tokens when recovery
     is detected and user is not yet authenticated.
regression_test_planned:
  - test/contracts/password_reset_redirect_flow_test.dart (updated)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: verified, evidence: "main.dart, app_router.dart, splash_screen.dart — dart analyze clean, 13/13 contract tests pass." }
  - { tier: 1, layer: test_code, status: verified, evidence: "Updated source-grep contract test pins main.dart detection + stash fields + setSession call." }
  - { tier: 2, layer: supabase_auth_sdk, status: verified, evidence: "gotrue 2.20.0 has setSession(refreshToken, {accessToken?}) — confirmed at gotrue_client.dart:792." }
impact_analysis: |
  Low risk, contained to auth recovery flow. The fragment was already being
  read at the same granularity (Uri.splitQueryString); just shifted earlier
  in the boot sequence before GoRouter can clear it. The supabase session
  setSession() is the canonical method for restoring sessions and is used
  internally by the SDK for PKCE recovery. Worst case: setSession fails and
  user sees an error in the reset password form, which already handles
  AuthException gracefully.
blast_radius: feature
---

# Password recovery broken by GoRouter clearing URL fragment before SplashScreen can read it

## Symptom

Password-recovery email link lands on the SPA at
`https://app.icanbefitter.com/#type=recovery&access_token=xxx&refresh_token=yyy`.
GoRouter immediately routes to `/sign-in`. User never sees `/reset`.

## Root cause

**Two timing bugs, nested:**

1. **(Original, known)** `PASSWORD_RECOVERY` fires during
   `Supabase.initialize()` before any `onAuthStateChange` subscription
   can exist. Fix: read `Uri.base.fragment` before initialize(). This
   was implemented in `b49ed15b`.

2. **(Missed, this fix)** GoRouter's `initialLocation: '/splash'` calls
   `history.replaceState()` during widget-tree bootstrap — before any
   widget's `initState` runs. This strips the browser URL hash. By the
   time `SplashScreen._runDeferredInit` runs, `Uri.base.fragment` is
   already empty.

Both the original author and the code-review skill missed Bug #2 because
their mental model was "fragment check before `Supabase.initialize()` is
early enough" — neither accounted for GoRouter processing the URL between
`runApp()` and the first widget's `initState`.

## The hidden second half

Even with `isPasswordRecovery` correctly set from `main.dart`, **the
`access_token` in the URL hash was also needed by Supabase** to establish
the recovery session. Without it, `auth.updateUser()` in
ResetPasswordScreen would fail. The fix:

1. Stash `access_token` and `refresh_token` alongside the flag in `main.dart`.
2. After `SupabaseService.instance.initialize()`, call
   `auth.setSession(refreshToken, accessToken: accessToken)` manually
   — providing the tokens that Supabase was supposed to auto-detect
   from the now-cleared URL hash.

## Key design decisions

- **Detection in `main()` before `runApp()`** (`main.dart:92-105`): This is
  the ONLY point in the boot sequence where the URL fragment is still
  intact on the browser. After `runApp()`, GoRouter owns the URL.
- **Token stash on AppRouter** (`app_router.dart:76-82`): Static fields
  are the simplest cross-file communication during boot (before Riverpod
  or DI is ready).
- **setSession in splash_screen after Supabase init**
  (`splash_screen.dart:126-138`): Runs after Supabase is ready but before
  `_navigateNext` decides the route. If the stashed tokens work, the user
  gets a recovery session; if they fail, the recovery flag remains true
  and `_navigateNext` still routes to `/reset` (where an error message
  appears).

## Files changed

| File | Change |
|------|--------|
| `lib/main.dart:92-105` | New — fragment capture + token stash before `runApp()` |
| `lib/core/router/app_router.dart:76-82` | New — `recoveryAccessToken` + `recoveryRefreshToken` |
| `lib/features/auth/screens/splash_screen.dart:121-138` | Remove old dead check, add `setSession()` |
| `test/contracts/password_reset_redirect_flow_test.dart` | Updated — pins new detection site + stash + setSession |

## Regression test

`test/contracts/password_reset_redirect_flow_test.dart` — 13 tests:
- 2 pin `forgot_password_sheet.dart` redirect URL (unchanged)
- 2 pin `main.dart` fragment detection + token stash (new)
- 2 pin `splash_screen.dart` setSession + /reset routing (updated)
- 4 pin `app_router.dart` flag + fields + route + auth exemption (updated)
- 3 pin `reset_password_screen.dart` guard + reset + updateUser (unchanged)

## New bug class

This is a new class: **"GoRouter clears URL fragment before widget can read
it"** — a timing-ordering bug where a dependency (GoRouter's
`initialLocation`) consumes browser URL state before the feature code
(in `initState`) reads it. Added to debugging skill §2.22.
