// lib/core/services/sync_domains/community_sync_domain.dart
//
// [SyncDomain] wrapper for the community part-file surfaces (audit
// 2026-05-20 / A6 — B5 D7-D8 batch).
//
// Wraps `lib/core/services/sync/sync_community.dart` via the public
// forwarders on `SyncServiceCommunity`.
//
// Sub-surfaces:
//   - custom_items : _syncCustomItems (push orchestrator covering both)
//                    ↔ _restoreCustomExercises + _restoreCustomFoods
//                      (restore is split — wrapper runs both halves
//                      sequentially under the single domain call).
//
// The push-side orchestrator already covers exercises AND foods in a
// single iteration over customBox (deterministic-id + logging-type
// repair pass). The matched-pair invariant is documented on the
// `CustomItems` allowlist entry in
// `test/contracts/sync_domain_interface_test.dart`.
//
// NOT YET WIRED — `SyncFlags.useDomainFor('community')` defaults FALSE.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class CommunitySyncDomain extends SyncDomainBase {
  CommunitySyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'community';

  @override
  Future<void> push() => _syncService.pushCustomItemsForSyncDomain();

  @override
  Future<void> restore() => _syncService.restoreCustomItemsForSyncDomain();
}
