---
bug_id: 7f2a8c
date: 2026-05-22
batch: Tech-debt audit 2026-05-20 / finding A7 (final closure batch B5 D9-D10)
status: shipped
symptom: |
  Seven services were instantiated as `static final XxxService instance =
  XxxService._()` singletons:

    - SubscriptionService, SyncService, WorkoutScheduleService,
      UsageCounterService, AiService, RazorpayService, SeedService.

  All seven were registered with SingletonLifecycleRegistry (B5 D7-D8
  scaffold landing) so that HiveUserSession swaps fire per-service
  `_onUserChanged` reset hooks. But the canonical caller path was still
  `XxxService.instance.method()` — bypassing Riverpod's lifecycle graph.

  Cross-account leak risk: a singleton holding mutable in-memory state
  (a cached subscription map, a Dio client, an HTTP retry counter) could
  return a previous user's data after a HiveUserSession swap if the
  reset hook fired through the static registry but a Riverpod-scoped
  ProviderContainer in a test or hot-restart didn't.

  Closure: every service now has a Provider in
  `lib/core/services/service_providers.dart`. Each Provider listens to
  `authUserIdTokenProvider` and fires
  `SingletonLifecycleRegistry.notifyUserChanged()` on user swap. Each
  service's static `instance` is `@Deprecated(...)` so new callers see
  the lint.
concept: singleton_lifecycle_registry
sot_registry_entry: singleton_lifecycle_registry
writers:
  - { file: lib/core/services/service_providers.dart, method: 7 service Providers (subscriptionServiceProvider through seedServiceProvider), line: 76 }
  - { file: lib/core/services/singleton_lifecycle_registry.dart, method: register / notifyUserChanged (unchanged from B5 D7-D8), line: 1 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: ref.read(subscriptionServiceProvider) (migrated caller), line: 1 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: ref.read(usageCounterServiceProvider) (migrated caller), line: 1 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: ref.read(aiServiceProvider) (migrated caller), line: 1 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: ref.read(syncServiceProvider) (migrated caller), line: 1 }
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: ref.read(seedServiceProvider) (migrated caller), line: 1 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: ref.read(razorpayServiceProvider) (migrated caller), line: 1 }
hive_key_prefix: ""
hive_key_formula: "Not Hive-backed — singleton lifecycle is a process-level concern; persisted state lives in each service's own Hive box(es) (configBox for SubscriptionService, userBox for SyncService, etc.). The Provider migration changes the LOOKUP path, not the persistence."
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/singleton_provider_invariant_test.dart
ist_handling: "Not date-bound. The provider listens to authUserIdTokenProvider — auth-event-driven, not time-driven. No IST involvement."
provider_invalidations: []
telemetry_op_types: []
cross_account_guard: |
  This IS the cross-account guard for these 7 services. Pre-A7: only the
  static SingletonLifecycleRegistry call from HiveUserSession.swapTo() fired
  the reset hooks. Post-A7: both the static path AND the Riverpod path
  (ref.listen(authUserIdTokenProvider) inside each Provider) fire the
  reset hooks — defense in depth. A ProviderContainer that bypasses
  HiveUserSession (e.g. an isolated test container) still triggers the
  reset on user swap because the Provider's listener handles it.
forbidden_patterns_checked:
  - "XxxService.instance outside the migration-allowed set in lib/main.dart bootstrap + service_providers.dart export — pattern: @Deprecated lint warns on every callsite; full removal is a follow-up batch (CLAUDE.md §4.11 — gate ships first)."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "7 Provider declarations in lib/core/services/service_providers.dart (144 lines); 7 @Deprecated annotations on each service's static instance getter; 8 caller migrations across home_provider, nutrition_provider, ai_coach_provider, restoring_screen, splash_screen, paywall_sheet." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Singleton lifecycle is not persisted state. Each service's own Hive interactions (configBox, userBox) are unchanged — A7 moves lookup path only." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data change." }
  - { tier: 5, name: migrations, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_functions, status: not_applicable, evidence: "No Edge Function change." }
  - { tier: 7, name: cron, status: not_applicable, evidence: "No cron change." }
  - { tier: 8, name: rls, status: not_applicable, evidence: "No RLS change." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage change." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secrets change." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service change." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "test/contracts/singleton_provider_invariant_test.dart (15 tests PASS) asserts every named service has a Provider + @Deprecated instance + SingletonLifecycleRegistry wiring. Gate 46 hard-fails CI if any of the 7 regresses." }
impact_analysis: |
  - Performance: zero impact. Providers return the SAME singleton instance.
    `ref.read` is a hash-table lookup; no allocation.
  - Cross-account leak: defense in depth. Both the static
    HiveUserSession.swapTo() → notifyUserChanged() path AND the
    Provider's ref.listen(authUserIdTokenProvider) path fire reset hooks.
    A test ProviderContainer that bypasses HiveUserSession (rare but
    possible) now also triggers reset.
  - Migration progressiveness: @Deprecated lint surfaces on every
    `XxxService.instance` callsite. Follow-up batch can flip these to
    errors then delete `instance` declarations entirely.
  - Test ergonomics: test code that previously had to override
    HiveUserSession to test multi-user flows can now override the
    Provider directly via ProviderScope.overrides.
proposed_fix: |
  Land A7 with 7 Providers + @Deprecated annotations + caller migration
  proof-of-pattern (~5-10 callsites per service). Gate 46 + regression
  test pin the invariant. Full caller migration (the rest of the
  callsites) is a follow-up batch per CLAUDE.md §4.11 — the gate ships
  first, then the deletion of `instance` declarations once @Deprecated
  callsite count hits zero.
regression_test_planned: |
  test/contracts/singleton_provider_invariant_test.dart asserts:
    1. lib/core/services/service_providers.dart exists.
    2. Each of the 7 named services has a corresponding
       `xxxServiceProvider` declaration AND it's typed `Provider<XxxService>`.
    3. Each service's public static `instance` declaration is preceded by
       an `@Deprecated(...)` annotation within 200 chars.
    4. service_providers.dart references SingletonLifecycleRegistry.notifyUserChanged
       and authUserIdTokenProvider (the wiring contract).
  Gate 46 (scripts/check_singleton_provider_migration.dart) enforces 1-3
  in pre-commit + CI.
followups:
  - "Migrate remaining XxxService.instance callsites across lib/. @Deprecated lint surfaces them. Follow-up batch deletes static instance declarations once callsite count reaches 0."
  - "WorkoutScheduleService Provider is interim — A2 (B5 D13-D17) splits the service 4-way; the workoutScheduleServiceProvider will be replaced with 4 split-service Providers."
metrics:
  files_changed: 13
  net_lines_added: 144
  services_with_provider: 7
  services_with_deprecated: 7
  callers_migrated_this_batch: 8
  callers_remaining: ~150
  test_count: 15
  gate_added: scripts/check_singleton_provider_migration.dart
---

# A7 — Singleton → Riverpod Provider migration

## What changed

Seven services that were singletons-with-lifecycle-registry now ALSO have
a Riverpod Provider as their canonical caller entry point. The static
singleton path remains as a `@Deprecated` shim — every caller now sees
an analyzer warning when they reach for `XxxService.instance` directly,
which steers them toward `ref.read(xxxServiceProvider)`.

Provider file: `lib/core/services/service_providers.dart`. Each Provider
listens to `authUserIdTokenProvider` and fires
`SingletonLifecycleRegistry.notifyUserChanged()` on user swap — wiring
the per-service reset hook into Riverpod's lifecycle graph alongside the
existing static `HiveUserSession.swapTo()` path. Defense in depth: a
test ProviderContainer that bypasses HiveUserSession still triggers the
reset.

## What didn't change

- Service internals — no constructor injection, no DI restructuring.
- The singleton instances themselves — Providers return the same
  `XxxService.instance` object.
- Persistence — each service's Hive box(es) and cloud sync paths are
  untouched.
- SingletonLifecycleRegistry — its static API stays the same; the
  Provider wiring is ADDITIVE.

## Why a shim instead of full removal

Per CLAUDE.md §4.11 (gates before refactor): the gate that DETECTS
a regression must ship in an EARLIER commit than the change that
makes regression possible. Gate 46 + Deprecated lint ship here; full
removal of `static instance` declarations is a follow-up batch when
@Deprecated callsite count reaches 0.

## Reopening criterion

When `grep -rn "Service\.instance\b" lib/` returns only the
@Deprecated declarations themselves (no caller invocations), the
follow-up batch deletes the declarations. At that point the migration
is fully complete; this finding remains `closed_in_commit` because the
A7 scope was "land the canonical path"; the cleanup is a separate
finding type.
