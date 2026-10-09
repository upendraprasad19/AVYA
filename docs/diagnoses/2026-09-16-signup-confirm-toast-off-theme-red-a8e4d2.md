---
bug_id: a8e4d2
date: 2026-09-16
batch: obs-batch-2026-09-16
status: fixed
blast_radius: account
symptom: >-
  On the signup screen, after tapping CREATE ACCOUNT with email confirmation
  required, the "Check your email (and spam folder) for a confirmation
  link, then sign in." message rendered in a plain red SnackBar
  (AppColors.bad) — jarring and inconsistent with the Wardroom dark theme.
  Founder: "Red toast to be coloured different. Wardroom theme."
concept: auth_toast_severity_styling
recurrence: >-
  New. Grepped docs/diagnoses/INDEX.md and the memory feedback_*.md files for
  prior toast/snackbar coloring or Wardroom-palette-violation bugs — no
  matching prior diagnose-doc for this class.
sot_registry_entry: not_applicable — a client-side UI severity/styling mapping, not a Hive/Postgres writer/reader concept.
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method: "signUpWithEmail — confirmation-pending branch now sets AuthStatus.info", line: 384 }
readers:
  - { file: lib/features/auth/screens/sign_in_screen.dart, method: authToastStyleFor, line: 31 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method: "ref.listen SnackBar renderer", line: 185 }
hive_key_prefix: n/a — no Hive key participates; AuthState2 is in-memory Riverpod state
hive_key_formula: n/a
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/auth_toast_info_status_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "a non-error AuthState2 message forced into AuthStatus.error for lack of any other bucket", absent_after_fix: true }
proposed_fix: >-
  `AuthState2` had only one non-idle/loading/success bucket — `error` —
  reused for every message regardless of whether it represented an actual
  failure or an expected happy-path next-step. Added `AuthStatus.info` to
  the enum; the signup confirmation-pending branch in
  `signUpWithEmail` now sets `info` instead of `error`. Extracted a pure
  `authToastStyleFor(AuthStatus)` mapping in `sign_in_screen.dart`
  (`info` → Wardroom gold `AppColors.accent` bg / `AppColors.bgDeep` text,
  matching `SyncBanner`'s established tone for the same class of
  informational/next-step message; everything else → the existing red
  `AppColors.bad` / white) and wired the `ref.listen` SnackBar renderer
  through it. Deliberately left the sibling "An account with this email
  already exists. Please sign in." message on `AuthStatus.error` — that one
  represents a real signup conflict requiring the user to change what they
  were doing, not a next-step happy path, so red remains the correct
  semantic (flagged during investigation, not treated as part of this bug).
regression_test_planned:
  - test/contracts/auth_toast_info_status_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/contracts/auth_toast_info_status_test.dart -> 7/7 passed. Also re-ran test/auth/confirm_email_screen_test.dart, test/contracts/check_email_registered_behavioral_test.dart, test/contracts/confirm_email_error_mapping_test.dart, test/contracts/google_oauth_session_navigation_behavioral_test.dart (the other AuthStatus-touching suites) -> all pass unchanged, confirming the new enum value introduces no regression (no switch statement anywhere pattern-matches AuthStatus exhaustively — grepped for it, zero hits). Mutation-proven: reverted authToastStyleFor to unconditionally return the red/white pair -> exactly 1 of 7 assertions reddened (the 'info renders Wardroom gold, not red' test, background Expected #D4B270 / Actual #D7604E), the other 6 (including the structural wiring checks and the 'already exists stays error' regression guard) stayed green; restored the fix and re-ran -> 7/7 green again." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive key participates" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call — purely client-side UI state and rendering" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "no client-server contract change; Supabase's response shape is unchanged, only the LOCAL classification of one already-existing branch's message" }
impact_analysis: >-
  Account-tier (lib/features/auth/** glob), purely cosmetic. Additive enum
  value with no removed member, so no existing `AuthStatus` comparison can
  silently break — verified no exhaustive switch/pattern-match on
  `AuthStatus` exists anywhere in lib/ (grepped). **Corrected 2026-09-16 by
  plan-review round 1** (`docs/plan-reviews/obs-batch-2026-09-16-round1.md`):
  the switch-statement grep is the wrong check for the one OTHER
  `AuthStatus`-consuming screen, `confirm_email_screen.dart` — it uses an
  `if (authState.status == AuthStatus.error) {...} return
  _buildLoadingState(context);` chain, not a switch, so any status value
  that isn't `.error` (including a hypothetical `.info`) silently falls
  through to the loading state rather than hitting a compile-time-checked
  branch. Traced by hand: this is safe today because `confirmEmail`
  (the only method this screen calls) only ever sets `.error` or
  `.success`, never `.info` — `AuthStatus.info` is set at exactly one call
  site in the whole codebase, inside `signUpWithEmail`, which
  `confirm_email_screen.dart` never calls — but the risk shape is an
  if/else fallthrough, not an unhandled switch case, and the original
  wording here implied the latter.
---

# Signup confirmation toast rendered as a red error, not an informational message

## What was actually wrong

`AuthState2` had exactly one non-idle/loading/success bucket — `error` —
and `sign_in_screen.dart`'s `ref.listen` rendered every message reaching
that bucket through the same red `AppColors.bad` SnackBar. The signup
confirmation-pending message ("Check your email... for a confirmation
link, then sign in.") is a genuinely non-error, expected happy-path
next-step — signup succeeded, the user just has one more action — but had
no bucket to live in except `error`, so it inherited the same alarm-red
styling as a real sign-in failure.

The same batch's sync-banner fix (Observation 2) already established the
correct Wardroom precedent for this exact CLASS of message: an
informational/next-step notice renders in Campaign Gold
(`AppColors.accent`/`accentTint`), not red.

## The fix

1. Added `AuthStatus.info` to the enum.
2. `signUpWithEmail`'s confirmation-pending branch now sets `info` instead
   of `error`.
3. Extracted a pure `authToastStyleFor(AuthStatus)` function in
   `sign_in_screen.dart` returning `(background, text)` — gold/`bgDeep` for
   `info` (matching `confirm_email_screen.dart`'s own existing
   `AppColors.bgDeep`-on-`AppColors.accent` button precedent), red/white for
   everything else — and wired the `ref.listen` SnackBar renderer through
   it instead of the hardcoded `AppColors.bad`.

Deliberately left alone: the sibling "account already exists" message,
which still sets `AuthStatus.error`. That message represents a genuine
signup conflict requiring the user to change course (go sign in instead),
not a happy-path next step, so red remains the correct semantic — flagged
during investigation as a possible future consideration, not part of the
reported bug.

## Regression test

`test/contracts/auth_toast_info_status_test.dart`: behavioral coverage of
the extracted pure `authToastStyleFor` function (info → gold/not-red, error
→ unchanged red/white, every other status defensively falls back to error
styling), plus structural source-grep pins that (a) the confirmation-pending
write site uses `AuthStatus.info` while the "already exists" site is
unchanged at `AuthStatus.error`, and (b) `sign_in_screen.dart`'s renderer
goes through `authToastStyleFor` rather than a hardcoded `AppColors.bad`.
**Mutation-proven:** reverted `authToastStyleFor` to unconditionally return
red/white — exactly 1 of 7 assertions reddened (the exact regression), the
other 6 stayed green; restored the fix, 7/7 green again.
