part of '../sync_service.dart';

/// Sync + restore for health-domain Hive surfaces: weight, body
/// measurements, sleep, daily steps, urine color. All reads/writes
/// route through `_hive.healthBox`. Cloud tables: weight_logs,
/// body_measurements, sleep_logs, daily_steps, water_logs (urine
/// color is merged onto water_logs rows by date — health_metrics
/// table doesn't exist).
extension SyncServiceHealth on SyncService {
  // ── Public entry points (called from biometric provider) ────

  /// Immediately pushes Hive weight logs to Supabase. Safe to call
  /// fire-and-forget from anywhere — catches its own errors.
  ///
  /// Added 2026-04-18: the weight-log save path (home_provider.logWeight)
  /// now fires this directly so the cloud `weight_logs` table fills in
  /// seconds instead of waiting for the next weekly full sync.
  Future<void> syncWeightNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncWeightLogs(userId);
    } catch (e, st) {
      debugPrint('[SyncService.syncWeightNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_weight_now'));
      try {
        await _reportSyncFailure(opType: 'sync_weight_now', error: e);
      } catch (_) {}
    }
  }

  /// Pushes recent sleep entries to Supabase `sleep_logs`. Fire-and-forget per
  /// CLAUDE.md §15. Handles two Hive storage patterns:
  ///   • Per-day keys  `sleep_log_YYYY-MM-DD`  (standard log path)
  ///   • List key      `sleep_logs`             (conversational AI tool path)
  Future<void> syncSleepNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      // Handle per-day keys (standard path) via existing helper
      await _syncSleepLogs(userId);
      // Handle list key written by conversational_log_handler._logSleep
      final healthBox = _hive.healthBox;
      final listRaw = healthBox.get('sleep_logs');
      if (listRaw is! List || listRaw.isEmpty) return;
      for (final item in listRaw) {
        if (item is! Map) continue;
        final log = Map<String, dynamic>.from(item);
        final dateStr = log['date'] as String?;
        if (dateStr == null) continue;
        final hours = (log['duration_hrs'] as num?)?.toDouble() ??
            (log['sleep_hours'] as num?)?.toDouble() ??
            (log['hours'] as num?)?.toDouble();
        if (hours == null) continue;
        try {
          await _supabase.client.from('sleep_logs').upsert({
            'id': SyncService._deterministicId('sleep_logs_$dateStr'),
            'user_id': userId,
            'date': dateStr,
            'duration_hrs': hours,
            if (log['quality'] != null) 'quality': log['quality'],
            'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (e, st) {
          debugPrint('[SyncService.syncSleepNow] list-item $dateStr: $e');
          // audit-2026-05-11 H-42 — telemetry pair.
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'sync_service_for_4'));
          try {
            await _reportSyncFailure(opType: 'upsert_sleep_log_chat', error: e);
          } catch (_) {}
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService.syncSleepNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_7'));
      try {
        await _reportSyncFailure(opType: 'sync_sleep_now', error: e);
      } catch (_) {}
    }
  }

  /// Pushes recent body measurements to Supabase `body_measurements`.
  /// Fire-and-forget per CLAUDE.md §15. Delegates to existing `_syncMeasurements`
  /// which reads `measurement_YYYY-MM-DD` keys — the same pattern written by
  /// conversational_log_handler._logMeasurement.
  Future<void> syncMeasurementsNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncMeasurements(userId);
    } catch (e, st) {
      debugPrint('[SyncService.syncMeasurementsNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_measurements_now'));
      try {
        await _reportSyncFailure(opType: 'sync_measurements_now', error: e);
      } catch (_) {}
    }
  }

  // ── Private push helpers ────────────────────────────────────

  Future<void> _syncWeightLogs(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'weight_2026-04-07', NOT a single list key.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('weight_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'weight_log') continue;
      try {
        await _supabase.client.from('weight_logs').upsert({
          'id': SyncService._deterministicId(key),
          'user_id': userId,
          'date': log['date'],
          'weight_kg': log['weight_kg'],
          'notes': log['notes'],
          'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e, st) {
        debugPrint('[SyncService._syncWeightLogs] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_5'));
        try {
          await _reportSyncFailure(opType: 'upsert_weight_log', error: e);
        } catch (_) {}
      }
    }
  }

  Future<void> _syncMeasurements(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'measurement_2026-04-07'.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('measurement_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      try {
        await _supabase.client.from('body_measurements').upsert({
          'id': SyncService._deterministicId(key),
          'user_id': userId,
          'date': log['date'],
          'chest': log['chest'],
          'waist': log['waist'],
          'hips': log['hips'],
          'arms': log['arms'],
          'notes': log['notes'],
          'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        // E.14.A · audit-2026-05-16 — success-path emission.
        unawaited(ErrorTelemetry.logEvent('upsert_body_measurements_success',
            message: 'date=${log['date']}'));
      } catch (e, st) {
        debugPrint('[SyncService._syncMeasurements] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_6'));
        try {
          await _reportSyncFailure(opType: 'upsert_body_measurement', error: e);
        } catch (_) {}
      }
    }
  }

  Future<void> _syncSleepLogs(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'sleep_log_2026-04-07'.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('sleep_log_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      try {
        await _supabase.client.from('sleep_logs').upsert({
          'id': SyncService._deterministicId(key),
          'user_id': userId,
          'date': log['date'],
          'duration_hrs': log['duration_hrs'],
          'quality': log['quality'],
          'bed_time': log['bed_time'],
          'wake_time': log['wake_time'],
          'notes': log['notes'],
          'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        // E.14.A · audit-2026-05-16 — success-path emission.
        unawaited(ErrorTelemetry.logEvent('upsert_sleep_logs_success',
            message: 'date=${log['date']}'));
      } catch (e, st) {
        debugPrint('[SyncService._syncSleepLogs] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_7'));
        try {
          await _reportSyncFailure(opType: 'upsert_sleep_log', error: e);
        } catch (_) {}
      }
    }
  }

  /// F20 · Pushes daily step totals to Supabase `daily_steps`.
  Future<void> _syncStepsLogs(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'step_2026-04-07' with
    // {type:'step_log', date, steps, source}.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('step_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'step_log') continue;
      final date = log['date'] as String?;
      final steps = (log['steps'] as num?)?.toInt();
      if (date == null || steps == null) continue;
      try {
        await _supabase.client.from('daily_steps').upsert({
          'user_id': userId,
          'date': date,
          'steps': steps,
          'source': log['source'] ?? 'health_connect',
          'synced_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date');
      } catch (e, st) {
        debugPrint('[SyncService._syncStepsLogs] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_8'));
        try {
          await _reportSyncFailure(opType: 'upsert_daily_steps', error: e);
        } catch (_) {}
      }
    }
  }

  Future<void> _syncUrineColorLogs(String userId) async {
    // Urine color data is now merged into the water_logs table
    // (health_metrics table does not exist).
    final healthBox = _hive.healthBox;
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('urine_color_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      if (date == null) continue;
      try {
        await _supabase.client.from('water_logs').upsert({
          'user_id': userId,
          'date': date,
          'urine_color': (log['index'] as int?) ?? -1,
          'urine_status': log['label'] ?? 'unknown',
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date');
      } catch (e, st) {
        debugPrint('[SyncService._syncUrineColorLogs] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_9'));
        try {
          await _reportSyncFailure(opType: 'upsert_urine_color_log', error: e);
        } catch (_) {}
      }
    }
  }

  // ── Private pull helpers ────────────────────────────────────

  Future<void> _restoreWeightLogs(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'weight_logs', userId,
        dateColumn: 'created_at', since: since, orderBy: 'created_at',
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String? ?? '';
        final key = 'weight_$date';
        if (_hive.healthBox.get(key) != null) continue;
        await _hive.healthBox.put(key, {
          'type': 'weight_log',
          'date': date,
          'weight_kg': map['weight_kg'],
          'created_at': map['created_at'],
          'source': 'cloud_restore',
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWeightLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_17'));
      try {
        await _reportSyncFailure(opType: 'restore_weight_logs', error: e);
      } catch (_) {}
    }
  }

  Future<void> _restoreMeasurements(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'body_measurements', userId,
        dateColumn: 'created_at', since: since, orderBy: 'created_at',
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String? ?? '';
        final key = 'measurement_$date';
        if (_hive.healthBox.get(key) != null) continue;
        await _hive.healthBox.put(key, {
          ...map,
          'source': 'cloud_restore',
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreMeasurements] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_18'));
      try {
        await _reportSyncFailure(opType: 'restore_measurements', error: e);
      } catch (_) {}
    }
  }

  Future<void> _restoreSleepLogs(String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('sleep_logs')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since);

      if (rows.isEmpty) return;

      final healthBox = _hive.healthBox;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String?;
        if (date == null) continue;
        final key = 'sleep_log_$date';
        if (healthBox.get(key) != null) continue; // Don't overwrite local data
        await healthBox.put(key, {
          ...map,
          'source': 'cloud_restore',
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreSleepLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_19'));
      try {
        await _reportSyncFailure(opType: 'restore_sleep_logs', error: e);
      } catch (_) {}
    }
  }

  /// F20 · Restore daily step totals from Supabase into healthBox.
  Future<void> _restoreStepsLogs(String userId, String since) async {
    try {
      final sinceDate = since.length >= 10 ? since.substring(0, 10) : since;
      final rows = await _fetchAllRows(
        'daily_steps', userId,
        dateColumn: 'date', since: sinceDate, orderBy: 'date',
      );
      if (rows.isEmpty) return;
      final healthBox = _hive.healthBox;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String?;
        final steps = (map['steps'] as num?)?.toInt();
        if (date == null || steps == null) continue;
        final key = 'step_$date';
        // Only restore if local doesn't already have a step entry for this
        // date (covers the case where Health Connect will repopulate on
        // device-local sync).
        if (healthBox.get(key) != null) continue;
        await healthBox.put(key, {
          'type': 'step_log',
          'date': date,
          'steps': steps,
          'source': map['source'] ?? 'cloud_restore',
          'created_at': map['created_at'],
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreStepsLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_20'));
      try {
        await _reportSyncFailure(opType: 'restore_steps_logs', error: e);
      } catch (_) {}
    }
  }

  // ── SyncDomain public forwarders for health helpers (A6 migration) ──
  // See lib/core/services/sync_flags.dart for the per-domain flag gate.

  static const String _kSyncDomainRestoreSinceHealth = '2020-01-01T00:00:00Z';

  Future<void> pushWeightLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncWeightLogs(userId);
  }

  Future<void> restoreWeightLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreWeightLogs(userId, since ?? _kSyncDomainRestoreSinceHealth);
  }

  Future<void> pushMeasurementsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncMeasurements(userId);
  }

  Future<void> restoreMeasurementsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreMeasurements(userId, since ?? _kSyncDomainRestoreSinceHealth);
  }

  Future<void> pushSleepLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncSleepLogs(userId);
  }

  Future<void> restoreSleepLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreSleepLogs(userId, since ?? _kSyncDomainRestoreSinceHealth);
  }

  Future<void> pushStepsLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncStepsLogs(userId);
  }

  Future<void> restoreStepsLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreStepsLogs(userId, since ?? _kSyncDomainRestoreSinceHealth);
  }

  Future<void> pushUrineColorLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncUrineColorLogs(userId);
  }
}
