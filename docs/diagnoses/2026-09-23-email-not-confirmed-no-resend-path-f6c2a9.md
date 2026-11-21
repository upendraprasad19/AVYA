---
bug_id: f6c2a9
date: 2026-09-23
batch: email-confirm-resend (founder-forwarded support screenshot, account tier)
status: fixed
blast_radius: account
symptom: |
  Founder forwarded a screenshot of a real signup (sumitk142003@gmail.com)
  hitting a persistent "Email not confirmed" red SnackBar on sign-in,
  despite the founder having observed the user tap the confirmation link
  and be shown what looked like a success/confirmed state.

  Live verification against `auth.users` (project dedsavbjuwgarrhphgnl)
  confirmed `email_confirmed_at` was genuinely NULL for this user, so the
  sign-in error itself is accurate, not a display bug. Widening the query to
  every user who ever had a confirmation email sent in the prior 10 days
  found 6 of 9 real external signups never completed confirmation at all —
  some over a week old (`creativesekhar91@gmail.com` from 2026-09-21,
  `fdf@gmail.com` from 2026-09-17) — versus near-instant confirms for the
  founder's own QA/test accounts. Only one genuine external user
  (`chintamani78987@gmail.com`) ever completed confirmation via email, and
  that took 15 minutes. No hour in the sample had more than 2 signups, so
  this is not the built-in-mailer burst rate limit.

  Separately: `auth.one_time_tokens` still held sumitk142003@gmail.com's
  original, unconsumed `confirmation_token` row at investigation time — a
  successful `verifyOTP` consumes/deletes this row, so whatever the founder
  and Sumit saw, the confirmation call had not actually succeeded against
  Supabase as of that check. `client_errors` telemetry has zero rows for
  this user or for any `confirm`-tagged op_type in the whole window,
  meaning `AuthNotifier.confirmEmail` was never observed completing
  (success OR failure) for this attempt — consistent with, but not proof
  of, the link never actually reaching `ConfirmEmailScreen`/`verifyOTP` at
  all (e.g. Android App Link auto-verification failing open to a browser,
  per the existing `web_confirm_link_routing` bug class, diagnose 9c4e1a).
  This residual is NOT fully explained — see `residual` below.

  Regardless of root cause on the confirm side, tracing the failure path
  surfaced an independent, real gap: `sign_in_screen.dart` had a "Resend
  OTP" affordance for phone sign-in only. A user whose confirmation email
  is lost, expired, or never arrives has NO in-app way to request a fresh
  one — the only visible response to "Email not confirmed" was a transient
  SnackBar with no action.
concept: auth_email_confirmation_recovery
sot_registry_entry: not_applicable — a UX recovery affordance around an
  existing Supabase-managed auth flow, not a new Hive/Postgres writer/reader
  contract.
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthNotifier.resendConfirmationEmail — calls Supabase auth.resend(type: OtpType.signup)", line: 361 }
readers:
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "_showResendConfirmation gate (ref.listen) + _buildResendConfirmationLink", line: 180 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: auth.users, auth.one_time_tokens (read-only investigation queries; no writer here touches either)
cloud_columns: [auth.users.email_confirmed_at, auth.users.confirmation_sent_at]
contract_test_path: test/contracts/is_email_not_confirmed_message_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [auth_resend_confirmation_email]
  failure: [auth_resend_confirmation_email_failed]
cross_account_guard: Not applicable — resend targets whatever email the user just typed into the (unauthenticated) sign-in form; no session/Hive access involved.
forbidden_patterns_checked:
  - "adding a client-side cooldown/rate-limit for the resend tap — Supabase's own `resend` already rate-limits per email server-side and surfaces it as a normal AuthException, so a second limiter would be redundant and could disagree with the server's own window"
  - "showing the resend affordance for ANY auth error — gated specifically on AuthNotifier.isEmailNotConfirmedMessage so a wrong-password failure never offers a misleading recovery action (mirror-case test in sign_in_screen_resend_confirmation_test.dart)"
proposed_fix: |
  Two-part, scoped to the client-side gap only (the deliverability/App-Link
  root cause on the confirm side is tracked separately, not fixed here — see
  `residual`):

  1. `AuthNotifier.resendConfirmationEmail(String email)` — thin wrapper over
     Supabase's `auth.resend(type: OtpType.signup, email:)`, mirroring the
     existing `signInWithEmail`/`signUpWithEmail` state-machine shape
     (loading → success maps to `AuthStatus.info` with a "check your inbox"
     message, `AuthException` surfaces verbatim, anything else gets a
     generic fallback + telemetry).
  2. `AuthNotifier.isEmailNotConfirmedMessage(String?)` — pure detector
     (case-insensitive substring match on Supabase's own "Email not
     confirmed" GoTrue string), deliberately NOT `@visibleForTesting` since
     `sign_in_screen.dart` reads it in production, same reasoning as the
     existing `alreadyAuthenticatedConfirmMessage` sibling.
  3. `sign_in_screen.dart`: the `ref.listen` handler captures whether the
     LATEST error was specifically "Email not confirmed" into a local
     `_showResendConfirmation` flag BEFORE `resetState()` clears
     `errorMessage` (mirrors the existing `_resendSecondsRemaining`
     capture-before-reset shape used for phone OTP). When true, an inline
     "Didn't get the confirmation email? Resend it" link renders on the
     email sign-in step, below "Forgot password?". The flag is scoped to
     the currently-entered email and cleared by "CHANGE EMAIL"; a
     successful resend deliberately leaves it visible (user may need to
     resend again).
regression_test_planned:
  - test/contracts/is_email_not_confirmed_message_test.dart (new — pure detector, 5 cases incl. the mirror: a different auth failure and the sign-up confirmation-pending info message must NOT match)
  - test/auth/sign_in_screen_resend_confirmation_test.dart (new — 4 widget cases: affordance shows on "Email not confirmed", mirror case hides it on wrong-password, tapping it calls resendConfirmationEmail with the trimmed email exactly once and the affordance survives a successful resend, "CHANGE EMAIL" clears it)
impact_analysis: |
  Additive UI-only change on the sign-in screen's email step; no existing
  call site, provider, or Hive/Postgres contract is touched. `resend` is a
  read-of-Supabase's-own-state call (re-issues a token for an EXISTING
  unconfirmed `auth.users` row) — it cannot create an account, change a
  password, or authenticate the caller. Worst case of a race (user resends
  right as an old link IS being verified) is Supabase's own token
  invalidation semantics, unchanged by this fix.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/auth/ — No issues found (10.3s). New/changed: auth_provider.dart (resendConfirmationEmail + isEmailNotConfirmedMessage), sign_in_screen.dart (_showResendConfirmation + _buildResendConfirmationLink)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live SQL against dedsavbjuwgarrhphgnl: auth.users.email_confirmed_at IS NULL for sumitk142003@gmail.com; auth.one_time_tokens still holds its original unconsumed confirmation_token row; auth.audit_log_entries is empty project-wide (0 rows) so no audit trail was available for the confirm attempt itself." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Founder confirmed Brevo SMTP is already configured for this project — the historically-undocumented 'no custom SMTP' cause from lib/features/auth/CLAUDE.md's pitfall table does not apply here as originally suspected. The 6-of-9 non-confirmation rate is still unexplained by this fix alone; see residual." }
mutation_proven:
  mutated: "lib/features/auth/providers/auth_provider.dart:346 — isEmailNotConfirmedMessage's body replaced with a bare `false;` (detector permanently off)."
  result: "5 of 9 tests reddened: all 4 sign_in_screen_resend_confirmation_test.dart cases that depend on the affordance ever appearing, plus none of the pure-function tests that assert isFalse (correctly still pass — they assert the negative, which a neutered detector trivially satisfies too, confirming those specific cases are NOT proof of the positive path). The 2 tests asserting the mirror/negative case (wrong-password affordance absence, unrelated-message non-match) stayed green throughout, as expected."
  confirmed_applied: "Ran `flutter test test/contracts/is_email_not_confirmed_message_test.dart test/auth/sign_in_screen_resend_confirmation_test.dart` before, during (mutated), and after (reverted) — 9/9 green → 4/9 green (5 failing) → 9/9 green."
residual: |
  NOT closed by this fix, stated explicitly per §4.2 (no silent deferral):
  why Sumit's confirm-link tap did not result in a consumed
  `confirmation_token` row or ANY confirm-related client_errors telemetry,
  despite the founder observing what looked like a success/confirmed state,
  is unresolved. Candidate causes not yet distinguished: (a) the Android
  App Link failed to auto-verify and the tap opened a browser instead of
  the app (the existing `web_confirm_link_routing` class, diagnose 9c4e1a,
  already covers the WEB redirect once reached — but this would need the
  browser path to ALSO reach and complete `verifyOTP`, which the unconsumed
  token row says did not happen); (b) the founder briefly glimpsed
  `ConfirmEmailScreen`'s loading state ("Confirming your account...") and
  read the "CONFIRM ACCOUNT" header as a completed confirmation rather than
  an in-progress one; (c) a second signup/resend attempt invalidated the
  original link before it was tapped. Investigation was constrained by
  `auth.audit_log_entries` holding zero rows project-wide (unclear whether
  disabled, unpopulated by this Supabase project's GoTrue config, or
  purged) — there is no server-side audit trail to distinguish these.
  Founder has custom SMTP (Brevo) already configured, which also rules out
  the historically-documented "no custom SMTP" deliverability cause as the
  explanation for the wider 6-of-9 non-confirmation pattern found during
  this investigation — that pattern's cause is ALSO still open. Filed as
  OI-244 for follow-up; not silently dropped.
---

## Summary

A founder-forwarded screenshot of a real user's "Email not confirmed"
sign-in failure led to two findings: (1) live-verified the account is
genuinely unconfirmed and this is not a display bug, with evidence the
broader confirmation-completion rate for real external signups is
unexpectedly low; (2) the app had no self-service recovery path for this
specific failure. This diagnose-doc closes (2) only — a real "resend
confirmation email" affordance — and explicitly leaves (1)'s root cause
open as a stated residual rather than assuming the resend button fixes it.

## Root cause

For the shipped fix (the missing recovery path): `sign_in_screen.dart` was
built out for phone-OTP resend only; the email sign-in error path reused
the same generic transient-SnackBar handling as every other auth failure,
with no branch for the specific, self-service-recoverable "Email not
confirmed" case.

For the residual (why this specific user's email is still unconfirmed):
not determined — see `residual` above.

## Fix

See `proposed_fix` in the frontmatter. `AuthNotifier.resendConfirmationEmail`
+ `AuthNotifier.isEmailNotConfirmedMessage` in
`lib/features/auth/providers/auth_provider.dart`; `_showResendConfirmation`
+ `_buildResendConfirmationLink` in
`lib/features/auth/screens/sign_in_screen.dart`.

## Regression tests

- `test/contracts/is_email_not_confirmed_message_test.dart`
- `test/auth/sign_in_screen_resend_confirmation_test.dart`

Both mutation-proven — see `mutation_proven` in the frontmatter.
