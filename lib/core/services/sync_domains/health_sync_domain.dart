// lib/core/services/sync_domains/health_sync_domain.dart
//
// [SyncDomain] wrapper for the health part-file surfaces (audit
// 2026-05-20 / A6 — B5 D7-D8 batch).
//
// Wraps `lib/core/services/sync/sync_health.dart` via the public
// forwarders on `SyncServiceHealth`.
//
// Sub-surfaces:
//   - weight_logs       : _syncWeightLogs       ↔ _restoreWeightLogs
//   - measurements      : _syncMeasurements     ↔ _restoreMeasurements
//   - sleep_logs        : _syncSleepLogs        ↔ _restoreSleepLogs
//   - steps_logs        : _syncStepsLogs        ↔ _restoreStepsLogs
//   - urine_color_logs  : _syncUrineColorLogs   (push-only — see allowlist)
//
// `_syncUrineColorLogs` has no `_restoreUrineColorLogs` counterpart
// (the cloud data flows into water_logs rows by date, not a dedicated
// urine_color_logs table). The push runs as part of `push()`; the
// `restore()` half is a no-op for that surface. The asymmetry is
// captured in the exhaustiveness allowlist
// (`test/contracts/sync_domain_interface_test.dart` → `pushOnlyAllowlist`
// entry `UrineColorLogs`).
//
// NOT YET WIRED — `SyncFlags.useDomainFor('health')` defaults FALSE.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class HealthSyncDomain extends SyncDomainBase {
  HealthSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'health';

  @override
  Future<void> push() async {
    await Future.wait([
      _syncService.pushWeightLogsForSyncDomain(),
      _syncService.pushMeasurementsForSyncDomain(),
      _syncService.pushSleepLogsForSyncDomain(),
      _syncService.pushStepsLogsForSyncDomain(),
      _syncService.pushUrineColorLogsForSyncDomain(),
    ], eagerError: false);
  }

  @override
  Future<void> restore() async {
    await Future.wait([
      _syncService.restoreWeightLogsForSyncDomain(),
      _syncService.restoreMeasurementsForSyncDomain(),
      _syncService.restoreSleepLogsForSyncDomain(),
      _syncService.restoreStepsLogsForSyncDomain(),
      // Note: no restoreUrineColorLogs — urine color is reconstructed
      // from water_logs rows on restore.
    ], eagerError: false);
  }
}
