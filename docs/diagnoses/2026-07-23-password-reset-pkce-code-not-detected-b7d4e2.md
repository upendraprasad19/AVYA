---
bug_id: b7d4e2
date: 2026-07-23
batch: password-reset-flow
status: shipped
symptom: |
  Password-recovery email link (https://app.icanbefitter.com/reset?code=<uuid>)
  lands on the SPA, briefly shows /restoring, then routes to /onboarding
  instead of the in-app reset-password form. The user never sees /reset.
concept: auth_password_reset_pkce_detection
sot_registry_entry: null
writers:
  - { file: lib/main.dart, method_or_widget: "main() (recovery detection via PasswordRecoveryDetector)", line: 108 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "static isPasswordRecovery flag", line: 73 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: "_SplashScreenState._navigateNext", line: 264 }
  - { file: lib/features/auth/screens/reset_password_screen.dart, method_or_widget: "_ResetPasswordScreenState.initState (guard)", line: 42 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/password_recovery_detector_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "PasswordRecoveryDetector.detect scoped code-param check applied to any path", absent: true, after_fix: true, note: "Scoped to uri.path == '/reset' — the exact redirectTo target — so an unrelated PKCE code (e.g. future OAuth flow) is never misclassified as recovery." }
  - { pattern: "manual exchangeCodeForSession call duplicating detectSessionInUrl's auto-exchange", absent: true, after_fix: true, note: "detectSessionInUrl (default true on web, supabase_service.dart:49-52 has no override) already performs the exchange; the fix only adds the routing-flag detection, not a second exchange." }
proposed_fix: |
  1. Extract the inline fragment-detection block from main.dart into a pure,
     unit-testable PasswordRecoveryDetector.detect(Uri) function
     (lib/core/utils/password_recovery_detector.dart).
  2. Add a second branch to the detector: uri.path == '/reset' &&
     uri.queryParameters.containsKey('code') -> isRecovery = true. This is
     the PKCE-flow shape supabase_flutter 2.x defaults to; the prior
     fragment-only check (`fragment.contains('type=recovery')`) never
     covered it.
  3. main.dart calls PasswordRecoveryDetector.detect(Uri.base) and sets
     AppRouter.isPasswordRecovery / stashes tokens from the result,
     preserving existing behavior for the fragment-based shape.
regression_test_planned:
  - test/contracts/password_recovery_detector_test.dart (new — behavioral, constructs Uris directly)
  - test/contracts/password_reset_redirect_flow_test.dart (updated — source-grep, extended for new detector file)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "lib/main.dart, lib/core/utils/password_recovery_detector.dart — flutter analyze clean, 20/20 contract tests pass (5 new behavioral + 15 source-grep)." }
  - { tier: 2, layer: hive, status: not_applicable, evidence: "No Hive read/write in this flow — routing-only bug." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 6, layer: edge_function, status: not_applicable, evidence: "No Edge Function involved — Supabase Auth's built-in code-exchange handles the PKCE session, no custom EF." }
  - { tier: 11, layer: external_services, status: verified, evidence: "Fix correctness depends on the Supabase Auth dashboard's Redirect-URL allowlist including https://app.icanbefitter.com/reset (sibling risk to diagnose e9f2a4, where the dashboard Site URL overrode redirectTo). The observed bug-report URL (https://app.icanbefitter.com/reset?code=<uuid>#/restoring) is direct evidence the allowlist already includes this exact redirectTo today — the PKCE code reached /reset intact, only the client-side classification was missing. B-pass review (docs/reviews/0fc99a56da0c-review.md, Finding 2) flagged this tier was omitted; added retroactively." }
impact_analysis: |
  Low risk, contained to auth recovery routing. No change to
  resetPasswordForEmail's redirectTo, the Supabase dashboard Site URL, or
  Supabase.initialize()'s detectSessionInUrl behavior — the PKCE code
  exchange itself was already working correctly (confirmed: the app landed
  in an authenticated state, proving the exchange succeeded). Only the
  client-side classification of "this authenticated session came from a
  recovery link" was missing. Worst case if the new branch had a bug: the
  PKCE-shape link would continue to silently misroute exactly as it does
  today (no new failure mode introduced) — the fragment-based branch is
  untouched and unaffected.
blast_radius: account
---

# Password-reset PKCE `?code=` link not detected as recovery — falls through to /onboarding

## Symptom

`b49ed15b` (original in-app reset flow) and `3e7090f2` (fragment-timing fix,
diagnose `9f5c41`) both fixed the **implicit-flow** URL shape
(`#access_token=...&refresh_token=...&type=recovery`). Supabase's actual
current link for this project uses the **PKCE flow** instead — the observed
URL is:

```
https://app.icanbefitter.com/reset?code=<uuid>#/restoring   (first paint)
https://app.icanbefitter.com/reset?code=<uuid>#/onboarding  (lands here)
```

No `type=recovery` fragment is present at all — only a `code` query param.

## Root cause

- `forgot_password_sheet.dart:57` — `resetPasswordForEmail(redirectTo: 'https://app.icanbefitter.com/reset')`.
  Matches the observed URL's path exactly.
- `pubspec.yaml:37` — `supabase_flutter: ^2.12.4`, which defaults to the
  **PKCE auth flow** with `detectSessionInUrl: true` on web.
- `lib/core/services/supabase_service.dart:49-52` — `Supabase.initialize()`
  passes no `authFlowType`/`detectSessionInUrl` override, so the SDK
  auto-detects the `?code=` query param and silently exchanges it for a real
  session during `initialize()` — this is why the app ends up authenticated
  instead of erroring.
- `lib/main.dart` (pre-fix, was the only writer of `AppRouter.isPasswordRecovery`
  since `3e7090f2`) only checked `Uri.base.fragment` for `'type=recovery'` —
  the implicit-flow shape. It had no branch for the PKCE `?code=` shape.
- Because the flag never got set, `splash_screen.dart`'s `_navigateNext`
  (line 264) fell through to its normal authenticated-user branch —
  `context.go('/restoring')` — instead of the recovery branch
  (`context.go('/reset')`, line 270). `RestoringScreen` then classified the
  (recovery-only) session via `AuthSessionBootstrapper.resolveDestination`
  and, since the account looked unprovisioned, routed to `/onboarding`.

This is a **new gap**, not a regression from `b49ed15b`/`3e7090f2` — those
fixes correctly hardened the fragment-based detection's timing; neither was
ever built to recognize the PKCE query-param shape.

## Fix

Extracted the detection logic from `main.dart` into a pure function,
`PasswordRecoveryDetector.detect(Uri)` (`lib/core/utils/password_recovery_detector.dart`),
and added a second branch recognizing `uri.path == '/reset' && uri.queryParameters.containsKey('code')`.
No change to the actual PKCE exchange (`detectSessionInUrl` already handles
it correctly) — only the routing classification.

Extracting to a pure function also fixes a coverage gap: the existing
regression test (`password_reset_redirect_flow_test.dart`) is source-grep
only (presence-checks against raw file text), which this repo's own
`feedback_source_grep_false_confidence.md` flags as insufficient alone. The
new `password_recovery_detector_test.dart` exercises the extracted function
with constructed `Uri`s and asserts actual boolean outcomes — a real
behavioral test.

## Files changed

| File | Change |
|------|--------|
| `lib/core/utils/password_recovery_detector.dart` | New — pure `PasswordRecoveryDetector.detect(Uri)`, both fragment + PKCE branches |
| `lib/main.dart` | Delegates to the extracted detector instead of inlining the fragment check |
| `test/contracts/password_recovery_detector_test.dart` | New — behavioral test, 5 cases |
| `test/contracts/password_reset_redirect_flow_test.dart` | Updated — source-grep pins for the new detector file + main.dart delegation |

## Regression test

`test/contracts/password_recovery_detector_test.dart` — 5 tests, fails on
pre-fix `PasswordRecoveryDetector` (fragment-only) and passes after the fix:
1. PKCE `?code=` on `/reset` → `isRecovery == true` (the actual bug shape)
2. Legacy fragment shape still detected + tokens extracted
3. `code` param on an unrelated path (`/sign-in`) → NOT flagged
4. `/reset` with no `code` param and no recovery fragment → NOT flagged
5. Unrelated fragment (`#/restoring`) → NOT flagged

## New bug class

Extends the "GoRouter clears URL fragment before widget can read it" class
(`9f5c41`) with a sibling: **"recovery detector built for one Supabase auth
flow shape misses another"** — a detector hardened for timing can still be
incomplete for coverage. Any future Supabase SDK upgrade that changes the
default auth flow type again should re-verify both branches of
`PasswordRecoveryDetector.detect` against a live link.
