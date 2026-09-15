/// User-visible sync state. Drives the `SyncBanner` widget.
///
/// Sources: `SyncQueue.pendingCount` stream + `SyncService` in-flight events.
/// For this first implementation the state is simple: just pending count from
/// the queue. In-flight tracking is a later enhancement.
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar C.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/sync_queue.dart';

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

  @override
  SyncState build() {
    // Seed from current queue depth.
    final initial = SyncQueue.instance.pendingCountSync;
    _sub = SyncQueue.instance.pendingCount.listen(_onCount);

    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
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
