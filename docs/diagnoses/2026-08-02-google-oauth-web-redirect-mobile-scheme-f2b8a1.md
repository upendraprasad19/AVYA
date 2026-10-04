---
bug_id: f2b8a1
date: 2026-08-02
batch: google-login-activation
status: shipped
symptom: |
  Google sign-in was never live in prod despite functionality-flow.md
  asserting "Email + Google OAuth work normally" — no Google OAuth client
  existed in Google Cloud Console (google-services.json oauth_client: [])
  and Android had no deep-link intent-filter to catch the redirect. While
  wiring these up (Track A: Google Cloud Console + Supabase dashboard
  config; Track B: this fix), a second latent defect surfaced in code:
  AuthNotifier.signInWithGoogle passed the mobile-only custom-scheme
  redirectTo unconditionally, including on the web build. On web, a browser
  cannot navigate to `io.supabase.icanbefitter://login-callback/`, and the
  URL wasn't on Supabase's redirect allowlist either, so the OAuth flow
  would have left web users stuck rather than returning them to the app.
concept: auth_google_oauth_redirect
sot_registry_entry: null
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthNotifier.signInWithGoogle", line: 311 }
readers:
  - { file: android/app/src/main/AndroidManifest.xml, method_or_widget: "MainActivity intent-filter (scheme io.supabase.icanbefitter)", line: 47 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/google_oauth_redirect_flow_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "redirectTo: 'io.supabase.icanbefitter://login-callback/', (unconditional, no kIsWeb branch)", absent: true, after_fix: true }
related_bugs: [e9f2a4]
recurrence: |
  Same bug class as e9f2a4 (Supabase dashboard Site URL overrides client
  redirectTo / redirectTo not matching platform) — see
  feedback_mistake_supabase_site_url_overrides_redirect_to.md. e9f2a4 fixed
  the password-reset redirectTo pointing at the wrong domain; this is the
  same class applied to a *platform* mismatch (mobile scheme used on web)
  rather than a wrong-domain mismatch. The known-good web origin
  (`https://app.icanbefitter.com`) established in e9f2a4's fix
  (`forgot_password_sheet.dart:57`) is reused here.
proposed_fix: |
  1. Branch `redirectTo` in `signInWithGoogle` on `kIsWeb`, matching the
     `kIsWeb` pattern already used elsewhere in the same file (`:49`,
     `:725`): web uses `https://app.icanbefitter.com`, mobile keeps
     `io.supabase.icanbefitter://login-callback/`.
  2. Add the missing Android deep-link intent-filter to
     `AndroidManifest.xml` so the mobile scheme has somewhere to land.
  3. Manual (non-code, Track A): create a Google Cloud OAuth 2.0 Web client
     with Supabase's callback URI, enable the Google provider in Supabase
     Auth with that Client ID/Secret, and add both
     `io.supabase.icanbefitter://login-callback/` and
     `https://app.icanbefitter.com` to the Supabase Redirect URLs allowlist.
regression_test_planned:
  - test/contracts/google_oauth_redirect_flow_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "auth_provider.dart kIsWeb branch added; AndroidManifest.xml intent-filter added; flutter analyze clean." }
  - { tier: 10, layer: secrets_api_keys, status: not_applicable, evidence: "Google OAuth Client ID/Secret are Supabase-dashboard-side config, not client secrets — no client-side key exposure." }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "Code-level fix applied (kIsWeb branch + manifest intent-filter); live end-to-end sign-in verification on a real device is the next step in this same session, to be run immediately after this commit." }
impact_analysis: |
  Blast-radius account (auth code + Android manifest, per docs/blast_radius.yaml),
  but narrowly scoped within that tier: contained to the Google OAuth entry
  point only. No other sign-in method's code path touched. The web branch is
  new-to-this-batch
  (Google OAuth was never functional on web before this fix, so there is no
  existing web behavior being changed) — only the previously-nonfunctional
  mobile-only redirect string is now conditional. Live end-to-end
  verification (Android device tap-through) still pending at commit time —
  tracked as the immediate next step, not a deferral.
blast_radius: account
---

# Google OAuth redirectTo hardcoded to mobile scheme, breaks on web

## Symptom

Investigating "activate Google login," `AuthNotifier.signInWithGoogle`
(`auth_provider.dart:307-326`) was found to pass a single hardcoded
`redirectTo: 'io.supabase.icanbefitter://login-callback/'` regardless of
platform — unlike every other platform-aware call in the same file
(`:49`, `:725`, both guarded by `kIsWeb`).

## Root cause

`signInWithOAuth`'s `redirectTo` must be a value the browser (web) or OS
(mobile) can actually resolve back into the app, AND it must be present on
Supabase's Redirect URLs allowlist. A browser has no handler for a custom
URI scheme like `io.supabase.icanbefitter://...` — on web this would leave
the user stranded after Google consent instead of returning to the app.

## Fix

`auth_provider.dart:311-317` now branches on `kIsWeb`:

```dart
redirectTo: kIsWeb
    ? 'https://app.icanbefitter.com'
    : 'io.supabase.icanbefitter://login-callback/',
```

Paired with `android/app/src/main/AndroidManifest.xml` gaining a
`BROWSABLE`/`VIEW` intent-filter for `io.supabase.icanbefitter://login-callback/`
so the mobile branch has an app to hand control back to (previously missing
entirely — Google sign-in could not have worked on Android before this
change either).

## Regression test

`test/contracts/google_oauth_redirect_flow_test.dart` — source-grep pins:
1. `auth_provider.dart` contains the `kIsWeb` branch and both literal
   redirect strings.
2. `AndroidManifest.xml` contains the `io.supabase.icanbefitter` /
   `login-callback` intent-filter.

## New bug class

Recurrence of the class from e9f2a4 (`redirectTo`/allowed-redirect-list
mismatch) — this instance is a platform (web vs. mobile) mismatch rather
than a wrong-domain mismatch. Added to
`feedback_mistake_supabase_site_url_overrides_redirect_to.md` as a second
instance.
