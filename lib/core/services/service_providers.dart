// lib/core/services/service_providers.dart
//
// Tech-debt audit 2026-05-20 / A7 — Riverpod providers for the seven
// `static .instance` services that were registered with
// [SingletonLifecycleRegistry] in the A7 scaffold batch.
//
// These providers expose the SAME singleton instance as `XxxService.instance`
// — the goal of this batch is NOT to restructure the services (no
// constructor injection, no DI re-architecture). The goal is to give every
// caller a canonical Riverpod entry point so that:
//
//   1. Caller migration is mechanical: `XxxService.instance.method()` →
//      `ref.read(xxxServiceProvider).method()`.
//   2. The provider wires `ref.listen(authUserIdTokenProvider, …)` so the
//      SingletonLifecycleRegistry reset hook fires through Riverpod's
//      lifecycle — even if the static registry path becomes inert in some
//      future scenario (e.g. a test ProviderContainer that doesn't go
//      through HiveUserSession), the per-service reset still fires.
//   3. The `static get instance` getter is `@Deprecated` so new callers see
//      the lint and prefer the Provider.
//
// Full removal of the singleton path is a follow-up batch (CLAUDE.md §4.11 —
// gates before refactor; this batch IS the gate). Once every caller has
// migrated to the provider, the `@Deprecated` becomes an analyzer error,
// then `_instance` + `instance` get deleted in a final cleanup commit.
//
// SoT registry: see `singleton_lifecycle_registry` concept (writers /
// readers updated in this commit to point at this file).
//
// closes-diagnose: 2026-05-21-a7-singleton-provider-migration-<6char>

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

// ignore_for_file: deprecated_member_use_from_same_package

/// Helper — every provider below wires the same shape:
///   - on auth user id change, fire the SingletonLifecycleRegistry hook
///     for [singletonName] (so the per-service `_onUserChanged` runs).
///   - return the existing singleton instance.
///
/// The registry hook is a no-op for services whose `_onUserChanged`
/// doesn't touch in-memory state today (SeedService / UsageCounterService /
/// WorkoutScheduleService), but the wiring is the same so the contract is
/// uniform.
void _wireResetHook(Ref ref, String singletonName) {
  ref.listen<String>(
    authUserIdTokenProvider,
    (previous, next) {
      if (previous == next) return;
      // The registry call also fires for sibling singletons (it iterates
      // every registered callback), but that is the SAME contract
      // [HiveUserSession] follows — `notifyUserChanged()` is global, not
      // per-name. Calling it from any provider on the listener edge gives
      // us the Riverpod-graph wiring without changing registry semantics.
      // [singletonName] is captured here only for telemetry / debug
      // breadcrumbs; the registry itself does not key off it.
      SingletonLifecycleRegistry.notifyUserChanged();
    },
  );
}

/// Provider for [SubscriptionService] — PRO state + payment grace window.
///
/// Reset behavior: re-fires `onStateChanged` so widgets re-read the new
/// user's PRO state from the (post-flip) namespaced userBox.
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  _wireResetHook(ref, 'SubscriptionService');
  return SubscriptionService.instance;
});

/// Provider for [SyncService] — orchestrator for Hive→Supabase fan-out +
/// restoreFromCloud + realtime + queue.
///
/// Reset behavior: drops `_realtimeSubscription`, the health-sync
/// completer, the restore-cancelled flag, and the restore-progress label
/// so the previous user's sync state cannot leak into the new session.
final syncServiceProvider = Provider<SyncService>((ref) {
  _wireResetHook(ref, 'SyncService');
  return SyncService.instance;
});

/// Provider for [WorkoutScheduleService] — phase plan, schedule writes,
/// exercise swap, day shorten / pause / template assignment.
///
/// Reset behavior: no-op today (all state lives in workoutBox / userBox).
/// A2 (tech-debt audit follow-up) will split this service into 4 sibling
/// services; this provider becomes the transitional bridge.
final workoutScheduleServiceProvider =
    Provider<WorkoutScheduleService>((ref) {
  _wireResetHook(ref, 'WorkoutScheduleService');
  return WorkoutScheduleService.instance;
});

/// Provider for [UsageCounterService] — daily increment-at-API-call
/// counters (AI text log, scan meal, cart auditor).
///
/// Reset behavior: no-op today (all counters live in per-user userBox via
/// MigratedKey).
final usageCounterServiceProvider = Provider<UsageCounterService>((ref) {
  _wireResetHook(ref, 'UsageCounterService');
  return UsageCounterService.instance;
});

/// Provider for [AiService] — Edge Function bridge for the AI coach /
/// food AI / scan meal pipeline.
///
/// Reset behavior: closes + drops the cached Dio HTTP client so the next
/// call lazily rebuilds one. In-flight requests from a previous user are
/// severed.
final aiServiceProvider = Provider<AiService>((ref) {
  _wireResetHook(ref, 'AiService');
  return AiService.instance;
});

/// Provider for [RazorpayService] — checkout flow + payment webhook
/// polling.
///
/// Reset behavior: nulls `_onSuccess`, `_onFailure`, and `_pendingPlan`
/// so an abandoned-checkout callback from the previous user cannot fire
/// against the new user's UI.
final razorpayServiceProvider = Provider<RazorpayService>((ref) {
  _wireResetHook(ref, 'RazorpayService');
  return RazorpayService.instance;
});

/// Provider for [SeedService] — bundled JSON seed-into-Hive on first
/// launch.
///
/// Reset behavior: no-op (seeds are shared, not per-user). Wired for
/// parity + future-proofing.
final seedServiceProvider = Provider<SeedService>((ref) {
  _wireResetHook(ref, 'SeedService');
  return SeedService.instance;
});
