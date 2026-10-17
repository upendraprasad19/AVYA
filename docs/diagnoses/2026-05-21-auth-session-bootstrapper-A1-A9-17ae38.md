---
bug_id: 17ae38
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 — B2 architecture (A1 + A9)
status: shipped
symptom: |
  Two coupled architecture-debt findings on the post-sign-in path.

  A1 (score 24): `lib/features/auth/providers/auth_provider.dart` was
  a god-provider. Its `_ensureLocalUser` method did Postgres CRUD on
  three cloud tables (`users`, `user_profile`, `user_progress`) and
  pushed the OneSignal player_id, all inline. 11 direct
  `_supabase.client.from(...)` call sites at lines 480, 488, 519, 530,
  573, 611, 634, 716, 724, 789, 827. The Riverpod notifier owned
  business logic that should live in a dedicated service.

  A9 (score 30): `lib/features/auth/screens/restoring_screen.dart`
  ran `Supabase.instance.client.from('user_profile').select(...)`
  directly from a Flutter widget at lines 50, 59, 228. CLAUDE.md
  §4.4 rule #4 violation (no direct Supabase calls from widgets) and
  duplicated the same SELECT that `auth_provider.dart:573` issued —
  two readers, divergent shapes, drift waiting to happen.
concept: post_signin_destination
sot_registry_entry: onboarding_completed_at
writers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: AuthSessionBootstrapper.hydrateFromCloud, line: 154 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: AuthSessionBootstrapper.pushOneSignalPlayerId, line: 449 }
  - { file: lib/features/auth/providers/auth_provider.dart, method: AuthNotifier._ensureLocalUser orchestrator delegates to bootstrapper, line: 359 }
readers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: AuthSessionBootstrapper.resolveDestination, line: 105 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method: AuthSessionBootstrapper.classifyDestination (pure helper), line: 134 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method: RestoringScreen._kickoffRestore (switch on PostSignInDestination), line: 50 }
hive_key_prefix: "userBox['profile']"
hive_key_formula: "userBox['profile'] map merged from cloud user_profile row, post-sign-in only"
sync_methods: [syncProfileNow]
restore_methods: [hydrateFromCloud]
cloud_table: user_profile
cloud_columns: [user_id, onboarding_completed_at, full_name, primary_goal, current_weight_kg, fitness_experience, height_cm, equipment_access, days_per_week]
contract_test_path: test/contracts/auth_session_bootstrapper_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 12, fn: istNow used by ProfileWriteService for updated_at stamp }
provider_invalidations: [authNotifierProvider, currentUserProvider]
telemetry_op_types:
  success: [auth_user_ensured, auth_signed_in, auth_signed_up]
  failure:
    - auth_session_bootstrapper_resolve_destination
    - auth_session_bootstrapper_restore_query_failed
    - auth_session_bootstrapper_push_onesignal_player_id
    - users_unique_violation_23505
    - users_fk_violation_23503
    - users_upsert_failed
cross_account_guard: |
  auth_provider._ensureLocalUser keeps the cross-account guard
  (profile.id mismatch → clearAllData + verify-after-clear) at the
  orchestration layer. AuthSessionBootstrapper operates only after
  the guard has run, so it never sees a poisoned Hive map. The
  bootstrapper holds a per-userId mutex so concurrent calls for the
  same user serialise; calls for different users are independent.
forbidden_patterns_checked:
  - { pattern: "Supabase.instance.client inside restoring_screen.dart", absent: true }
  - { pattern: ".from('users') inside _ensureLocalUser body", absent: true }
  - { pattern: ".from('user_profile') inside _ensureLocalUser body", absent: true }
  - { pattern: ".from('user_progress') inside _ensureLocalUser body", absent: true }
  - { pattern: "userBox.put('profile' inside auth_session_bootstrapper.dart", absent: true }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "AuthSessionBootstrapper extracted at lib/core/services/auth_session_bootstrapper.dart (533 lines, instance singleton + per-userId mutex). auth_provider.dart shrunk from 843 → 550 lines. restoring_screen.dart no longer imports supabase_flutter." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Profile writes still route through ProfileWriteService (audit A4 contract preserved). Source-grep test asserts userBox.put('profile' is absent from bootstrapper." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No schema change; same three tables (users / user_profile / user_progress) read by the new service." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Pure refactor — no data migration." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron scheduling affected." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "auth.uid() = user_id RLS still gates user_profile / users / user_progress reads. Bootstrapper SELECTs scoped by .eq('user_id', user.id) preserving the policy contract." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage objects touched." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No new secrets introduced." }
  - { tier: 11, name: ist_correctness, status: verified, evidence: "ProfileWriteService stamps updated_at via istNow(). No new IST-sensitive code paths." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "Gate 36 (check_widget_no_direct_supabase) cleared restoring_screen.dart from the WARN list. All UI-layer Supabase calls in this file removed; remaining gate warning is apply_referral_sheet.dart (audit A5 scope)." }
impact_analysis:
  callers_audited:
    - lib/features/auth/providers/auth_provider.dart (AuthNotifier — owns _ensureLocalUser)
    - lib/features/auth/screens/restoring_screen.dart (RestoringScreen — _kickoffRestore + _resolveOnboardingResumeRoute)
  callers_updated_in_this_batch:
    - lib/features/auth/providers/auth_provider.dart (now delegates 293 lines of cloud hydration to bootstrapper; keeps cross-account guard + Crashlytics + OneSignal.login at orchestration layer)
    - lib/features/auth/screens/restoring_screen.dart (switch on PostSignInDestination sealed class; _resolveOnboardingResumeRoute removed — superseded by bootstrapper.resolveDestination)
  callers_unchanged:
    - lib/features/onboarding/providers/onboarding_provider.dart (stamps onboarding_completed_at — orthogonal writer)
    - lib/shared/repositories/user_repository.dart (setOnboardingCompleted — orthogonal writer)
    - lib/features/profile/services/profile_write_service.dart (Hive profile writer chokepoint — still canonical, called by bootstrapper)
proposed_fix: |
  Two-layer extract.

  1. New service `lib/core/services/auth_session_bootstrapper.dart`
     (533 lines). Mirrors `HealthWriteService` / `WorkoutWriteService`
     convention: private constructor + `static AuthSessionBootstrapper
     instance`, per-userId Completer mutex, all Supabase calls routed
     through `SupabaseService.instance.client`, all errors routed
     through `ErrorTelemetry.recordNonFatal` (audit A11 pattern).
     Public API:
       - `Future<PostSignInDestination> resolveDestination(String userId)`
         — was `restoring_screen.dart:50,59,228` SELECT.
       - `Future<void> hydrateFromCloud(User user)` — was
         `auth_provider._ensureLocalUser` lines 477-803.
       - `Future<void> pushOneSignalPlayerId(String userId, String playerId)`
         + `syncCurrentOneSignalPlayerId(userId)` — was
         `auth_provider._syncOneSignalPlayerId`.
       - `@visibleForTesting static PostSignInDestination
         classifyDestination(Map?)` — pure decision helper, tested
         exhaustively in `auth_session_bootstrapper_test.dart`.

  2. `PostSignInDestination` sealed class with three subtypes:
     `GoHome`, `ResumeOnboarding(firstMissingStep)`,
     `StartMissionBrief`. The sealed modifier forces
     `restoring_screen._kickoffRestore`'s switch to handle every
     branch — Dart's exhaustiveness checker catches future drift.

  3. `auth_provider.dart` thinned out (843 → 550 lines). Riverpod
     notifier surface preserved: `signInWithEmail`, `signUpWithEmail`,
     `signInWithGoogle`, `signInWithPhone`, `verifyOtp`, `signOut`,
     `resetState`, `resetPhoneFlow` — all signatures unchanged.
     `_ensureLocalUser` keeps the cross-account guard,
     `UserConfigMigrator` / `StreakFreezeClampMigrator` /
     `InductionService.backfillMusterToProfileIfNeeded` /
     `LoggingTypeRepairMigrator` invocations, Crashlytics user
     identifier, and `OneSignal.login(user.id)` — but delegates the
     cloud-CRUD block to `AuthSessionBootstrapper.hydrateFromCloud`
     wrapped in a try/catch that preserves the 23505/23503 detection
     for `ErrorTelemetry.recordNonFatal` (so
     `auth_provider_error_surfacing_test.dart` keeps passing).

  4. `restoring_screen.dart` rewritten: imports
     `AuthSessionBootstrapper` and `SupabaseService` (drops
     `supabase_flutter` import entirely). `_kickoffRestore` switches
     on the sealed `PostSignInDestination`; the Plan A self-heal
     branch (populated Hive + cloud NULL) is preserved inside the
     `ResumeOnboarding` case. UI/animation behavior unchanged
     (15-second timeout CTA, Pulsing seal, animated dots, restore
     progress label).

  5. SoT registry (`docs/sot_registry.yaml`) updated: bootstrapper
     added to writers + readers of `onboarding_completed_at` concept,
     and to `user_full_name` reader_allow_files (since it reads the
     profile map for cloud-vs-Hive precedence, not full_name
     specifically). Stale line ranges (`400-715`) corrected to
     post-refactor ranges. Reader manifest gate
     (`check_reader_manifest_complete`) green.

  6. New contract test
     `test/contracts/auth_session_bootstrapper_test.dart` (17 tests):
       - 7 behavioral pins on `classifyDestination` covering every
         branch of the decision tree.
       - 2 structural pins (singleton identity, sealed hierarchy).
       - 4 source-grep contracts on the service (no
         `Supabase.instance.client`, telemetry routing,
         ProfileWriteService routing, mutex shape).
       - 2 source-grep contracts on `restoring_screen.dart`
         (no `supabase_flutter` import, calls
         `AuthSessionBootstrapper.instance.resolveDestination`).
       - 2 source-grep contracts on `auth_provider.dart`
         (delegates to `hydrateFromCloud`, no Postgres CRUD inside
         `_ensureLocalUser` body).

  All source-grep helpers strip block + line comments first per
  `feedback_source_grep_strip_comments_first.md`.
regression_test_planned:
  - test/contracts/auth_session_bootstrapper_test.dart (17 tests, all green).
  - test/contracts/auth_provider_error_surfacing_test.dart (existing, still green — 23505/23503 detection preserved at orchestrator layer).
---

# Bug 17ae38 — Auth god-provider extract (A1) + widget-layer Supabase removal (A9)

closes-audit-findings: A1, A9 (tech-debt audit 2026-05-20)

## What landed

Two coupled architecture findings closed as one batch (A9 needs A1's
bootstrapper to exist).

- **A1**: `auth_provider.dart` is no longer a god-provider. 293 lines
  of cloud CRUD moved to `AuthSessionBootstrapper`. The Riverpod
  notifier kept its public surface verbatim — `signIn*`, `signOut`,
  `verifyOtp` callers are unaffected.
- **A9**: `restoring_screen.dart` no longer imports
  `package:supabase_flutter/supabase_flutter.dart`. Its 3 direct
  `.from('user_profile').select()` calls (lines 50/59/228 pre-fix)
  are now a single call to
  `AuthSessionBootstrapper.instance.resolveDestination(userId)`
  returning a sealed `PostSignInDestination`.

## Why couple A1 and A9

A9's fix _is_ A1's bootstrapper. There is no clean way to remove the
widget's Supabase call without somewhere else owning the
`user_profile` SELECT + the decision tree. Doing them separately
would either leave A9 open or create a one-shot helper that A1 would
immediately delete. Same architectural batch.

## Riverpod surface — preserved

The notifier API consumed by `sign_in_screen.dart`,
`sign_up_screen.dart`, `phone_auth_screen.dart`, `splash_screen.dart`
and `auth_invalidation_provider.dart` is unchanged:

```
class AuthNotifier extends Notifier<AuthState2> {
  Future<void> signInWithEmail(String email, String password);
  Future<void> signUpWithEmail(String email, String password);
  Future<void> signInWithGoogle();
  Future<void> signInWithPhone(String phone);
  Future<void> verifyOtp(String phone, String otp);
  Future<void> signOut();
  void resetState();
  void resetPhoneFlow();
}
```

No widget needs to change. The bootstrapper is an implementation
detail of `_ensureLocalUser`.

## Cross-account guard — still at orchestrator

`_ensureLocalUser` keeps the cross-account safety net (profile-id
mismatch → `UserRepository.clearAllData` → verify-after-clear → force
sign-out on partial-fail). The bootstrapper runs only after the guard
has cleared. If the guard fires `StateError`, signUp/signIn surface
the message and the user is signed out before any cloud CRUD attempt.

## Why `classifyDestination` is pure-and-public

Behaviorally testing `resolveDestination` would require mocking the
Supabase SDK — infrastructure the project doesn't have. The decision
logic (5 nested null-checks in onboarding order) is the only piece
worth pinning anyway; the I/O wrapper is a thin try/catch. Splitting
the pure helper out lets `auth_session_bootstrapper_test.dart` cover
every branch with no Hive, no Supabase, no async — 7 tests run in <100ms.

## Sealed class — exhaustiveness checker as a regression net

`PostSignInDestination` is `sealed`. If anyone adds a fourth
destination later, Dart 3's switch-exhaustiveness checker flags
`restoring_screen._kickoffRestore` at compile time. That's a
structural guarantee the source-grep contract tests can't provide.

## Gate output

- `dart run scripts/check_widget_no_direct_supabase.dart` →
  `restoring_screen.dart` removed from the violation list; only
  `apply_referral_sheet.dart:61` remains (A5 scope, out of this batch).
- `dart run scripts/check_reader_manifest_complete.dart` → OK (after
  bootstrapper added to `onboarding_completed_at` writers/readers and
  `user_full_name` `reader_allow_files`).
- `flutter analyze --fatal-infos` on the three touched files → no
  issues.
- `flutter test test/contracts/auth_session_bootstrapper_test.dart` →
  17/17 pass.
- `flutter test test/contracts/auth_provider_error_surfacing_test.dart` →
  1/1 pass (existing test, source-grep on `_ensureLocalUser` still
  finds `ErrorTelemetry.recordNonFatal` + `23505`/`23503` because the
  outer wrapper preserves the detection).
