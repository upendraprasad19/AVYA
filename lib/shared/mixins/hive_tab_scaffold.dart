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

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// First-mount hook. Runs inside the initial microtask, BEFORE the
  /// `isLoading = false` flip. Default no-op. Override for side effects
  /// (e.g. `_checkStreakFreezeUsed`, prediction poller, fire-and-forget
  /// async kick-offs). NOT re-run on [retry].
  Future<void> initTab() async {}

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await initTab();
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
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
