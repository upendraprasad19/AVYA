---
bug_id: e2a4f7
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Surfaced during live web E2E (amar@gmail.com). Browser console at sign-in:
  "[AuthSessionBootstrapper.resolveDestination] PostgrestException(code 42703:
  column user_profile.full_name does not exist)". resolveDestination always
  throws and silently falls back to StartMissionBrief for EVERY user. Masked
  for existing installs by the router's local-flag redirect, but a returning,
  cloud-onboarded user on a fresh install / new device / post-data-clear is
  forced to redo onboarding (cloud restore is cancelled in the StartMissionBrief
  branch). The ResumeOnboarding self-heal branch became dead code.
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at
blast_radius: account
writers:
  - { file: lib/core/services/sync/sync_profile.dart, method: _syncUserProfile, line: 84 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: hydrateFromCloud, line: 196 }
readers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: resolveDestination, line: 115 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: classifyDestination, line: 152 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method: _kickoffRestore, line: 88 }
hive_key_prefix: "userBox['profile'] map"
hive_key_formula: "userBox['profile']['date_of_birth'] mirrors user_profile.date_of_birth; full_name mirrors users.full_name (different table)"
sync_methods: [syncProfileNow]
restore_methods: [restoreFromCloudForUser]
cloud_table: user_profile
cloud_columns: [user_id, onboarding_completed_at, date_of_birth, primary_goal, current_weight_kg, fitness_experience]
contract_test_path: test/contracts/auth_session_bootstrapper_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [auth_session_bootstrapper_resolve_destination]
cross_account_guard: >
  Unchanged. Routing decision feeds restoring_screen which calls
  _ensureOwnershipBeforeHome (HiveUserSession.openForUser) before /home.
forbidden_patterns_checked:
  - { pattern: "select('user_id, onboarding_completed_at, full_name", absent: true }
  - { pattern: "row['full_name'] inside classifyDestination", absent: true }
proposed_fix: >
  resolveDestination selected `full_name` from `user_profile`, but that column
  lives on the `users` table (live information_schema 2026-05-30 confirms
  user_profile has NO full_name; users has it). The SELECT 42703'd on every
  call; the catch returned StartMissionBrief unconditionally. Fix: select
  `date_of_birth` (a real user_profile column written by the onboarding identity
  screen via sync_profile.dart:84) instead of full_name, and key the
  classifyDestination identity-step check off row['date_of_birth'] instead of
  row['full_name']. date_of_birth is the correct identity-step sentinel: the
  identity screen collects {full_name -> users, date_of_birth + gender ->
  user_profile}.
regression_test_planned:
  - test/contracts/auth_session_bootstrapper_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "auth_session_bootstrapper.dart SELECT + classifyDestination now use date_of_birth; verified failing-then-passing via auth_session_bootstrapper_test.dart" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "information_schema 2026-05-30: user_profile columns include date_of_birth/gender/onboarding_completed_at/primary_goal/current_weight_kg/fitness_experience and NOT full_name; users has full_name + onboarding_completed" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "amar@gmail.com onboarding write confirmed date_of_birth populated on user_profile via sync_profile.dart:84 (_hasValue guard)" }
  - { tier: 12, layer: end_to_end_contract, status: fixed_in_this_batch, evidence: "live web E2E reproduced the 42703; classify behavioral tests + source-grep absent/present guards pin the contract" }
impact_analysis: >
  Regression since commit ec01b469 (2026-05-21, audit-2026-05-20 A1/A9 extract
  that moved the inline restoring_screen query into resolveDestination with the
  wrong column). For ~9 days resolveDestination returned StartMissionBrief for
  every user. Masked for existing installs because GoRouter._authRedirect
  independently reads the LOCAL Hive onboarding_completed flag and bounces
  onboarded users off /onboarding to /home. The bug bites a returning,
  cloud-onboarded user whose local flag is false/absent (fresh install, new
  device, post-data-clear, post-cross-account-clear): StartMissionBrief cancels
  the cloud restore (restoring_screen.dart:94) and routes to mission-brief, so
  they re-onboard from scratch and their cloud data is not pulled. No data loss
  on the server; the harm is a forced re-onboarding + cancelled restore for that
  cohort. The ResumeOnboarding self-heal (Plan A re-stamp) was unreachable.
  Same wrong-table mistake class as diagnose 9e1d4c (proactive-coach-promotion
  user_profile.full_name). Account-tier: per-user auth/onboarding routing.
---

# e2a4f7 — resolveDestination queried non-existent user_profile.full_name

## What happened
`AuthSessionBootstrapper.resolveDestination` (the post-sign-in routing arbiter)
ran a `user_profile` SELECT that included `full_name`. That column does not
exist on `user_profile` — it lives on `users`. PostgREST returned **42703
(undefined_column)**; the method's catch swallowed it and returned the
conservative `StartMissionBrief()` fallback for **every** user, on every call.
`classifyDestination` (which also keyed the identity step off `full_name`) was
never reached.

## Why it was masked
`GoRouter._authRedirect` (`app_router.dart:566–575`) is a second, independent
routing authority that reads the **local Hive** `onboarding_completed` flag and
bounces onboarded users off `/onboarding` → `/home`. Any existing install
(founder's device included) has that flag set, so the misroute was invisible.

## Who it bites
A returning, cloud-onboarded user whose **local** flag is false/absent (fresh
install / new device / post-data-clear). `StartMissionBrief` cancels the cloud
restore (`restoring_screen.dart:94`) and routes to mission-brief; the router
sees the local flag false and lets them sit on onboarding → forced re-onboard,
cloud data never pulled.

## Root cause
Writer/reader table drift introduced by the 2026-05-21 A1/A9 extract
(`ec01b469`): the reader was given a column that lives on a different table.
The existing test pinned the *pure* `classifyDestination` with a mock row
containing `full_name`, so it stayed green while the real SELECT was broken —
the source-grep / pure-unit false-confidence class.

## Fix
SELECT `date_of_birth` instead of `full_name`; classify the identity step off
`row['date_of_birth']`. `date_of_birth` is a real `user_profile` column the
identity screen populates (sync mapping at `sync_profile.dart:84`). Tests
updated to the real column + new source-grep guards asserting `full_name` is
absent and `date_of_birth` present in resolveDestination.

## Verification
Live `information_schema` (2026-05-30): `user_profile` has `date_of_birth`,
`gender`, `onboarding_completed_at`, `primary_goal`, `current_weight_kg`,
`fitness_experience` — and NO `full_name`; `users` has `full_name`. Regression
test fails on `main` (3 classify + 2 source-grep failures) and passes with the
fix.
