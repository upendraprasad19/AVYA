---
bug_id: d3a7c9
date: 2026-08-06
batch: post38-auth-fixes (Unit 1 — Google OAuth never completes the state machine)
status: fixed
blast_radius: platform
symptom: >
  Founder taps CONTINUE WITH GOOGLE on APK 1.0.0+38, completes Google consent,
  and the app sits on the sign-in screen with BOTH buttons spinning forever.
  Force-quitting and reopening lands on Home, already signed in. Supabase had
  issued the token the whole time — auth.users.last_sign_in_at moved to
  2026-08-06 12:31:37 UTC (18:01:37 IST), matching the screenshot clock.
concept: oauth_signin_completion
sot_registry_entry: oauth_signin_completion
writers: >
  lib/features/auth/providers/auth_provider.dart:322-346 AuthNotifier
  .signInWithGoogle sets AuthStatus.loading at :323, awaits signInWithOAuth
  (which returns the instant the external browser launches and carries NO
  session), then falls out of the try WITHOUT ever setting AuthStatus.success.
  The session arrives later and out of band on GoTrue's onAuthStateChange
  stream, which nothing was consuming for navigation.
readers: >
  lib/features/auth/screens/sign_in_screen.dart:202 derives
  `isLoading = authState.status == AuthStatus.loading` and feeds it to BOTH the
  Google button (:347-353) and the email CONTINUE button — one hung call, two
  spinners, which is exactly what the screenshot shows.
  lib/features/auth/screens/sign_in_screen.dart:167 `if (next.status ==
  AuthStatus.success)` -> :198 `context.go('/restoring')` is the ONLY navigation
  trigger in the flow, so it never fired.
hive_key_prefix: "not_applicable — no Hive key is read or written by this fix"
hive_key_formula: >
  not_applicable. The fix is confined to in-memory Riverpod state (AuthState2)
  plus a GoTrue stream subscription; the post-auth Hive session is opened later
  by RestoringScreen via HiveUserSession.openForUser, unchanged here.
sync_methods: >
  None. signInWithGoogle never reaches _ensureLocalUser/hydrateFromCloud (OAuth
  has no synchronous response.user — see lib/features/auth/CLAUDE.md), and this
  fix does not change that. The convergence point remains RestoringScreen.
restore_methods: >
  None changed. Reaching AuthStatus.success routes to /restoring, whose existing
  resolveDestination + restoreFromCloudForUser behaviour is untouched.
cloud_table: auth.users
cloud_columns: >
  last_sign_in_at (READ ONLY, as diagnostic evidence — it proved the server-side
  sign-in succeeded while the UI hung, which is what localised the bug to the
  client). No column is written by this fix.
contract_test_path: test/contracts/google_oauth_session_navigation_behavioral_test.dart
ist_handling: >
  not_applicable — no date keys, counters, or day-boundary windows in this path.
  The IST conversions in this doc are presentational only (UTC telemetry
  timestamps rendered as IST to line up with the founder's screenshot clock).
provider_invalidations: >
  None added. The notifier already drives sign_in_screen's existing
  ref.listen(authNotifierProvider); this fix only makes that listener actually
  receive the success transition it was always written to expect.
telemetry_op_types: >
  No new op_type. auth_oauth_launch_failed is added to the Edge Function's
  PRE_AUTH_OP_TYPES allow-list in the sibling b6e4f2 fix so that a FAILED launch
  can be recorded at all; this fix's own success path emits nothing.
cross_account_guard: >
  Unaffected. The watch resolves only on a non-null session and then sets
  in-memory status; it opens no Hive box and reads no user-scoped data. The
  Layer A wrapUserScopedBox / Layer B invalidation guards run later and
  unchanged, in RestoringScreen.
forbidden_patterns_checked: >
  No raw Hive.box; no setState for shared state; no inline isPro; no new
  functions.invoke; no secrets; no unawaited() without an error sink; no
  Container(color:+decoration:). The new subscription is cancelled on success,
  on launch failure, on timeout, and via ref.onDispose, so it cannot leak.
proposed_fix: >
  Repair the WRITER so the existing reader contract holds unchanged. AuthNotifier
  subscribes to authStateChanges() BEFORE launching the browser (so a fast
  redirect cannot land in the gap) and sets AuthStatus.success on the first
  event carrying a NON-NULL session. A 90s timeout (oauthSessionWait) returns
  the status to idle — deliberately idle and not error, because the dominant
  cause is the user dismissing the consent screen, and an error toast for a
  deliberate cancel is noise. Three seams (ensureSupabaseReady,
  authStateChanges, launchGoogleOAuth) are @visibleForTesting non-private,
  matching the pattern check_email_registered_behavioral_test already uses on
  this notifier, because a real Supabase client cannot exist in a pure VM test.
  REJECTED alternative — adding a GoRouter refreshListenable: it would change
  routing behaviour globally for every route and every auth event, to fix one
  screen's entry path.
regression_test_planned: >
  test/contracts/google_oauth_session_navigation_behavioral_test.dart — 4 cases,
  MUTATION-PROVEN. Deleting the _watchForOAuthSession() call reproduces the
  reported symptom exactly (status stays loading) and fails 2 of the 4. Case 2 is
  the discriminator — a null-session event (initialSession on a signed-out
  client, signedOut) must NOT be read as success, or the fix would navigate a
  user who never signed in. Case 3 pins that a failed launch cancels the watch so
  a later stray session cannot resurrect success. Case 4 uses fakeAsync to prove
  the abandoned-consent timeout releases the spinner.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ -> 0 errors, 0 warnings; 4/4 behavioral tests green; mutation reproduces the reported symptom" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive read or write in this path; the session box is opened later by RestoringScreen" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "auth.users row 9e6bde97 last_sign_in_at = 2026-08-06 12:31:37+00 — proves the token WAS issued while the UI hung, localising the defect to the client" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this unit" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched by this unit" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no table access" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read; OAuth client config is account-side and unchanged" }
  - { tier: 11, name: external_services, status: verified, evidence: "Google Cloud OAuth client + Supabase provider config were already live from f2b8a1 (2026-08-02); account 9e6bde97 was created through that provider on 2026-08-02 13:11:55+00, so provider setup is NOT implicated" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the contract was: server issues a session, client observes it and navigates. The client half was missing entirely; the test drives the real notifier through the OAuth-shaped event (session with no synchronous response.user)" }
impact_analysis: >
  EVERY user who tried Google sign-in was affected, on every build since Google
  OAuth went live (f2b8a1, 2026-08-02) — this is not a 1.0.0+38 regression, it is
  the first time anyone exercised the path on a shipped APK. There was no
  workaround a user could discover except force-quitting the app, which looks
  identical to a crash. For a founding-cohort sign-up funnel this is a total
  loss of the Google entry point: the account IS created and the session IS
  issued, so the user is left believing sign-in is broken while their account
  quietly exists.
  Recurrence: this is diagnose c8f1d3's lesson — nothing in this app observes
  auth state on your behalf, so a screen must navigate explicitly — applied then
  to the password-reset EXIT path and never to the OAuth ENTRY path. The f2b8a1
  doc anticipated "stuck" only from a redirect-scheme mismatch and shipped with
  an empty success: [] list, so nothing had ever asserted the completion.
related_bugs: c8f1d3, f2b8a1, b3f9e7
recurrence: >
  Third instance of "no refreshListenable exists, so navigate explicitly"
  (9f5c41 timing, c8f1d3 exit path, now d3a7c9 entry path). The generalisable
  rule: any flow whose result arrives OUT OF BAND (redirect, deep link, push)
  needs an explicit observer — the router will not notice on its own.
---

# Google sign-in never navigates (d3a7c9)

## What made this hard to see

The failure is invisible from the server. `last_sign_in_at` moves, a session row
exists, telemetry shows a healthy restore a few minutes later — every server-side
signal says success. Only the client's own state machine was stuck, and the one
place that would have recorded a client-side auth complaint (`ErrorTelemetry`)
could not write a row at all while signed out — see the sibling diagnose b6e4f2.

## Why the timeout is idle, not error

Backing out of the Google consent screen is a normal user action, not a fault.
Reporting it as an error trains users to distrust a screen that is working. The
requirement is only that the UI stop claiming to be busy, which `idle` satisfies.

## Verification

- `flutter analyze lib/` — 0 errors, 0 warnings.
- 4/4 cases green; mutation (removing the watch) turns cases 1 and 4 red with
  `Actual: AuthStatus.loading`, i.e. the founder's exact symptom.
- Live: `auth.users` `9e6bde97` `last_sign_in_at = 2026-08-06 12:31:37+00`.
