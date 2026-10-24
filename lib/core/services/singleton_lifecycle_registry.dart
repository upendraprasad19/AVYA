// lib/core/services/singleton_lifecycle_registry.dart
//
// Tech-debt audit 2026-05-20 / A7 — narrow scaffold for cross-account
// state leaks in `static .instance` singletons.
//
// Problem (A7, audit score 14):
//   Seven core services live OUTSIDE the Riverpod graph as static
//   singletons (SyncService, SubscriptionService, WorkoutScheduleService,
//   UsageCounterService, AiService, RazorpayService, SeedService). They
//   hold mutable in-memory state (cached HTTP clients, completers,
//   stream subscriptions, in-flight flags, callbacks). When the user
//   account flips inside [HiveUserSession] (sign-out → sign-up, or
//   cross-account guard fire), the singleton instance survives — its
//   stale state can leak into the new user session.
//
// Full Riverpod conversion is a multi-day refactor (hundreds of caller
// migrations). This registry is the narrow stepping-stone:
//   1. Each singleton registers a `_onUserChanged` callback at
//      construction time.
//   2. [HiveUserSession] calls [notifyUserChanged] AFTER the box state
//      has flipped to the new user.
//   3. Each callback resets the singleton's mutable state via its
//      existing reset hook (or a new private one).
//
// Public singleton API is unchanged — callers do not move. Follow-up
// batch can migrate each singleton into a Riverpod Provider with
// `ref.listen(authUserIdProvider, (_, __) => state.reset())`.
//
// closes-diagnose: 2026-05-21-singleton-lifecycle-A7-7a3e1c

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';

/// Process-wide registry of singleton lifecycle hooks.
///
/// Singletons register a "user changed" callback at construction. When
/// [HiveUserSession] flips to a new user, [notifyUserChanged] is invoked
/// AFTER the namespaced Hive boxes have been swapped — every registered
/// callback fires so each singleton can reset in-memory caches before
/// the next read.
///
/// Re-registration with the same [name] is allowed and replaces the
/// previous callback (idempotent — useful for tests that re-construct).
class SingletonLifecycleRegistry {
  SingletonLifecycleRegistry._();

  /// Internal map of name → onUserChanged callback. Linked-hash-map
  /// preserves insertion order so callbacks fire in a deterministic
  /// sequence (matches singleton construction order in main.dart).
  static final Map<String, void Function()> _callbacks =
      <String, void Function()>{};

  /// Register a lifecycle callback for [name]. Idempotent — calling
  /// twice with the same [name] replaces the previous callback. The
  /// callback fires from [notifyUserChanged] after a user swap; it MUST
  /// be cheap (synchronous, no I/O) since it runs inline.
  static void register(String name, void Function() onUserChanged) {
    _callbacks[name] = onUserChanged;
  }

  /// Returns the registered names (debugging / test introspection).
  /// Order matches registration order.
  @visibleForTesting
  static List<String> registeredNames() =>
      List<String>.unmodifiable(_callbacks.keys);

  /// Returns the number of currently-registered callbacks.
  static int get count => _callbacks.length;

  /// Invoke every registered callback. Caught exceptions are reported
  /// via [ErrorTelemetry.recordNonFatal] (H-42 contract) but never
  /// rethrown — one bad callback must not prevent the others from
  /// running.
  ///
  /// Called by [HiveUserSession._openForUserLocked],
  /// [HiveUserSession._closeAllLocked], and
  /// [HiveUserSession._deleteAllFilesForCurrentUserLocked] AFTER the
  /// static owner fields have been flipped to the new state.
  static void notifyUserChanged() {
    for (final entry in _callbacks.entries) {
      try {
        entry.value();
      } catch (e, st) {
        // H-42 — telemetry pair. Never throw out of a lifecycle hook.
        debugPrint(
            '[SingletonLifecycleRegistry] callback "${entry.key}" threw: $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: 'singleton_lifecycle_callback',
          extra: {'singleton': entry.key},
        ));
      }
    }
  }

  /// Reset registry state — test-only helper. Production code must
  /// never clear the registry (the seven singletons rely on their
  /// callbacks being live for the full app lifetime).
  @visibleForTesting
  static void resetForTesting() {
    _callbacks.clear();
  }
}
