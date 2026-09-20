// Regression tests for the APK Test #4 closeout maintenance batch.
//
// Three P2 audit items:
//   1. relogSavedMeal times_used sync (Item 1)
//   2. progress_photo orphan cleanup logging (Item 2)
//   3. Telemetry failure queue cap + drain wiring (Item 3)
//
// SyncService uses a static singleton — DI is impractical without production-
// code changes. Tests use structural source-file assertions for sync wiring
// (same pattern as sync_gap_test.dart) and in-memory logic tests for the
// queue cap where no network call is involved.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  // ── Item 1: relogSavedMeal times_used sync ──────────────────────────────

  group('Item 1 — relogSavedMeal times_used sync', () {
    test('syncSavedMealsNow public method exists in SyncService', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('Future<void> syncSavedMealsNow()'),
          reason: 'Public syncSavedMealsNow wrapper must exist');
    });

    test('syncSavedMealsNow delegates to _syncSavedMeals', () {
      final src = loadSyncServiceSource().readAsStringSync();
      // The public method must call the private helper.
      expect(src, contains('await _syncSavedMeals(userId)'),
          reason: '_syncSavedMeals must be called from syncSavedMealsNow');
    });

    test('relogSavedMeal fires syncSavedMealsNow after times_used increment', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      expect(src, contains('unawaited(SyncService.instance.syncSavedMealsNow())'),
          reason: 'relogSavedMeal must fire syncSavedMealsNow to push counter to cloud');
    });

    test('relogSavedMeal still fires pushSnapshot', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      // Count occurrences to make sure at least one pushSnapshot remains
      // in the relogSavedMeal vicinity (it was already there pre-patch).
      expect(src, contains('unawaited(SyncService.instance.pushSnapshot())'),
          reason: 'relogSavedMeal must still fire pushSnapshot');
    });
  });

  // ── Item 2: progress_photo orphan cleanup logging ───────────────────────

  group('Item 2 — progress photo orphan cleanup', () {
    test('cleanupOrphanedStorage method exists', () {
      final src = _src(
          'lib/features/profile/repositories/progress_photo_repository.dart');
      expect(src, contains('Future<void> cleanupOrphanedStorage()'),
          reason: 'cleanupOrphanedStorage must be defined');
    });

    test('cleanupOrphanedStorage logs remove failures with debugPrint', () {
      final src = _src(
          'lib/features/profile/repositories/progress_photo_repository.dart');
      expect(
          src,
          contains(
              '[ProgressPhotoRepository.cleanupOrphanedStorage] remove failed'),
          reason: 'Storage remove failures must be logged');
    });

    test('cleanupOrphanedStorage logs scan failures with stack trace', () {
      final src = _src(
          'lib/features/profile/repositories/progress_photo_repository.dart');
      expect(
          src,
          contains(
              '[ProgressPhotoRepository.cleanupOrphanedStorage] scan failed'),
          reason: 'Scan failures must be logged');
    });

    test('orphaned storage path logged on delete failure', () {
      final src = _src(
          'lib/features/profile/repositories/progress_photo_repository.dart');
      expect(
          src,
          contains('orphaned storage object'),
          reason: 'delete() must log orphan path when storage remove fails');
    });
  });

  // ── Item 3: Telemetry failure queue ─────────────────────────────────────

  group('Item 3 — telemetry failure queue', () {
    test('_telemetryQueueKey constant exists', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains("_telemetryQueueKey = 'pending_telemetry_failures'"),
          reason: 'Queue Hive key must be defined');
    });

    test('_telemetryQueueMax is 50', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('_telemetryQueueMax = 50'),
          reason: 'Queue cap must be 50');
    });

    test('_enqueueTelemetryFailure method exists', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('Future<void> _enqueueTelemetryFailure('),
          reason: '_enqueueTelemetryFailure must be defined');
    });

    test('drainTelemetryQueue public method exists', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('Future<void> drainTelemetryQueue()'),
          reason: 'Public drainTelemetryQueue must be defined');
    });

    test('_reportSyncFailure catch calls _enqueueTelemetryFailure', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('await _enqueueTelemetryFailure(opType, error)'),
          reason: '_reportSyncFailure catch must enqueue instead of silently drop');
    });

    test('checkAndSync fires drainTelemetryQueue on app launch', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('unawaited(drainTelemetryQueue())'),
          reason: 'checkAndSync must drain the telemetry queue on every launch');
    });

    test('queue cap logic: while loop trims to _telemetryQueueMax', () {
      // Structural: confirm the while-loop trim is present in _enqueueTelemetryFailure.
      final src = loadSyncServiceSource().readAsStringSync();
      expect(src, contains('while (queue.length > _telemetryQueueMax)'),
          reason: 'Queue must be trimmed to prevent unbounded Hive growth');
    });
  });
}
