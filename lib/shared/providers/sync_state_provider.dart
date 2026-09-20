/// User-visible sync state. Drives the `SyncBanner` widget.
///
/// Sources: `SyncQueue.pendingCount` stream + `SyncService` in-flight events.
/// For this first implementation the state is simple: just pending count from
/// the queue. In-flight tracking is a later enhancement.
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar C.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/hive_service.dart';
import '../../core/services/sync_queue.dart';

/// How often the periodic auto-drain sweeps the queue while this provider is
/// alive (i.e. for the app's lifetime — `syncStateProvider` is never
/// invalidated). Named so the interval `sync_queue.dart`'s own doc comment
/// promises is greppable and can't silently drift from what's actually
/// wired here again (diagnose — see docs/diagnoses/: this constant did not
/// exist before this fix; the promised timer simply didn't exist either).
const Duration syncQueueAutoDrainInterval = Duration(minutes: 5);

/// Banner display grace (2026-09-17 founder follow-up to the auto-drain
/// fix): a pending op YOUNGER than this never turns the SyncBanner on. A
/// login-time version conflict enqueues an op that the next 5-min drain
/// tick typically self-heals — flashing "1 change waiting to sync" for
/// those ≤5 minutes reads as something being wrong when nothing needs the
/// user. The window is one drain tick plus slack, so anything that
/// survived its first auto-retry attempt still surfaces. The rendered
/// count is therefore "pending ops older than the grace window" — it can
/// undercount transiently (documented in docs/architecture/sync.md).
const Duration syncBannerGraceWindow = Duration(minutes: 6);

/// How often the provider recomputes the DISPLAY state while debt exists —
/// the only mechanism that notices an op AGING past
/// [syncBannerGraceWindow] when no queue event fires at that moment (the
/// stream notifies on mutations, not on age crossings). Early-exits while
/// the queue is empty, so the steady-state cost is one Hive read per
/// minute only when the banner is already relevant or just-relevant.
const Duration syncBannerDisplayRefreshInterval = Duration(minutes: 1);

/// Pure decision extracted for testability (`connectivity_plus`'s stream
/// needs a platform channel, which a plain unit test can't exercise) — true
/// when the reported connectivity change represents a RESTORE (at least one
/// non-`none` result), the condition that should trigger a drain.
bool shouldDrainOnConnectivityChange(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

/// §4.6 kill-switch predicate for the two auto-drain triggers below, kept as
/// a pure function over the raw `configBox` value so it's testable without a
/// Hive box open (B-pass Finding 3, `docs/reviews/08821dc5a27b-review.md`:
/// this batch's blast radius is `platform`, via the new `connectivity_plus`
/// dependency, and platform tier requires a kill-switch per
/// `docs/blast_radius.yaml`'s `requires: feature_flag` — matches the
/// established `disable_sync_debounce`/`disable_bg_restore`-style convention
/// in `sync_service.dart`/`restoring_screen.dart`: absent or anything but
/// `true` means "not disabled", so the fix stays ACTIVE by default and a
/// missing/uninitialized configBox can't accidentally disable it).
bool isSyncAutoDrainDisabled(Object? rawConfigValue) => rawConfigValue == true;

/// §4.6 kill-switch for the banner display grace (this batch): `true` shows
/// the RAW pending count — i.e. exactly the pre-grace behavior.
bool isSyncBannerGraceDisabled(Object? rawConfigValue) =>
    rawConfigValue == true;

/// §4.6 kill-switch for the manual force-retry (this batch): `true` makes
/// `retryNow()` issue a plain unforced `drain()` — exactly the pre-force
/// behavior (which could silently no-op on a backoff-windowed op).
bool isSyncForceRetryDisabled(Object? rawConfigValue) =>
    rawConfigValue == true;

/// Pure display policy (this batch, plan-review round 1 Finding 4): of the
/// given pending ops, how many have actually WAITED long enough to surface
/// — at least [syncBannerGraceWindow] since their first failed attempt.
/// Younger ops are presumed self-healing (the 5-min auto-drain typically
/// resolves them) and stay silent.
int syncBannerDisplayCount(List<PendingSyncOp> ops, DateTime now) =>
    ops
        .where(
          (op) => now.difference(op.firstAttemptAt) >= syncBannerGraceWindow,
        )
        .length;

sealed class SyncState {
  const SyncState();
}

class SyncIdle extends SyncState {
  const SyncIdle();
}

class SyncQueued extends SyncState {
  final int pendingCount;
  const SyncQueued(this.pendingCount);
}

class SyncStateNotifier extends Notifier<SyncState> {
  StreamSubscription<int>? _sub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _drainTimer;
  Timer? _displayTimer;

  /// Defensive read (same pattern as `sync_service.dart`'s `_syncDebounceDisabled`
  /// et al.) — a missing/unopened configBox defaults to fix-ACTIVE.
  bool get _autoDrainDisabled {
    try {
      return isSyncAutoDrainDisabled(
          HiveService.instance.configBox.get('disable_sync_auto_drain'));
    } catch (_) {
      return false;
    }
  }

  /// Defensive read for the banner grace kill-switch (same pattern).
  bool get _bannerGraceDisabled {
    try {
      return isSyncBannerGraceDisabled(
          HiveService.instance.configBox.get('disable_sync_banner_grace'));
    } catch (_) {
      return false;
    }
  }

  /// Defensive read for the manual force-retry kill-switch (same pattern).
  bool get _forceRetryDisabled {
    try {
      return isSyncForceRetryDisabled(
          HiveService.instance.configBox.get('disable_sync_force_retry'));
    } catch (_) {
      return false;
    }
  }

  /// ONE state funnel for every path that produces sync state — build seed,
  /// stream events, and the display-aging timer alike (plan-review round 1
  /// Finding 4: two independent mappings drifting apart is how "0 changes
  /// waiting to sync" ships). `rawCount` is the RAW queue depth (the
  /// zero-shortcut avoids the `pendingOps()` read when there is nothing to
  /// show); the displayed count applies the grace policy unless its
  /// kill-switch is on.
  SyncState _stateFor(int rawCount) {
    if (rawCount == 0) return const SyncIdle();
    if (_bannerGraceDisabled) return SyncQueued(rawCount);
    final displayable =
        syncBannerDisplayCount(SyncQueue.instance.pendingOps(), DateTime.now());
    return displayable == 0 ? const SyncIdle() : SyncQueued(displayable);
  }

  @override
  SyncState build() {
    _sub = SyncQueue.instance.pendingCount.listen(_onCount);

    // Auto-drain trigger 1 of 2 that `sync_queue.dart`'s own doc comment
    // promised but never actually wired (diagnose — see docs/diagnoses/):
    // connectivity restore. Safe to fire on every reported change (including
    // a flap) because `drain()` is a no-op with nothing due AND (as of this
    // batch's B-pass, Finding 4) in-flight-guarded against overlapping
    // itself — NOT because of `_isDue`, which is a time-based backoff check
    // with no concurrency semantics at all; the real safety net today is
    // that both registered executors are independently idempotent.
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      if (_autoDrainDisabled) return;
      if (shouldDrainOnConnectivityChange(results)) {
        unawaited(SyncQueue.instance.drain());
      }
    });

    // Auto-drain trigger 2 of 2: periodic sweep. Simpler than the doc
    // comment's "while foregrounded" — this fires regardless of app
    // lifecycle state, which only means an occasional drain call while
    // backgrounded (harmless; `drain()` is a no-op when nothing is due, and
    // most platforms suspend/throttle timers in the background anyway).
    // Doing this is a strict improvement over the pre-fix state, where
    // NEITHER trigger existed and an offline write could sit queued
    // indefinitely until the next app launch or a manual "Retry" tap.
    _drainTimer = Timer.periodic(syncQueueAutoDrainInterval, (_) {
      if (_autoDrainDisabled) return;
      unawaited(SyncQueue.instance.drain());
    });

    // Display-aging sweep (this batch): the ONLY mechanism that notices an
    // op crossing [syncBannerGraceWindow] when no queue event fires at that
    // moment — the pending-count stream notifies on MUTATIONS, not on age
    // crossings. Placed AFTER the drain timer deliberately (plan-review
    // round 2 Finding 9): the structural test pins `_drainTimer =` by its
    // FIRST occurrence. Early-exits while the queue is empty so the
    // steady-state cost is nil. Kill-switched via [_stateFor]'s grace
    // check, which routes to the raw count when disabled.
    _displayTimer = Timer.periodic(syncBannerDisplayRefreshInterval, (_) {
      final raw = SyncQueue.instance.pendingCountSync;
      if (raw == 0) return;
      state = _stateFor(raw);
    });

    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
      _connectivitySub?.cancel();
      _connectivitySub = null;
      _drainTimer?.cancel();
      _drainTimer = null;
      _displayTimer?.cancel();
      _displayTimer = null;
    });

    return _stateFor(SyncQueue.instance.pendingCountSync);
  }

  void _onCount(int count) {
    state = _stateFor(count);
  }

  /// User tapped "Retry now" on the banner — kick off a drain immediately,
  /// FORCED so an op sitting inside a backoff window is retried now rather
  /// than silently skipped (pre-force, `_isDue`'s filter could make this
  /// tap a no-op with zero feedback). Kill-switched back to the plain
  /// unforced drain per §4.6.
  Future<void> retryNow() async {
    if (_forceRetryDisabled) {
      await SyncQueue.instance.drain();
      return;
    }
    await SyncQueue.instance.drain(force: true);
  }
}

final syncStateProvider =
    NotifierProvider<SyncStateNotifier, SyncState>(SyncStateNotifier.new);
