---
bug_id: 918045
date: 2026-11-25
batch: oi348-landing3a (OI-348 walk, Landing 3a, B6)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk A1 (Chintamani, AAB 1.0.0+50, 2026-11-22 15:32 UTC): after tapping the sign-up confirmation link the screen showed "Confirming your account..." with a spinner for about 10 s, then moved on. Not endless, but nothing said the link had worked. Live client_errors for that confirm: auth_user_ensured 15:32:07.950, hive_session_reopen_noop 15:32:08.084 (openForUser done, +0.13 s), auth_signed_in 15:32:17.982 (method=email_confirm). So ~9.9 s went to the six migrators + hydrateFromCloud (cloud calls), after verifyOTP had returned. A web sample (another account, +49, 2026-11-13) took 2.6 s for the same span. Which cloud call is slow was not knowable: no step timing existed.
concept: confirm_email_verified_stage
sot_registry_entry: confirm_email_verified_stage
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "_performConfirmEmail: after verifyConfirmToken returns a user, state = loading + emailVerified (unless disable_confirm_verified_stage); then ensureLocalUserAfterConfirm", line: 978 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthState2.copyWith: emailVerified ?? false (NOT sticky, like errorMessage)", line: 142 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "confirmEmailErrorState: emailVerified && error is! StateError -> confirmedButSlowMessage", line: 899 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "_ensureLocalUser -> runTimed(_ensureLocalUserBody) -> one auth_ensure_timing event (outcome, total, laps)", line: 1231 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "hydrateFromCloud(user, {timings}): h_* laps per cloud step, incl. catch-head laps", line: 782 }
readers:
  - { file: lib/features/auth/screens/confirm_email_screen.dart, method_or_widget: "build -> _buildLoadingState(emailVerified:) -> 'Email confirmed. Setting up your account...' vs 'Confirming your account...'", line: 129 }
  - { file: lib/features/auth/screens/confirm_email_screen.dart, method_or_widget: "ref.listen: success -> /restoring (unchanged; keyed on status only)", line: 104 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "ref.listen / build: reads status + errorMessage only (verified unaffected)", line: 185 }
hive_key_prefix: "n/a (configBox disable_confirm_verified_stage is a kill switch, not data)"
hive_key_formula: "n/a"
sync_methods: [AuthSessionBootstrapper.hydrateFromCloud]
restore_methods: []
cloud_table: client_errors
cloud_columns: [op_type, error_message]
contract_test_path: test/contracts/confirm_email_verified_stage_behavioral_test.dart
ist_handling: ["none: no date key; the ceiling and the laps are relative durations"]
provider_invalidations: ["none: authNotifierProvider state only"]
telemetry_op_types:
  success: [auth_ensure_timing, auth_signed_in, auth_user_ensured]
  failure: [auth_confirm_email_timeout]
cross_account_guard: "Unchanged. openForUser + the cross-account clear-and-verify stay awaited inside the 40 s ceiling (diagnose a9c4e2's boundary). A guard StateError keeps its own message even after the link was verified (test g2)."
forbidden_patterns_checked:
  - { pattern: "a timeout or background run wrapping openForUser / the cross-account guard", absent: true }
  - { pattern: "emailVerified kept by copyWith (sticky)", absent: true }
  - { pattern: "'invalid or has expired' shown after a successful verify", absent: true }
  - { pattern: "a log call outside finally in runTimed", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-landing3a.md (2 review rounds, converged; founder 2026-11-25 "Show progress + measure").
  Rejected: "move on and load in the background". hydrateFromCloud and resolveDestination share _withLock(userId) (auth_session_bootstrapper.dart), and RestoringScreen calls resolveDestination, so the wait would only move to /restoring; a9c4e2 also forbids bounding the guard.
  1. AuthState2.emailVerified (non-sticky). _performConfirmEmail emits loading + emailVerified right after verifyOTP returns a user; status stays loading, so routing is unchanged. Kill switch configBox disable_confirm_verified_stage (test override confirmVerifiedStageDisabledForTest).
  2. ConfirmEmailScreen shows "Email confirmed. Setting up your account..." in that state; GO TO SIGN IN stays.
  3. A verified link that then times out or fails (not the cross-account StateError) shows "Email confirmed. Setting up your account is taking longer than usual. Tap GO TO SIGN IN to continue." The link is spent, and GO TO SIGN IN lands an authenticated user on onboarding/Home via _authRedirect.
  4. Measurement: StepTimings + runTimed (lib/core/utils/step_timings.dart). _ensureLocalUser runs its body through runTimed and sends ONE auth_ensure_timing event per call: "userId=<8> outcome=<ok|threw> total=<ms> <lap>=<ms> ...". Laps: verify / sign_in (the auth call), open, guard, migrators, terms, h_lock, h_users_upsert, h_users_active, h_users_name, h_terms_sync, h_profile_read, h_profile_merge, h_progress_read, h_terms_read, h_plan_gen, h_profile_branch, h_stub, h_tail, hydrate_failed, binds, and catch-head laps (h_users_failed, h_profile_failed, h_progress_failed, h_plan_gen_failed) so a throw does not hide its time in the next lap.
  Deviation from the plan text: runTimed is a top-level function in step_timings.dart (testable on its own), not a static on AuthNotifier.
  NOT in this batch: making the load faster. It needs the first auth_ensure_timing row from a phone (closure ledger B6-SPEEDUP upstream_blocked).
regression_test_planned: |
  test/contracts/confirm_email_verified_stage_behavioral_test.dart (8): the REAL confirmEmail with two seams (verifyConfirmToken, ensureLocalUserAfterConfirm held on a Completer): (a)(b) loading+verified while loading, success clears it; (c) kill switch ON -> no stage; (d) null user -> invalid; (e) fakeAsync, the REAL 40 s ceiling while verified -> confirmedButSlowMessage + auth_confirm_email_timeout telemetry; (f) same with the kill switch -> old timeout text; (g1) generic error while verified -> confirmed message; (g2) StateError -> cross-account message; (h) a second confirmEmail's first emit is not verified.
  test/contracts/confirm_email_error_mapping_test.dart (+5): the verified table.
  test/auth/confirm_email_screen_test.dart (+2): both loading texts, GO TO SIGN IN kept.
  test/core/step_timings_test.dart (3), test/contracts/auth_ensure_timing_runner_test.dart (4): exactly one line, ok/threw, rethrow, a throwing log masks nothing, line after the body.
  test/contracts/auth_ensure_timing_presence_test.dart (4, presence only, reason: _ensureLocalUser needs a live Supabase + Hive session): runTimed wiring, the auth_ensure_timing literal, lap order in both files.
  Repointed: test/contracts/auth_provider_error_surfacing_test.dart anchors on _ensureLocalUserBody, window 11000 -> 14000 (measured 10792 to the first recordNonFatal).
mutation_proof: |
  Rule 21. Scratchpad harness mut3a.sh: cp backup, node replace (refuses if the text is absent), run, cp back, cmp clean (all "restored").
  M1 stage emit removed -> 4 red. M2 kill-switch default flipped to ON -> 4 red. M3 copyWith sticky -> 5 red. M4 verified branch only for TimeoutException -> 3 red. M5 confirmed message swapped for "invalid or expired" -> 5 red. M6 runTimed log moved out of finally -> 3 red. M7 one hydrate lap removed -> 1 red (presence).
impact_analysis: |
  Confirm path: one extra loading->loading emit; routing and every other AuthState2 reader unchanged (sign_in_screen reads status + errorMessage). Sign-in path: only the timing (one more client_errors row per sign-in, LOW priority, droppable under a telemetry cooldown; 500-char cap keeps outcome and total first). A cross-account StateError signs out first, so that one outcome=threw row goes to the anon lane, which accepts only PRE_AUTH op types: that row is lost (accepted, stated). An ok row can land after the user saw the 40 s timeout (the ceiling raises in the caller; the load keeps running).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "auth_provider.dart, confirm_email_screen.dart, auth_session_bootstrapper.dart, step_timings.dart; 26 new tests + repointed pins green; flutter analyze lib/ no warnings." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "No Hive write added; the kill switch is a configBox read (fails to the fix ON)." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "None." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "client_errors read-only 2026-11-25: the A1 and web confirm spans above." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "log-client-error unchanged; auth_ensure_timing is an ordinary LOW op type." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "public.users row comes from trigger on_auth_user_created (live), so nothing waits on the client upsert." }
recurrence: "Not a recurrence. Same span as a9c4e2 (sign-in with no ceiling) and 42a98d (confirm before Supabase init); both fixes kept: the 40 s ceiling and ensureSupabaseReady before the OI-205 guard."
related_bugs: [a9c4e2, 42a98d]
---

# 918045 - confirm-email-no-progress

## What happened
A confirm link is checked in well under a second; the ~10 s that followed was the account load. The screen showed the same "Confirming your account..." text the whole time, so a working link looked stuck.

## The fix
Once the link is accepted the screen says "Email confirmed. Setting up your account...". A failure after that point no longer calls the spent link invalid. Every sign-in and confirm now reports one `auth_ensure_timing` line naming how long each step took.

## Residual, stated
- The load itself is not faster yet: the next phone sign-up names the slow step (ledger B6-SPEEDUP).
- The `outcome=threw` row of a cross-account guard failure is lost (anon lane).
