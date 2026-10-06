// lib/core/services/sync_domains/streaks_sync_domain.dart
//
// First proof-of-pattern implementation of [SyncDomain] (audit
// 2026-05-20 / finding A6). Wraps the existing
// `SyncService._syncStreaks` + `SyncService._restoreStreaks` private
// helpers via the public forwarders
// `pushStreaksForSyncDomain` / `restoreStreaksForSyncDomain` on the
// `SyncServiceWorkout` extension.
//
// This class is a FACADE — it does not duplicate the helper logic.
// The part-file `lib/core/services/sync/sync_workout.dart` remains the
// source of truth for the actual push/restore behaviour. The role of
// this class is to demonstrate that the [SyncDomain] interface can
// host a real domain without breaking the existing fan-out wiring
// in `SyncService.syncWorkoutData` / `restoreFromCloudForUser` (both
// of which continue to call the private methods directly).
//
// Why streaks first
// -----------------
// The streaks pair is the smallest contained `_syncX` / `_restoreX`
// duo in the codebase:
//   * `_syncStreaks(userId)` — 45 lines, single Hive list, single cloud
//     table (`streaks`), single onConflict key.
//   * `_restoreStreaks(userId)` — 53 lines, single cloud table, single
//     Hive list with dedupe by week_start.
// No cross-domain transactional dependency, no template ordering quirk,
// no rate-limit interplay. Ideal scaffold target.
//
// Migration path forward
// ----------------------
// As each part-file is migrated to its own SyncDomain implementation
// in follow-up batches, the SyncService fan-out switches from calling
// `_syncStreaks(userId)` directly to dispatching through
// `domain.push()`. That migration is OUT OF SCOPE for this batch —
// the scaffold proves the pattern works without disturbing the live
// call graph.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

/// [SyncDomain] implementation for the streaks surface (the
/// `streaks` Hive list under `healthBox['streaks']` + the cloud
/// `streaks` table).
class StreaksSyncDomain extends SyncDomainBase {
  StreaksSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'streaks';

  /// Push local streaks (`healthBox['streaks']`) to cloud `streaks`
  /// table. Delegates to the canonical
  /// `SyncService._syncStreaks(userId)` via its public forwarder.
  @override
  Future<void> push() => _syncService.pushStreaksForSyncDomain();

  /// Pull cloud `streaks` table into local `healthBox['streaks']`.
  /// Delegates to the canonical `SyncService._restoreStreaks(userId)`
  /// via its public forwarder.
  @override
  Future<void> restore() => _syncService.restoreStreaksForSyncDomain();

  // pushSnapshot intentionally inherits the [SyncDomain] no-op default
  // — the streaks surface is not part of the AI snapshot fan-out.
}
