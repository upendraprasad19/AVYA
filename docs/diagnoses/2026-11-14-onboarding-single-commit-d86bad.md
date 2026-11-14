---
bug_id: d86bad
date: 2026-11-14
batch: onboarding-fuse-commit
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Founder (2026-11-14): onboarding asks the user to commit twice (Plan "REPORT FOR DUTY", then the Induction screen's
  "I COMMIT.") and shows one more selection (the Muster physique-focus question) after the data commit, with a long
  coach speech in between. Fusing the two commits surfaced three latent defects in the commit path, all fixed here:
  (1) the profile completeOnboarding saves has no `id`, so InductionService's coach-memory sync (keyed on
  profile['id']) was silently skipped for every new user; (2) the same missing `id` makes AuthNotifier._ensureLocalUser
  treat a freshly onboarded profile as another account's (`existingId == null` -> needsClear) if it runs before the
  bootstrapper stamps the id; (3) opening the Hive session inside completeOnboarding re-emits authUserIdTokenProvider
  and rebuilds OnboardingNotifier with EMPTY answers, so resolveStartDate (read after the open) lost the user's start
  choice.
concept: onboarding_single_commit
sot_registry_entry: muster_to_profile_bridge
contract_test_path: test/contracts/onboarding_single_commit_test.dart
related_bugs: [e2b8a4, d6f1b8, c2e9f4, b3f9e7, 7ad0c6, c4055a]
recurrence: |
  Not a recurrence of a fixed bug. e2b8a4 / d6f1b8 (2026-09-19) moved Muster before Induction and narrowed the bridge;
  this batch retires both screens. c2e9f4 added the cloud overwrite guard and b3f9e7 the in-method session open that
  this batch hoists. 7ad0c6 and c4055a are the cross-account guard and the auth-token rebuild contract whose
  interaction with a profile lacking `id` (defect 2) and with an in-method session open (defect 3) is fixed here.
  Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses grep for "profile.id", "existingId == null", "profile id
  mismatch", "answers" + "rebuild", "muster", "induction"; every hit read.
writers:
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "finalizeLocalCommit (stamps, then setOnboarded)", line: 371 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "completeOnboarding: answers captured before the hoisted session open", line: 423 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "completeOnboarding profile map: 'id' (session owner)", line: 529 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "completeOnboarding profile map: 'physique_focus' 'balanced'", line: 543 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "completeOnboarding calls finalizeLocalCommit after saveProgress", line: 661 }
  - { file: lib/features/ai_coach/services/induction_service.dart, method_or_widget: "_syncUid (session owner, then profile id)", line: 72 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "_ensureLocalUser -> shouldClearForProfileId", line: 1168 }
  - { file: lib/core/router/app_router.dart, method_or_widget: "postSessionRedirect (isOnboarded)", line: 818 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: "committed_to_lt_cdr", line: 583 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "resolveStartDate(a)", line: 629 }
hive_key_prefix: "coachBox committed_at / committed_to_lt_cdr / induction_completed_at; userBox profile (id, physique_focus); userBox onboarding_completed (MigratedKey)"
hive_key_formula: "coachBox.put('committed_at', now) etc.; userBox.put('profile', map) via ProfileWriteService.updateProfile"
sync_methods:
  - syncCoachMemoryNow
  - pushSnapshot
  - syncProfileNow (unchanged)
restore_methods:
  - "SyncService coach_memory restore (sync_coach.dart) restores the induction keys for returning users (unchanged)"
cloud_table: coach_memory
cloud_columns:
  - committed_at
  - committed_to_lt_cdr
  - induction_completed_at
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no IST date key or counter reset is touched; the commitment stamps keep their existing ISO timestamps", line: 1 }
provider_invalidations:
  - "none new: the plan screen navigates to /home; Home providers read the committed profile as before"
telemetry_op_types:
  success: [onboarding_step, onboarding_commit]
  failure: [induction_sync_skipped_no_uid, onboarding_session_open_failed]
cross_account_guard: "true: profile id written equals the session owner (HiveUserSession.currentOwnerFullId), the benign case for hive_user_session.dart:257, subscription_service.dart and _ensureLocalUser; it closes the null-id clear."
forbidden_patterns_checked:
  - { pattern: "setOnboarded before the commitment stamps", absent: true }
  - { pattern: "recordCommitment without a hasCommitted check on the commit path", absent: true }
  - { pattern: "state.answers read in completeOnboarding after the session open", absent: true }
  - { pattern: "a widget calling InductionService or HiveUserSession for the commit", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-14-onboarding-fuse-commit.md (five review rounds). completeOnboarding ends with
  finalizeLocalCommit (recordCommitment when !hasCommitted, completeInduction when !inductionCompleted, then
  setOnboarded); the session open is hoisted above the cloud guard and wrapped in try/catch, with state.answers captured
  before it; the profile map carries id (session owner) and physique_focus 'balanced'; InductionService syncs with the
  session owner's uid; AuthNotifier.shouldClearForProfileId extracted (behaviour unchanged); resolveStartDate takes the
  captured answers. Muster and Induction screens deleted; /coach/muster and /coach/induction redirect to /home; Plan
  screen shows a pledge card and one "I COMMIT ->" button.
regression_test_planned: |
  test/contracts/onboarding_single_commit_test.dart (new);
  test/contracts/onboarding_hive_session_open_before_write_test.dart C1 (extended: id, physique_focus, no early stamp,
  onboarded flag false after a failed commit).
impact_analysis: |
  Platform tier (onboarding commit, router, auth helper). New users: one fewer screen and one fewer commit; the
  commitment now reaches the cloud at commit time. Existing accounts: unchanged (nothing forces induction; the app is
  not live, CLAUDE.md section 1).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "onboarding_provider.dart, induction_service.dart, auth_provider.dart, plan_screen.dart, app_router.dart, wardroom_copy.dart, rank_service.dart; flutter analyze --no-fatal-infos clean (0 issues)" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "onboarding_single_commit_test: coachBox stamps + onboarding_completed order; C1: saved profile id == session owner, physique_focus balanced, no early stamp" }
  - { layer: postgres_schema, status: verified, evidence: "user_profile.physique_focus is text (migration 017); coach_memory.user_id FK to public.users (027) satisfied by the on_auth_user_created trigger (039:42-55)" }
  - { layer: postgres_data, status: not_applicable, evidence: "no data change; testers only (CLAUDE.md section 1)" }
  - { layer: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { layer: edge_function_deploy, status: not_applicable, evidence: "no Edge Function change; log-client-error accepts LOW-priority op types from authenticated callers without an allow-list" }
  - { layer: cron_jobs, status: not_applicable, evidence: "none touched" }
  - { layer: rls_policies, status: not_applicable, evidence: "coach_memory upsert path unchanged" }
  - { layer: storage, status: not_applicable, evidence: "none touched" }
  - { layer: secrets, status: not_applicable, evidence: "none touched" }
  - { layer: external_services, status: not_applicable, evidence: "none touched" }
  - { layer: client_server_contract, status: verified, evidence: "onboarding cloud payload built by explicit key (no id); physique_focus read from the same map; coach_memory upsert writes only the columns present" }
---

## Root cause

- **Silent sync skip (defect 1).** `InductionService.recordCommitment` / `completeInduction` read
  `userBox['profile']['id']` for the sync uid. `completeOnboarding` builds the profile map without `id` and
  `ProfileWriteService.updateProfile` writes it verbatim, so until `AuthSessionBootstrapper` stamped `merged['id']`
  later, the id was null and the sync was skipped with no log. The old Induction screen ran minutes later, which hid it.
- **Null-id clear (defect 2).** `_ensureLocalUser` (`auth_provider.dart`) clears when `existingId == null`. A sign-in
  between the commit and the bootstrapper's stamp would clear a freshly onboarded profile.
- **Rebuilt answers (defect 3).** `OnboardingNotifier.build()` watches `authUserIdTokenProvider`, which re-emits on the
  Hive session owner edge. `HiveUserSession.ensureOpenedForCurrentSession()` inside `completeOnboarding` therefore
  rebuilt the notifier and emptied `state.answers`. The profile map survived only because `a` was read first;
  `resolveStartDate()` read `state.answers` after the open.

## Mutation proof (rule 21)

Each mutant applied with a count check, the targeted files run, then restored and compared (scratchpad scripts):

| Mutant | Tests red |
|---|---|
| M1 `setOnboarded` before the stamps | 2 (`ORDER` test, retry test) |
| M2 drop the `!hasCommitted` check | 1 (retry keeps `committed_at`) |
| M3 drop `physique_focus` from the profile map | 1 (C1) |
| M4 sync uid only from `profile['id']` | 1 (sync uid test) |
| M5 read `state.answers` after the session open (compiling form) | 1 (C1: saved `full_name` empty) |
| M6 `resolveStartDate` ignores the passed answers | 1 (`resolveStartDate` test) |

M5's first attempt did not compile and was re-run in a compiling form; a compile error was not counted as a proof.
