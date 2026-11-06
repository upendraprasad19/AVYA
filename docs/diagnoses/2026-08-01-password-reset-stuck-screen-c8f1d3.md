---
bug_id: c8f1d3
date: 2026-08-01
batch: password-reset-flow
status: shipped
symptom: |
  A user requests a password reset from the web app, gets the email, clicks
  the link, lands on the "SET NEW PASSWORD" screen (Wardroom-branded,
  "RECRUIT REGISTRY" / "SET NEW PASSWORD", two password fields, "Minimum 6
  characters"), enters a new password, submits successfully, sees a
  "Password updated" confirmation SnackBar — and then the screen never
  advances. It sits on /reset indefinitely with nothing left to do.
concept: auth_password_reset_post_success_navigation
sot_registry_entry: null
writers:
  - { file: lib/features/auth/screens/reset_password_screen.dart, method_or_widget: "_ResetPasswordScreenState._updatePassword", line: 122 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "GoRoute /sign-in registration", line: 106 }
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
  - { pattern: "reliance on _authRedirect to move the user off /reset after signOut", absent: true, after_fix: true, note: "/reset is deliberately exempt from _authRedirect (app_router.dart:644, isOnReset -> return null) and GoRouter has no refreshListenable tied to Supabase auth state, so signOut() alone was never going to move the user off the route — confirmed by reading both the GoRouter construction (app_router.dart:84-89) and lib/app.dart's MaterialApp.router call, which has no auth-state listener that navigates." }
proposed_fix: |
  Add an explicit `if (mounted) context.go('/sign-in');` at the end of
  _updatePassword()'s success path, after the existing signOut() +
  releaseDeviceSessionIdentity() + isPasswordRecovery=false sequence.
  Mirrors the explicit-navigation pattern SignInScreen already uses on its
  own success path (ref.listen -> context.go('/restoring'),
  sign_in_screen.dart:183) rather than relying on the router to notice an
  auth-state change on its own. No router-level change (no
  refreshListenable) — scoped to the single screen that owns this
  transition. Hardened by the plan-review's 2 review rounds
  (docs/plan-reviews/signin-redesign-password-reset-fix.md): signOut() is
  now in its own try/catch (a transient failure must not surface a false
  "password update failed" error, since updateUser already succeeded, nor
  block the navigation below it) and releaseDeviceSessionIdentity() is
  called UNCONDITIONALLY after that try, not nested inside it (round 2
  caught that nesting it would skip the device-identity release on a
  signOut() throw, defeating OI-51's own purpose).
regression_test_planned:
  - test/contracts/password_reset_redirect_flow_test.dart (extended — new behavioral group pumps ResetPasswordScreen with a fake local Supabase session + mocked GoTrue HTTP responses, taps UPDATE PASSWORD, asserts the app navigates off /reset)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "lib/features/auth/screens/reset_password_screen.dart — flutter analyze clean; new behavioral widget test in test/contracts/password_reset_redirect_flow_test.dart fails pre-fix (screen stays on /reset) and passes post-fix (navigates to /sign-in)." }
  - { tier: 2, layer: hive, status: not_applicable, evidence: "No Hive read/write in this flow — pure client-side navigation bug." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, layer: postgres_data, status: not_applicable, evidence: "No data-layer change — Supabase auth.updateUser and auth.signOut were already being called correctly; only the client-side post-success navigation was missing." }
  - { tier: 5, layer: migrations, status: not_applicable, evidence: "No migration." }
  - { tier: 6, layer: edge_function, status: not_applicable, evidence: "No Edge Function involved — Supabase Auth's built-in updateUser/signOut endpoints, no custom EF." }
  - { tier: 7, layer: cron, status: not_applicable, evidence: "Not cron-related." }
  - { tier: 8, layer: rls, status: not_applicable, evidence: "No RLS-gated table involved." }
  - { tier: 9, layer: storage, status: not_applicable, evidence: "No storage bucket involved." }
  - { tier: 10, layer: secrets, status: not_applicable, evidence: "No secret/API-key change." }
  - { tier: 11, layer: external_services, status: not_applicable, evidence: "Supabase Auth dashboard config (Site URL, redirect allowlist) is unchanged and already correct per diagnose e9f2a4/b7d4e2 — this fix only adds a client-side navigation call after those already-working calls succeed." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "Traced the full flow by reading every file directly: forgot_password_sheet.dart:57 (redirectTo) -> AndroidManifest.xml (confirmed no App Link / custom-scheme intent-filter exists, so the link opens the prod web build in the phone's browser, not a native deep link) -> main.dart:107 (kIsWeb-gated recovery detection) -> app_router.dart /reset route + _authRedirect exemption -> reset_password_screen.dart _updatePassword -> app_router.dart /sign-in route (the new navigation target)." }
impact_analysis: |
  Low risk, contained to a single screen's success path. The fix adds one
  navigation call after the sign-out sequence, which already executed
  correctly and already ended the session — nothing about the auth state
  machine changes, only what happens client-side once that state change
  completes. Worst case if the navigation call itself misbehaved: the user
  stays on /reset exactly as today (no new failure mode — the pre-fix
  behavior is the floor, not something this change could make worse).
  Confirmed via direct reads of lib/app.dart and
  lib/core/router/app_router.dart that no other listener or
  refreshListenable currently reacts to this sign-out, so there is no
  double-navigation risk from adding this call. Plan-review round 1 found
  the initial single-try-block version could surface a false error and skip
  navigation on a transient signOut() failure; round 2 found round 1's own
  fix then skipped releaseDeviceSessionIdentity() on that same failure path.
  Both closed before merge — see
  docs/plan-reviews/signin-redesign-password-reset-fix.md.
blast_radius: account
---

# Password-reset "stuck screen" — success path never navigates off /reset

## Symptom

A user requests a password reset, receives the email, clicks the link
(which opens the production **web app** in the phone's browser — see "Web
vs native" below), lands on `ResetPasswordScreen` ("SET NEW PASSWORD"),
enters and confirms a new password, submits, sees a "Password updated. Sign
in with your new password." confirmation SnackBar — and then nothing
happens. The screen sits on `/reset` indefinitely.

## Bug-history check (done first)

Grepped `docs/diagnoses/INDEX.md` for `password reset` / `recovery` /
`redirect` / `stuck` / `Site URL` before forming any root-cause hypothesis.
Three prior diagnose-docs exist in the same `password-reset-flow` batch, all
shipped:

- `e9f2a4` (2026-07-22) — Supabase dashboard Site URL silently overrode the
  client's `redirectTo`, sending the email link to the wrong domain.
- `9f5c41` (2026-07-23) — GoRouter's `initialLocation` cleared the URL
  fragment via `history.replaceState` before any widget could read it.
- `b7d4e2` (2026-07-23) — the recovery detector recognized the legacy
  implicit-flow fragment shape but not the PKCE `?code=` query-param shape
  Supabase now defaults to, so the user silently fell through to
  `/onboarding` instead of `/reset`.

All three are about the user **failing to reach** `/reset` correctly. None
of them touch what happens **after** a successful `updateUser()` call —
this is a fourth, previously undocumented gap in the same area, not a
recurrence of any of the three.

## Root cause

**Writer:** `lib/features/auth/screens/reset_password_screen.dart`,
`_ResetPasswordScreenState._updatePassword()`. On success it called
`Supabase.instance.client.auth.updateUser(...)`, showed a "Password
updated" SnackBar, then `auth.signOut()`, `releaseDeviceSessionIdentity()`,
and reset `AppRouter.isPasswordRecovery = false` — with a trailing comment
claiming "The router's `_authRedirect` handles the navigation
automatically." That claim was false: no navigation call was ever made.

**Why the router never picked it up (confirmed by reading both files
directly, not inferred):**

- `GoRouter` is constructed at `lib/core/router/app_router.dart:84-89` with
  **no** `refreshListenable`. `lib/app.dart`'s `MaterialApp.router(
  routerConfig: AppRouter.router, ...)` (line 105) confirms this is the
  only router wiring — the only listeners registered in `app.dart`'s
  `initState` are `SubscriptionService.onStateChanged`,
  `NutritionWriteService.onStateChanged`, and `RankService.onStateChanged`
  (provider invalidation hooks, none touch navigation).
- `_authRedirect` (`app_router.dart:605`) only re-runs on an explicit
  navigation event. Calling `signOut()` in place doesn't trigger one.
- Even if `_authRedirect` did re-run, `/reset` is deliberately exempted
  from it (`isOnReset -> return null`, `app_router.dart:644`) — by design,
  since a legitimate recovery visitor has no normal session and must not be
  bounced by the "not authenticated -> /sign-in" branch mid-flow.

Net effect: after a successful reset the app is signed out but still
sitting on `/reset`, showing the confirmation SnackBar over a form with
nothing left to submit.

## Web vs native (ruled out as a deep-link bug)

`forgot_password_sheet.dart:57` sends `redirectTo:
'https://app.icanbefitter.com/reset'` — a plain HTTPS URL, not a custom
scheme. `android/app/src/main/AndroidManifest.xml` registers no Android App
Link and no custom-scheme intent-filter (only `MAIN`/`LAUNCHER`, a crop
activity, and Health Connect filters) — there is nothing on the device that
could hand this URL to the installed app. Recovery detection itself is
gated `if (kIsWeb)` in `lib/main.dart:107`, so it's inert on native
Android. The link opens the production **web build** in the phone's
browser, which is why it visually reads as "the app" to the user. Building
true native deep-linking is a separate, materially larger feature
(App Links manifest entry + a deep-link package + native intent handling)
and is explicitly out of scope for this fix.

## Fix

Added `if (mounted) context.go('/sign-in');` at the end of the success path
in `_updatePassword()`, after the existing sign-out sequence. This mirrors
the explicit-navigation pattern already used successfully elsewhere in the
same feature — `sign_in_screen.dart`'s `ref.listen` calls
`context.go('/restoring')` on its own success path rather than waiting for
the router to notice an auth-state change. No router-level change (no
`refreshListenable` added) — the fix is scoped to the one screen that owns
this transition.

The initial version of this fix put `signOut()`, `releaseDeviceSessionIdentity()`,
and the flag reset in the same try block as the new `context.go` call. This
branch's required plan-review (`docs/plan-reviews/signin-redesign-password-reset-fix.md`,
2 rounds) found two follow-on gaps in that shape before merge:

- **Round 1:** a `signOut()` network failure would hit the outer `catch`,
  surface a false "Could not update password" error (the password update
  had already succeeded), and skip the new navigation entirely. Fixed by
  giving `signOut()` its own inner try/catch that logs via `ErrorTelemetry`
  and swallows — a transient sign-out failure no longer blocks the fix this
  diagnose-doc exists for.
- **Round 2:** that same fix nested `releaseDeviceSessionIdentity()` inside
  `signOut()`'s try, so the same failure also skipped the device-identity
  release (OI-51) — the device could keep carrying the old user's push
  binding. Fixed by calling `releaseDeviceSessionIdentity()`
  unconditionally, after (not inside) that try block, matching the same
  unconditional-release pattern already used at four other `signOut()` call
  sites in this codebase (`auth_provider.dart`, `perform_sign_out.dart`,
  `settings_screen.dart`, `main.dart`).

## Files changed

| File | Change |
|------|--------|
| `lib/features/auth/screens/reset_password_screen.dart` | Added explicit `context.go('/sign-in')` after the sign-out sequence; isolated `signOut()` in its own try/catch; moved `releaseDeviceSessionIdentity()` to run unconditionally after it (plan-review rounds 1–2) |
| `test/contracts/password_reset_redirect_flow_test.dart` | Extended — new behavioral group exercises the real `_updatePassword()` code path (mocked Supabase HTTP transport, no network) and asserts navigation actually happens |

## Regression test

`test/contracts/password_reset_redirect_flow_test.dart`'s new behavioral
group pumps the real `ResetPasswordScreen` inside a minimal `GoRouter`,
seeds a local Supabase session via `auth.setInitialSession` (no network),
and injects a `MockClient` (`package:http/testing.dart`) into
`Supabase.initialize` so `updateUser`/`signOut`'s HTTP calls resolve
deterministically without hitting the real backend. Fills in matching valid
passwords, taps UPDATE PASSWORD, and asserts the app has navigated away
from `/reset`. This fails on pre-fix code (the screen never navigates) and
passes post-fix — a genuine behavioral assertion, not a source-grep
presence check.

## New bug class

Extends the password-reset-flow batch's pattern with a sibling: **"the
comment claims the router handles it, but nothing wires the router to the
event that comment relies on."** Any screen that ends a Supabase session
in place and expects `_authRedirect` to notice must either (a) navigate
explicitly, as this fix does, or (b) confirm a `refreshListenable` is
actually wired to `Supabase.auth.onAuthStateChange` — this codebase has
neither by default, so (a) is the safer default pattern going forward.
