import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/ist_date.dart';
import '../utils/readiness.dart';
import 'error_telemetry.dart';
import 'hive_service.dart';
import 'sync_service.dart';
import 'write_result.dart';

/// Single canonical writer for health-domain Hive surfaces:
/// sleep / weight / body measurements / water (water_ml total override) /
/// urine color / hydration snapshot.
///
/// Mirrors `WorkoutWriteService` + `NutritionWriteService` per CLAUDE.md
/// §15 "Source of Truth Rules". Built for audit-2026-05-16 task E.7
/// (finding F-A — Health domain had no WriteService; same architectural
/// asymmetry that produced the pre-Test-#6 workout/nutrition writer/reader
/// drift class. The IST drift finding F2-R2 — sleep_log key computed from
/// device-local `DateTime.now()` — is folded into the fix: every method
/// here computes its Hive date key via `istDateStr(date)`.
///
/// Hive key shapes (kept identical to pre-existing UI writes — this is a
/// wrapper, NOT a schema change):
/// - sleep:        `sleep_log_<istDate>`         (overwrite per day)
/// - weight:       `weight_<istDate>`            (overwrite per day)
/// - measurement:  `measurement_<istDate>`       (merged map, one record per day)
/// - water:        `water_ml_<istDate>`          (int total, overwrite)
/// - urine:        `urine_color_<istDate>`       (map, overwrite)
/// - hydration:    `hydration_<istDate>`         (snapshot, overwrite)
///
/// Every method:
///   1. Validates input.
///   2. Computes `istDateStr(date)` (single source for date key).
///   3. Acquires a per-(kind, istDate) mutex so concurrent taps merge
///      rather than race (mirrors WorkoutWriteService._acquireLock).
///   4. Stamps `date`, `source` (via [WriteSource.code]), `updated_at_ms`
///      onto the output map per the Hive field-name contract.
///   5. Single `healthBox.put`.
///   6. Fires the matching `SyncService.syncXxxNow()` selectively + a
///      `pushSnapshot()` so the AI coach sees the change (fire-and-forget
///      per CLAUDE.md §15).
///   7. On exception: `ErrorTelemetry.recordNonFatal` + `_reportSyncFailure`
///      with `op_type` `upsert_<kind>_log`.
///   8. Returns a [WriteResult] keyed by the Hive entry.
class HealthWriteService {
  HealthWriteService._();
  static final HealthWriteService instance = HealthWriteService._();

  /// Per-(kind, date) mutex. Key format: `<istDateStr>::<kind>`.
  final Map<String, Completer<void>> _locks = {};

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  /// Manually logs sleep for the IST date containing [date].
  ///
  /// Closes audit-2026-05-16 finding F2-R2: pre-fix, the only writer for
  /// the `sleep_log_*` key was `BiometricNotifier.logSleep` which used
  /// `now.year-now.month-now.day` (device-local). At IST 00:00–05:30 the
  /// device-local string was the prior UTC day → IST sleep readers
  /// missed the entry until the next launch's sync. Going through this
  /// method forces `istDateStr` so the date key always matches IST
  /// readers.
  Future<WriteResult> logSleep({
    required DateTime date,
    required double hours,
    required String quality,
    required WriteSource source,
  }) async {
    if (hours <= 0 || hours > 24) {
      return WriteResult.fail('logSleep: hours must be in (0, 24]');
    }
    final dateStr = istDateStr(date);
    final key = 'sleep_log_$dateStr';
    final lockKey = '$dateStr::sleep';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final payload = <String, dynamic>{
        'date': dateStr,
        'sleep_hours': hours,
        // Legacy alias kept for sync_health.dart pre-existing readers that
        // accept either field name on the list-key path. Same value.
        'duration_hrs': hours,
        'quality': quality,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        'created_at': DateTime.now().toIso8601String(),
      };
      await box.put(key, payload);

      unawaited(SyncService.instance.syncSleepNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logSleep] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_log_sleep'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// ⑥ Batch 6 (W2.3) — logs the daily readiness check-in for the IST date
  /// containing [date]. One row per day (`readiness_<istDate>`, overwrite —
  /// a re-check-in on the same day replaces it). Each axis is 0 (best) /
  /// 1 (mid) / 2 (worst); `level` is denormalized (Green/Yellow/Red) for cheap
  /// trend reads. Hive-only in 6-A — the cloud push (`syncReadinessNow`) is
  /// wired in 6-C (the `readiness_daily` migration + sync). `pushSnapshot`
  /// gives the AI coach visibility per the health-write pattern.
  Future<WriteResult> logReadiness({
    required DateTime date,
    required int sleep,
    required int soreness,
    required int energy,
    required WriteSource source,
  }) async {
    final dateStr = istDateStr(date);
    final key = 'readiness_$dateStr';
    final lockKey = '$dateStr::readiness';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final level =
          readinessLevelFor(sleep: sleep, soreness: soreness, energy: energy);
      final payload = <String, dynamic>{
        'date': dateStr,
        'sleep': sleep,
        'soreness': soreness,
        'energy': energy,
        'level': level.name,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        'created_at': DateTime.now().toIso8601String(),
      };
      await box.put(key, payload);

      unawaited(SyncService.instance.syncReadinessNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logReadiness] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_log_readiness'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Logs/updates the user's bodyweight for the IST date containing [date].
  ///
  /// Single source for the `weight_<istDate>` Hive key. Caller is
  /// responsible for any companion profile mutation (the home weight tile
  /// also updates `userBox['profile']['current_weight_kg']`); this service
  /// is intentionally scoped to the health box write so callers can compose.
  Future<WriteResult> logWeight({
    required DateTime date,
    required double weightKg,
    required WriteSource source,
  }) async {
    if (weightKg <= 0 || weightKg > 500) {
      return WriteResult.fail('logWeight: weightKg out of range');
    }
    final dateStr = istDateStr(date);
    final key = 'weight_$dateStr';
    final lockKey = '$dateStr::weight';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final payload = <String, dynamic>{
        'type': 'weight_log',
        'date': dateStr,
        'weight_kg': weightKg,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        'created_at': DateTime.now().toIso8601String(),
      };
      await box.put(key, payload);

      unawaited(SyncService.instance.syncWeightNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logWeight] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_log_weight'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Logs (or merges into existing) a body measurement.
  ///
  /// Multiple measurement parts on the same date share one Hive entry
  /// keyed `measurement_<istDate>` — `partName` is folded onto the map
  /// (matches the conversational AI handler's pre-existing merge shape).
  /// Allowed parts: `waist`, `chest`, `hips`, `arms` (enforced by reader
  /// tier in `_logMeasurement`; we don't re-validate here to stay flexible
  /// for future parts).
  Future<WriteResult> logMeasurement({
    required DateTime date,
    required String partName,
    required double valueCm,
    required WriteSource source,
  }) async {
    if (partName.trim().isEmpty) {
      return WriteResult.fail('logMeasurement: partName must be non-empty');
    }
    if (valueCm <= 0) {
      return WriteResult.fail('logMeasurement: valueCm must be > 0');
    }
    final dateStr = istDateStr(date);
    final key = 'measurement_$dateStr';
    final lockKey = '$dateStr::measurement';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final existing = box.get(key);
      final record = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{
              'id': 'meas_${DateTime.now().millisecondsSinceEpoch}',
              'date': dateStr,
              'created_at': DateTime.now().toIso8601String(),
            };
      record[partName.toLowerCase()] = valueCm;
      record['source'] = source.code;
      record['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;
      record['updated_at'] = DateTime.now().toIso8601String();
      await box.put(key, record);

      unawaited(SyncService.instance.syncMeasurementsNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurement] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_log_measurement'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Overwrites the total water intake (ml) for [date].
  ///
  /// Note: this is an OVERWRITE semantic, matching the pre-existing UI
  /// pattern in `WaterIntakeNotifier.addWater` which puts the clamped
  /// running-state value back onto `water_ml_<istDate>` (the Notifier's
  /// state is the source of truth for the day; Hive mirrors it).
  Future<WriteResult> setWaterMl({
    required DateTime date,
    required int totalMl,
    required WriteSource source,
  }) async {
    if (totalMl < 0) {
      return WriteResult.fail('setWaterMl: totalMl must be >= 0');
    }
    final dateStr = istDateStr(date);
    final key = 'water_ml_$dateStr';
    final lockKey = '$dateStr::water';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      // Legacy shape: pre-existing readers expect a bare int at this key.
      // We preserve that to avoid churning every reader; metadata goes to
      // a sibling map under a `_meta` suffix only if we ever need it.
      await box.put(key, totalMl);

      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.setWaterMl] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_set_water_ml'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Logs urine color selection for [date].
  ///
  /// `color` is a free-form label (e.g. `Pale straw`, `Dark yellow`); the
  /// numeric index/source-of-truth lives in the caller's UI state. Pre-fix
  /// the writer in `UrineColorNotifier.select` carried both `index` (int)
  /// and `label` (String) — we keep both fields on the payload via the
  /// expanded sig in [logUrineWithIndex] (kept for back-compat), and
  /// expose this simpler variant as the canonical entry.
  Future<WriteResult> logUrine({
    required DateTime date,
    required String color,
    required WriteSource source,
    int? colorIndex,
  }) async {
    if (color.trim().isEmpty) {
      return WriteResult.fail('logUrine: color must be non-empty');
    }
    final dateStr = istDateStr(date);
    final key = 'urine_color_$dateStr';
    final lockKey = '$dateStr::urine';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final payload = <String, dynamic>{
        'type': 'urine_color',
        'date': dateStr,
        'index': ?colorIndex,
        'label': color,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        'recorded_at': DateTime.now().toIso8601String(),
      };
      await box.put(key, payload);

      // urine_color_<date> lives in healthBox. syncNutritionData() only pushes
      // nutrition + water_ml_ + saved_meal_ rows (its _syncWaterLogs reads ONLY
      // water_ml_ keys), so it never reached this urine row — it synced only on
      // the next FULL sync. Fire the dedicated urine push so it reaches cloud
      // per-mutation, matching sleep/weight/measurement (diagnose b6d3f9).
      unawaited(SyncService.instance.pushUrineColorLogsForSyncDomain());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logUrine] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_log_urine'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  /// Persists a hydration snapshot (water + urine index) for [date].
  ///
  /// Overwrite semantics — the snapshot represents "what the user saw
  /// when they tapped SAVE on the hydration card". `hydrationScore` is
  /// the caller-computed score (0–100); kept open for future scoring
  /// rule changes.
  Future<WriteResult> logHydration({
    required DateTime date,
    required int totalMl,
    required int hydrationScore,
    required WriteSource source,
    int? urineColorIndex,
  }) async {
    if (totalMl < 0) {
      return WriteResult.fail('logHydration: totalMl must be >= 0');
    }
    final dateStr = istDateStr(date);
    final key = 'hydration_$dateStr';
    final lockKey = '$dateStr::hydration';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final payload = <String, dynamic>{
        'date': dateStr,
        'water_ml': totalMl,
        'urine_color_index': ?urineColorIndex,
        'hydration_score': hydrationScore,
        'source': source.code,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        'saved_at': DateTime.now().toIso8601String(),
      };
      await box.put(key, payload);

      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logHydration] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_write_service_log_hydration'));
      return WriteResult.fail(e.toString());
    } finally {
      _releaseLock(lockKey, c);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Mutex helpers (mirrors WorkoutWriteService pattern)
  // ─────────────────────────────────────────────────────────────

  Future<Completer<void>> _acquireLock(String key) async {
    while (_locks.containsKey(key)) {
      try {
        await _locks[key]!.future;
      } catch (_) {/* swallowed; the holder will release */}
    }
    final c = Completer<void>();
    _locks[key] = c;
    return c;
  }

  void _releaseLock(String key, Completer<void> c) {
    _locks.remove(key);
    if (!c.isCompleted) c.complete();
  }
}
