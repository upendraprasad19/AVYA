// lib/core/services/sync_domains/coach_sync_domain.dart
//
// [SyncDomain] wrapper for the AI coach part-file surfaces (audit
// 2026-05-20 / A6 — B5 D7-D8 batch).
//
// Wraps `lib/core/services/sync/sync_coach.dart` via the public
// forwarders on `SyncServiceCoach`.
//
// Sub-surfaces:
//   - coach_interactions : _syncCoachInteractions ↔ _restoreCoachInteractions
//   - coach_memory       : syncCoachMemoryNow     ↔ _restoreCoachMemory
//
// NOT YET WIRED — `SyncFlags.useDomainFor('coach')` defaults FALSE.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class CoachSyncDomain extends SyncDomainBase {
  CoachSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'coach';

  @override
  Future<void> push() async {
    await Future.wait([
      _syncService.pushCoachInteractionsForSyncDomain(),
      _syncService.pushCoachMemoryForSyncDomain(),
    ], eagerError: false);
  }

  @override
  Future<void> restore() async {
    await Future.wait([
      _syncService.restoreCoachInteractionsForSyncDomain(),
      _syncService.restoreCoachMemoryForSyncDomain(),
    ], eagerError: false);
  }
}
