// lib/shared/mixins/hive_tab_scaffold.dart
//
// Tech-debt audit 2026-05-20 / B5 / C1.
//
// HiveTabScaffoldMixin — extracts the copy-pasted "isLoading + Future.microtask
// + retry" boilerplate that lived in 4 of the 5 main tab screens (Home, Train,
// Nutrition, Profile). The AI Coach tab uses a fundamentally different mount
// shape (chat history hydration, no skeleton/retry loop) so it intentionally
// does NOT use this mixin — see the allow-list in
// `scripts/check_tab_screen_uses_hive_scaffold.dart`.
//
// Before:
//
//   class _MyScreenState extends ConsumerState<MyScreen> {
//     bool _isLoading = true;
//
//     @override
//     void initState() {
//       super.initState();
//       Future.microtask(() {
//         if (mounted) setState(() => _isLoading = false);
//       });
//     }
//
//     void _retry() {
//       setState(() => _isLoading = true);
//       ref.invalidate(fooProvider);
//       ref.invalidate(barProvider);
//       Future.microtask(() {
//         if (mounted) setState(() => _isLoading = false);
//       });
//     }
//   }
//
// After:
//
//   class _MyScreenState extends ConsumerState<MyScreen>
//       with HiveTabScaffoldMixin<MyScreen> {
//     @override
//     List<ProviderOrFamily> get retryInvalidates => [
//       fooProvider, barProvider,
//     ];
//   }
//
// The mixin owns the `_isLoading` flag (exposed as `isLoading` getter), the
// initial-mount microtask, and the `retry()` method. Subclasses get two
// optional hooks:
//
//   1. `initTab()` — async hook run inside the initial-mount microtask. Use
//      for first-time-only side effects (loading Hive prefs into `setState`-
//      able locals, starting a poller, kicking off a fire-and-forget async).
//      Default impl is a no-op. NOT re-run on retry — `retry()` only
//      re-invalidates `retryInvalidates` providers + cycles isLoading.
//
//   2. `invalidateOnRetry(ref)` — hook to invalidate any providers that
//      should refresh when the retry button fires. Default is a no-op
//      (still cycles isLoading). Use a callback rather than a typed list
//      because `ProviderOrFamily` is not exported from the public Riverpod
//      API; the inline `ref.invalidate(myProvider)` calls keep type safety
//      at each callsite.
//
// Rule: this mixin does NOT own error state. The 4 tab screens that use it
// catch render errors inside their `_buildContent` try/catch + dispatch
// `ErrorTelemetry.logEvent` themselves; they don't track an "init error"
// because the init body is a pure microtask flag-flip with no fallible work.
// If a future screen needs init-time error capture, extend this mixin rather
// than overload it.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

/// Mixin for `ConsumerState<T>` tab screens that follow the
/// "isLoading skeleton + microtask flag-flip + retry-invalidates-providers"
/// pattern. See file header for usage.
mixin HiveTabScaffoldMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _isLoading = true;

  /// Whether the screen is still in its initial skeleton state. Drives the
  /// `ScreenLoadingSkeleton` render at the top of `build()`.
  bool get isLoading => _isLoading;

  /// OBS-4 (b8e3f1 sibling, 2026-06-21) — true while the auth session is
  /// tearing down (sign-out) or not yet open (the FIX-1 owner-null window).
  /// `authUserIdTokenProvider` returns `'<anon>'` the moment the Hive owner is
  /// cleared — even before Supabase finishes `signOut` — so a tab screen that
  /// renders now would read an empty box, throw, and flash its
  /// "Failed to load…" error card. Gate the neutral skeleton on this instead;
  /// the router redirect to /sign-in (or /restoring) unmounts/reroutes the
  /// screen momentarily. Tab screens OR this into their `isLoading` branch.
  bool get isSessionTearingDown =>
      ref.watch(authUserIdTokenProvider) == '<anon>';

  /// Hook called from [retry] to refresh providers feeding this screen.
  /// Default no-op. Override and call `ref.invalidate(myProvider)` for
  /// every provider that should re-fetch when the user taps "retry" on
  /// the error state.
  void invalidateOnRetry(WidgetRef ref) {}

  /// Providers to refresh when a BACKGROUND RESTORE completes — an event
  /// with no user action behind it. Defaults to [invalidateOnRetry], which is
  /// right for most tabs.
  ///
  /// Override when a provider is safe to invalidate on a USER-INITIATED retry
  /// but NOT on an involuntary background event. B-pass finding 1 on b3c9d4:
  /// Nutrition's retry set includes `aiBreakdownProvider`, and
  /// `ai_mode_body.dart:41` treats its non-null -> null transition as "the user
  /// committed or cancelled" and pops the Log Food sheet. That inference is
  /// sound for a retry tap and FALSE for a restore tick, which would have
  /// closed the sheet and discarded a just-generated AI analysis with no
  /// explanation. Being safe for a user-tapped retry does not make a provider
  /// safe for an automatic trigger; that is what this seam separates.
  void invalidateOnBackgroundRestore(WidgetRef ref) => invalidateOnRetry(ref);

  /// First-mount hook. Runs inside the initial microtask, BEFORE the
  /// `isLoading = false` flip. Default no-op. Override for side effects
  /// (e.g. `_checkStreakFreezeUsed`, prediction poller, fire-and-forget
  /// async kick-offs). NOT re-run on [retry].
  Future<void> initTab() async {}

  /// H5 (Unit H, 2026-06-27) — kill-switch reverting to the pre-Unit-H
  /// "clear the skeleton only after `await initTab()` resolves" behavior.
  /// Defensive read: a widget test may pump a tab screen without
  /// `HiveService.init()`, so a missing configBox defaults to fix-active.
  bool get _skeletonFirstFrameDisabled {
    try {
      return HiveService.instance.configBox
              .get('disable_skeleton_first_frame') ==
          true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // b3c9d4 — every tab screen listens for the background restore
    // completing. Until this lived here it was wired ONLY in
    // home_screen.dart, so Home healed after a bg restore and Nutrition,
    // Train and Profile served their pre-restore snapshot for the whole
    // session (founder saw Home render the name while Profile showed
    // 'User'). Registration belongs to the mixin, not to each screen:
    // a per-screen list is a thing to remember, and the bug this fixes
    // WAS a forgotten entry in exactly such a list.
    //
    // Deliberately ABOVE the _skeletonFirstFrameDisabled early-return —
    // that kill-switch governs skeleton timing only, and a listener
    // registered below it would silently not exist whenever the switch
    // is engaged.
    try {
      SyncService.instance.restoreCompletedTick
          .addListener(_onRestoreCompleted);
    } catch (e, s) {
      // A tab must never fail to mount because sync isn't initialised
      // (widget tests pump these screens without SyncService).
      debugPrint('[HiveTabScaffoldMixin] tick listen failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, s,
          reason: 'hive_tab_scaffold_restore_tick_listen'));
    }
    if (_skeletonFirstFrameDisabled) {
      // Pre-Unit-H behavior: flip only after initTab() fully resolves.
      Future.microtask(() async {
        try {
          await initTab();
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      });
      return;
    }
    // H5 — clear the skeleton on the FIRST frame, decoupled from initTab()'s
    // async tail. Hive is already in-memory, so a slow/hung await inside an
    // override (or session churn) must NEVER strand the tab on a skeleton.
    // Run initTab()'s SYNCHRONOUS prefix now (e.g. a pending-promotion
    // read-and-clear + its own post-frame modal push) BEFORE registering the
    // flip, so that work is honoured first; let the async tail finish in the
    // background. The `isLoading || isSessionTearingDown` OR at each tab's
    // build() is untouched — the FIX-1/OBS-4 logout-flash guard stays intact.
    final initFuture = initTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isLoading = false);
    });
    unawaited(initFuture.catchError((Object e, StackTrace s) {
      debugPrint('[HiveTabScaffoldMixin] initTab() error: $e');
      // B-pass P2 (c4f8d2) — the async tail now always runs in the background,
      // so surface its failures to telemetry instead of swallowing silently.
      unawaited(ErrorTelemetry.recordNonFatal(e, s,
          reason: 'hive_tab_scaffold_init_tab'));
    }));
  }

  /// b3c9d4 — a completed background restore rewrote Hive underneath a
  /// screen that already built its providers. Refresh this tab's declared
  /// provider set.
  ///
  /// Calls [invalidateOnRetry] directly rather than [retry] on purpose:
  /// retry() cycles `isLoading`, which would flash a skeleton across every
  /// mounted tab on a routine restore. Mirrors the shape home_screen's
  /// bespoke `_onRestoreTick` used before it moved here.
  void _onRestoreCompleted() {
    if (!mounted) return;
    invalidateOnBackgroundRestore(ref);
  }

  @override
  void dispose() {
    try {
      SyncService.instance.restoreCompletedTick
          .removeListener(_onRestoreCompleted);
    } catch (_) {
      // Symmetric with the guarded add above: if the listener was never
      // registered there is nothing to remove.
    }
    super.dispose();
  }

  /// Re-fetch path for the screen's error-state retry button. Calls
  /// [invalidateOnRetry] then cycles isLoading via a microtask so the
  /// skeleton flashes briefly while providers refresh.
  void retry() {
    setState(() => _isLoading = true);
    invalidateOnRetry(ref);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }
}
