---
bug_id: c9e2b7
date: 2026-08-06
batch: post38-auth-fixes (Unit 2 — password reset replaced with a 6-digit code)
status: fixed
blast_radius: platform
symptom: >
  Founder requests a password reset FROM THE ANDROID APP, receives the email,
  opens the link (which loads the web app), lands on the branded SET NEW
  PASSWORD screen, types a new password, and gets "Auth session missing!" in
  red. The screen also names no account at all, so there is no way to tell a
  wrong-account reset from a right one. Both are the same root cause.
concept: password_recovery_session
sot_registry_entry: password_recovery_session
writers: >
  lib/features/auth/widgets/forgot_password_sheet.dart:55-58 called
  resetPasswordForEmail(email, redirectTo: 'https://app.icanbefitter.com/reset')
  — HARDCODED to the web origin with no kIsWeb branch, from every platform
  including the APK. Under PKCE (the default; AuthFlowType appears ZERO times in
  lib/) gotrue writes a code-verifier into the CALLING client's storage —
  gotrue_client.dart:1118 _generatePKCECodeChallenge -> _asyncStorage.setItem.
readers: >
  The browser at app.icanbefitter.com, which must exchange the emailed ?code=
  using that verifier. It was never written there — it is in the APK's storage —
  so detectSessionInUrl's exchange produces no session. Then
  lib/core/utils/password_recovery_detector.dart:48-50 matches on link SHAPE
  only and sets AppRouter.isPasswordRecovery, and
  lib/features/auth/screens/reset_password_screen.dart:44 gates on THAT FLAG,
  not on a session — so the form renders and only fails at
  reset_password_screen.dart:66-68 updateUser, which throws
  AuthSessionMissingException whose message is literally "Auth session missing!".
hive_key_prefix: "not_applicable — recovery state lives in the GoTrue storage adapter, not a Hive app box"
hive_key_formula: >
  The PKCE verifier is stored by gotrue under
  '${Constants.defaultStorageKey}-code-verifier' in the platform's own storage
  adapter. The app neither reads nor writes that key; the fix removes the
  dependency on it entirely.
sync_methods: >
  None. Password recovery does not participate in the domain sync fan-out.
restore_methods: >
  None. A successful reset signs out and routes to /sign-in
  (reset_password_screen.dart, per c8f1d3), so the normal post-auth restore runs
  on the NEXT sign-in, unchanged.
cloud_table: auth.users
cloud_columns: "encrypted_password (written server-side by GoTrue via updateUser); recovery_token / recovery_sent_at managed by GoTrue"
contract_test_path: test/contracts/password_recovery_code_flow_behavioral_test.dart
ist_handling: >
  not_applicable — the code's expiry window is enforced server-side by GoTrue in
  UTC; the client neither computes nor displays a date key here.
provider_invalidations: >
  None. The sheet is local widget state; the reset screen reads the session
  directly from Supabase.instance.client.auth rather than through a provider.
telemetry_op_types: >
  auth_password_recovery_verify_failed added at the verify callsite AND added to
  the Edge Function's PRE_AUTH_OP_TYPES allow-list (sibling b6e4f2), so a failed
  verification is recordable — the whole flow runs signed-out, which is exactly
  the state that used to be unloggable.
cross_account_guard: >
  Unaffected in the guard's own terms, and slightly strengthened in practice:
  the reset screen now proves a session exists before offering the form, so it
  can no longer act on behalf of an account it has not authenticated as. No
  Hive box is opened by this flow.
forbidden_patterns_checked: >
  No raw Hive.box; no setState for shared state; no inline isPro; no secrets;
  no Container(color:+decoration:). The verify callsite catches AuthException
  separately from the generic catch so GoTrue's own actionable wording
  ("Token has expired or is invalid") reaches the user instead of being
  flattened into a generic line.
proposed_fix: >
  Replace the emailed LINK with an emailed 6-DIGIT CODE. ForgotPasswordSheet
  becomes a two-step flow in one surface: email -> code -> verifyOTP(email:,
  token:, type: OtpType.recovery) -> a real session -> context.go('/reset').
  Verified present in the installed SDK at gotrue_client.dart:672, which carries
  a dedicated recovery branch.
  Founder decision, on the explicit brief "assume this app will be here
  forever": this DELETES the bug class. Four of the five password-reset
  diagnoses to date (e9f2a4, 9f5c41, b7d4e2, and this one) are URL parsing or
  routing bugs in a channel we do not control; removing the link removes the
  surface. It also needs NO global authFlowType change, so — unlike moving
  recovery to the implicit flow — it cannot regress the OAuth path that Unit 1
  is repairing in the same batch.
  Deliberately NOT a new route: keeping both steps inside the sheet leaves the
  whole entry on /sign-in, which is already reachable signed-out and already
  exempt from _authRedirect, so there is no new redirect exemption to get wrong.
  ALSO: reset_password_screen gains a real session-aware state (§4.4 rule 13) —
  with a session it shows currentUser.email (the founder's "no account shown"
  observation, which is only answerable ONCE a session exists); without one it
  says the link expired or was opened on another device and offers a new code,
  instead of accepting a password and failing at submit.
  Requires a matching Supabase dashboard change (recovery email template ->
  {{ .Token }}), completed by the founder 2026-08-06.
regression_test_planned: >
  test/contracts/password_recovery_code_flow_behavioral_test.dart — TWO cases,
  both against reset_password_screen's session gate, both green, and the first
  MUTATION-PROVEN (deleting the `if (!_hasSession)` early return makes the
  password form render with no session — the shipped bug — and turns it red).
  Case 1: no session -> the expired/other-device state, and NOT the form. This
  is the discriminator: it is the exact state that previously rendered a
  working-looking form. Case 2: with a session -> the form renders and displays
  currentUser.email.
  ⚠ CORRECTED after round-1 review. This field first described four cases
  including two driving ForgotPasswordSheet's step machine ("send success
  advances to the code step", "a wrong-length code is rejected client-side").
  Those cases do not exist and never did — `grep -rln "ForgotPasswordSheet"
  test/` returns nothing. The session gate is covered; the SHEET's two-step
  machine and its verifyOTP call are NOT, and OI-100 tracks writing them rather
  than this doc implying coverage it does not have.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ -> 0 errors, 0 warnings; verifyOTP + OtpType.recovery confirmed present in gotrue 2.27.1 at gotrue_client.dart:661-683" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no app Hive box in this path; the PKCE verifier lived in gotrue's own storage adapter and the fix stops depending on it" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change; GoTrue owns the recovery token columns" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "auth.audit_log_entries is empty (0 rows, all time) — checked, so it could NOT be used as evidence either way for this flow; the diagnosis rests on the client code path and the founder's screenshot instead" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this unit" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "recovery goes direct to GoTrue, not through an Edge Function" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "auth schema, GoTrue-managed" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read by the client; the recovery email template is account-side config, changed by the founder" }
  - { tier: 11, name: external_services, status: fixed_in_this_batch, evidence: "Supabase Auth -> Emails -> Reset Password body switched to {{ .Token }} by the founder 2026-08-06 (screenshot confirmed). Until that change the email carried a link, and the client tolerates both: the old link path still works for emails already in flight." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the contract moves from 'the browser that opens the link must hold the verifier' — unsatisfiable across devices — to 'the user types a code into whichever client they are holding', which has no device binding at all" }
impact_analysis: >
  Password reset was unusable for the most common real pattern, and the failure
  was DETERMINISTIC rather than flaky: PKCE binds the emailed code to the client
  that requested it, so request-on-phone/open-in-browser, and equally
  request-on-laptop/open-on-phone, could never complete. The user reaches a
  correct-looking form, types a password, and is told "Auth session missing!" —
  an internal phrase that gives them nothing to act on and no reason to suspect
  the device, which is the actual variable.
  For a recovery flow this is close to worst-case severity: it is the path a
  locked-out user takes, so its failure mode is permanent account loss with no
  self-service alternative.
  What let it survive four prior fixes: e9f2a4, 9f5c41 and b7d4e2 all pinned link
  DETECTION and c8f1d3 pinned post-success NAVIGATION. Nothing ever asserted
  that a SESSION EXISTS at /reset, so the tests were green while the last step
  could not work. That is the exact false-confidence shape of
  feedback_source_grep_false_confidence.
  Trade-off accepted: one extra step (typing six digits) versus a one-tap link.
  Chosen knowingly — an emailed link is a bearer credential, and link-prefetching
  mail scanners silently consume one-time links, which is an unfixable failure
  mode we now do not have.
related_bugs: e9f2a4, 9f5c41, b7d4e2, c8f1d3
recurrence: >
  Fifth password-reset diagnose, and the first to change the CHANNEL rather than
  patch the parser. The generalisable rule: when a bug class keeps recurring in
  one surface, count the fixes — four URL-handling fixes in fifteen days is the
  signal to delete the surface, not to parse it more carefully.
---

# The reset link could only ever work on the device that asked for it (c9e2b7)

## Why it is deterministic, not flaky

PKCE's security property is that the emailed code is useless without a secret
held by the requester. That is genuinely good — an intercepted reset email
cannot be redeemed. The cost is that "the requester" means *that client's
storage*, so the moment the link is opened anywhere else the exchange has
nothing to verify against. Not a race, not a timeout: structurally impossible.

## Why the screen let the user get all the way to submit

`reset_password_screen.dart:44` gated on `AppRouter.isPasswordRecovery`, which
only means *this URL looked like a recovery link*. Shape, not session. So the
form rendered, accepted a password, and failed at the last possible moment.

## Why a code, and not implicit-flow links

| Option | Cross-device | Email is a bearer credential | Touches global auth flow |
|---|---|---|---|
| PKCE link (before) | ✗ | ✗ | — |
| Implicit-flow link | ✓ | ✗ **yes — anyone with the inbox** | ✓ risks OAuth |
| **6-digit code (chosen)** | ✓ | ✓ safe | ✗ none |
