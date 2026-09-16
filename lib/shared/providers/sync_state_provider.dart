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

  @override
  SyncState build() {
    // Seed from current queue depth.
    final initial = SyncQueue.instance.pendingCountSync;
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

    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
      _connectivitySub?.cancel();
      _connectivitySub = null;
      _drainTimer?.cancel();
      _drainTimer = null;
    });

    return initial == 0 ? const SyncIdle() : SyncQueued(initial);
  }

  void _onCount(int count) {
    state = count == 0 ? const SyncIdle() : SyncQueued(count);
  }

  /// User tapped "Retry now" on the banner — kick off a drain immediately.
  Future<void> retryNow() async {
    await SyncQueue.instance.drain();
  }
}

final syncStateProvider =
    NotifierProvider<SyncStateNotifier, SyncState>(SyncStateNotifier.new);
