---
bug_id: 7a3e1c
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 — A7 singleton cross-account leak scaffold
status: shipped
symptom: |
  Audit finding A7 (score 14): seven `static .instance` core services
  live OUTSIDE the Riverpod graph and hold mutable in-memory state that
  survives HiveUserSession user swaps:

    - lib/core/services/sync_service.dart:82            (SyncService)
    - lib/core/services/subscription_service.dart:17    (SubscriptionService)
    - lib/core/services/workout_schedule_service.dart:177 (WorkoutScheduleService)
    - lib/core/services/usage_counter_service.dart:13   (UsageCounterService)
    - lib/core/services/ai_service.dart:54              (AiService)
    - lib/core/services/razorpay_service.dart:26        (RazorpayService)
    - lib/core/services/seed_service.dart:36            (SeedService)

  Each one is imported by Riverpod providers but the singleton itself
  is not Riverpod-managed. Invalidating a provider does not reset the
  singleton; its caches (HTTP client, completer, stream subscription,
  in-flight payment callbacks, restore-progress label) outlive a sign-
  out → sign-in flow and can leak the previous user's state into the
  new session.

  A full Riverpod conversion of seven singletons would touch hundreds
  of call sites and is a multi-day refactor. This batch ships the
  narrow scaffold: a process-wide lifecycle registry that bridges
  static-singleton land into HiveUserSession's user-swap signal.
concept: singleton_lifecycle_registry
sot_registry_entry: singleton_lifecycle_registry
writers:
  - { file: lib/core/services/sync_service.dart, method: "SyncService._() → _registerLifecycle()", line: 82 }
  - { file: lib/core/services/subscription_service.dart, method: "SubscriptionService._() → _registerLifecycle()", line: 17 }
  - { file: lib/core/services/workout_schedule_service.dart, method: "WorkoutScheduleService._() → _registerLifecycle()", line: 177 }
  - { file: lib/core/services/usage_counter_service.dart, method: "UsageCounterService._() → _registerLifecycle()", line: 13 }
  - { file: lib/core/services/ai_service.dart, method: "AiService._() → _registerLifecycle()", line: 54 }
  - { file: lib/core/services/razorpay_service.dart, method: "RazorpayService._() → _registerLifecycle()", line: 26 }
  - { file: lib/core/services/seed_service.dart, method: "SeedService._() → _registerLifecycle()", line: 36 }
readers:
  - { file: lib/core/services/hive_user_session.dart, method: "_openForUserLocked → SingletonLifecycleRegistry.notifyUserChanged()", line: 255 }
  - { file: lib/core/services/hive_user_session.dart, method: "_closeAllLocked → SingletonLifecycleRegistry.notifyUserChanged()", line: 387 }
  - { file: lib/core/services/hive_user_session.dart, method: "_deleteAllFilesForCurrentUserLocked → SingletonLifecycleRegistry.notifyUserChanged()", line: 424 }
hive_key_prefix: "in_memory_only"
hive_key_formula: |
  Not Hive-backed. SingletonLifecycleRegistry holds a process-local
  Map<String, void Function()>; the seven singletons re-register from
  their private constructors on every cold start.
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/singleton_lifecycle_registry_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 12, fn: "no IST surface — registry is timeless" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - singleton_lifecycle_callback
cross_account_guard: |
  This finding IS a cross-account-leak class. The lifecycle registry
  IS the guard for in-memory singleton state. Existing on-disk guards
  (HiveUserSession namespacing + the profile.id mismatch sweep) are
  unaffected — they still gate Hive storage. The registry covers what
  the existing guards do not: caches that never touch disk.

  HiveUserSession.notifyUserChanged() runs AFTER the static owner
  fields + currentOwnerListenable have flipped to the new user, so
  callback bodies that re-read namespaced Hive boxes see the new
  owner's data. Verified by reading _openForUserLocked (the flip at
  lines 178-182 precedes the notify at line 255).
forbidden_patterns_checked:
  - { pattern: "SingletonLifecycleRegistry.register in any file outside lib/core/services/", absent: true }
  - { pattern: "SingletonLifecycleRegistry.notifyUserChanged in any file outside hive_user_session.dart + the test", absent: true }
  - { pattern: "register('SyncService' more than once", absent: true }
proposed_fix: |
  1. Created lib/core/services/singleton_lifecycle_registry.dart with
     a static `register(name, hook)` + `notifyUserChanged()` API.
     Caught exceptions inside `notifyUserChanged()` are reported via
     `ErrorTelemetry.recordNonFatal` (reason
     `singleton_lifecycle_callback`) and never rethrown — H-42 contract.
  2. Each of the seven singletons calls `_registerLifecycle()` from
     its private constructor, registering a `_onUserChanged` reset
     hook. Public API of every singleton is unchanged; no callers
     moved.
  3. `lib/core/services/hive_user_session.dart` now invokes
     `SingletonLifecycleRegistry.notifyUserChanged()` at the tail of
     each of the three locked mutator paths
     (`_openForUserLocked`, `_closeAllLocked`,
     `_deleteAllFilesForCurrentUserLocked`) AFTER the static owner
     fields + listenable have flipped.
  4. Per-singleton reset behavior:
     - SyncService: cancels `_realtimeSubscription`, drops
       `_healthSyncCompleter` (completing any pending waiter), resets
       `restoreProgressLabel` to the cold-start default, clears
       `_restoreCancelled`.
     - SubscriptionService: re-fires static `onStateChanged` so
       Riverpod consumers re-read PRO state from the now-flipped
       namespaced userBox.
     - AiService: closes + drops cached `_httpClient` via existing
       `dispose()` method.
     - RazorpayService: nulls `_onSuccess`, `_onFailure`,
       `_pendingPlan` so an abandoned checkout cannot dispatch into
       the next user's UI closure.
     - WorkoutScheduleService / UsageCounterService / SeedService:
       no-op reset (state already lives in Hive or is shared); hook
       reserved for future caches.
  5. SoT registry updated with concept `singleton_lifecycle_registry`
     listing the 7 writers + 3 readers + class_constraints.
  6. Behavioral test `test/contracts/singleton_lifecycle_registry_test.dart`
     pins register/notify mechanics, exception isolation (H-42),
     idempotent re-register, and source-greps each wired singleton +
     all three notify call sites in HiveUserSession.
regression_test_planned: |
  test/contracts/singleton_lifecycle_registry_test.dart — 14 tests:
   - register() + notifyUserChanged() invokes the callback
   - multiple registers all fire on a single notify (insertion order)
   - notifyUserChanged is repeatable
   - throwing callback does not stop the others (H-42 contract)
   - re-register with same name replaces previous callback
   - registeredNames() reflects every active callback
   - 7 source-grep contracts (one per wired singleton)
   - 1 source-grep contract on HiveUserSession (3 notify call sites)
  Status: 14/14 passing locally.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "New file lib/core/services/singleton_lifecycle_registry.dart (~110 lines). 7 singletons gained _registerLifecycle + _onUserChanged (4 active reset hooks, 3 no-op placeholders). hive_user_session.dart gained 3 notifyUserChanged call sites (lines 255 / 387 / 424). flutter analyze --no-fatal-infos on 10 touched files clean (1 pre-existing unrelated info on `synchronized` import in hive_user_session.dart predates this batch)." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Registry is pure in-memory. No Hive box / adapter / migration touched. HiveUserSession's locked mutator semantics preserved (callbacks fire AFTER the lock-protected flip)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Pure client-side scaffold." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job affected." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS surface." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object touched." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret introduced." }
  - { tier: 11, name: ist_correctness, status: not_applicable, evidence: "Registry has no date-key surface." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Gate check_reader_manifest_complete (Gate 18) passes — phase-1 30 forbidden patterns + phase-2 25 manifest-complete concepts including the new singleton_lifecycle_registry entry. Test suite for the new concept: 14/14 PASS." }
impact_analysis:
  callers_audited:
    - lib/core/services/hive_user_session.dart (only reader — 3 call sites)
    - 7 singleton constructors (all writers)
  callers_unchanged:
    - Every consumer of SyncService.instance / SubscriptionService.instance /
      WorkoutScheduleService.instance / UsageCounterService.instance /
      AiService.instance / RazorpayService.instance / SeedService.instance
      (hundreds of sites across lib/ — public API of each singleton is
      unchanged).
  out_of_scope:
    - sync_service.dart part-file structure (A6 agent's scope)
    - features/ai_coach files (A10 just landed; some files moved)
    - Full Riverpod conversion of the seven singletons (multi-day
      follow-up; this scaffold is the stepping stone)
  follow_ups:
    - Once each singleton is migrated into a Riverpod Provider, the
      registry can be deleted and the hook replaced with
      `ref.listen(authUserIdProvider, (_, __) => state.reset())`.
    - The 4 Repository singletons mentioned in the audit (`*Repository.instance × 4`)
      are intentionally NOT wired in this batch — repositories are
      stateless read-only adapters by design. If a future repository
      adds a cache, it can register here.
related_bugs:
  - 2026-05-21-auth-session-bootstrapper-A1-A9-17ae38 (A1+A9 god-provider extract — same tech-debt audit batch)
  - 2026-05-21-ai-coach-repository-split-A10-9c2b1f (A10 repository split — same tech-debt audit batch)
recurrence: |
  Not a recurrence — first time the cross-account leak class is
  addressed for in-memory singleton state. The on-disk leak class was
  closed by HiveUserSession namespacing (Test #10.1) + the
  cross-account guard (audit 2026-05-11 C-6).
---

# Singleton lifecycle registry — A7

Tech-debt audit 2026-05-20 finding A7 (score 14) — narrow scaffold for
cross-account state leaks in seven `static .instance` services that
live outside the Riverpod graph.

See the YAML frontmatter for the full writer/reader manifest,
12-tier verification, and proposed-fix scope. Headline:
SingletonLifecycleRegistry.register/notifyUserChanged provides a
process-wide bridge between HiveUserSession's user-swap signal and
seven singletons that hold mutable in-memory caches. Public APIs are
unchanged; full Riverpod conversion is the follow-up.
