// lib/core/services/sync_domains/nutrition_sync_domain.dart
//
// [SyncDomain] wrapper for the nutrition part-file surfaces (audit
// 2026-05-20 / A6 — B5 D7-D8 batch).
//
// Wraps `lib/core/services/sync/sync_nutrition.dart` via the public
// forwarders on `SyncServiceNutrition`.
//
// Sub-surfaces:
//   - nutrition_logs : _syncNutritionLogs ↔ _restoreNutritionLogs
//   - water_logs     : _syncWaterLogs     ↔ _restoreWaterLogs
//   - saved_meals    : _syncSavedMeals    ↔ _restoreSavedMeals
//
// NOT YET WIRED into the SyncService fan-out — gated behind
// `SyncFlags.useDomainFor('nutrition')` (default FALSE).

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class NutritionSyncDomain extends SyncDomainBase {
  NutritionSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'nutrition';

  @override
  Future<void> push() async {
    await Future.wait([
      _syncService.pushNutritionLogsForSyncDomain(),
      _syncService.pushWaterLogsForSyncDomain(),
      _syncService.pushSavedMealsForSyncDomain(),
    ], eagerError: false);
  }

  @override
  Future<void> restore() async {
    await Future.wait([
      _syncService.restoreNutritionLogsForSyncDomain(),
      _syncService.restoreWaterLogsForSyncDomain(),
      _syncService.restoreSavedMealsForSyncDomain(),
    ], eagerError: false);
  }
}
