import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

/// Wraps the `health` package to sync data from Google Fit / Health Connect
/// (Android) or Apple HealthKit (iOS) into local Hive storage.
///
/// Data flows: Health Connect API -> Health package -> Hive healthBox
/// The BiometricNotifier reads from healthBox to display in the UI.
class HealthSyncService {
  HealthSyncService._();
  static final HealthSyncService instance = HealthSyncService._();

  Health? _health;
  bool _permissionsGranted = false;

  /// Whether the last [syncToHive] call wrote new step/weight data.
  /// Checked by callers that need to invalidate UI providers afterward.
  bool get lastSyncWroteData => _lastSyncWroteData;
  bool _lastSyncWroteData = false;

  /// Supported data types to read from Health Connect / HealthKit.
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.WEIGHT,
  ];

  static final _permissions = _types.map((_) => HealthDataAccess.READ).toList();

  /// Ensure the Health plugin is configured. Safe to call multiple times.
  /// On cold start, [_health] is null — this re-creates and configures it
  /// without re-triggering the permission dialog.
  void _ensureConfigured() {
    if (_health != null) return;
    _health = Health();
    _health!.configure();
    debugPrint('[HealthSync] Health plugin configured');
  }

  /// Request Health Connect / HealthKit permissions.
  /// Returns true if all requested permissions are granted.
  Future<bool> requestPermissions() async {
    // Unit 3 obs 2b: Health Connect / HealthKit have no web binding — calling
    // _ensureConfigured() (native Health()) on web dead-ends the CONNECT flow.
    if (kIsWeb) return false;
    try {
      _ensureConfigured();
      _permissionsGranted = await _health!.requestAuthorization(
        _types,
        permissions: _permissions,
      );
      debugPrint('[HealthSync] permissions granted: $_permissionsGranted');
      return _permissionsGranted;
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[HealthSync] requestPermissions error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_request_permissions'));
      return false;
    }
  }

  /// Check if permissions were already granted (without showing a dialog).
  /// Useful on app relaunch to avoid re-prompting the user.
  Future<bool> _checkPermissionsQuietly() async {
    try {
      _ensureConfigured();
      final hasPerms = await _health!.hasPermissions(
        _types,
        permissions: _permissions,
      );
      // hasPermissions returns null when the status is unknown (e.g., Health
      // Connect not installed). Treat null as false.
      _permissionsGranted = hasPerms == true;
      debugPrint('[HealthSync] quiet permission check: $_permissionsGranted');
      return _permissionsGranted;
    } catch (e, st) {
      debugPrint('[HealthSync] quiet permission check error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_quiet_permission_check'));
      return false;
    }
  }

  /// Fetch total steps for today from Health Connect.
  Future<int?> fetchStepsToday() async {
    if (kIsWeb) return null; // Unit 3 obs 2b — native-only
    if (_health == null || !_permissionsGranted) {
      debugPrint('[HealthSync] fetchStepsToday skipped: health=${_health != null}, perms=$_permissionsGranted');
      return null;
    }
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await _health!.getTotalStepsInInterval(midnight, now);
      debugPrint('[HealthSync] fetchStepsToday: $steps (midnight=$midnight, now=$now)');
      return steps;
    } catch (e, st) {
      debugPrint('[HealthSync] fetchStepsToday error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_fetch_steps_today'));
      return null;
    }
  }

  /// Fetch the latest weight entry from the last 7 days.
  Future<double?> fetchLatestWeight() async {
    if (kIsWeb) return null; // Unit 3 obs 2b — native-only
    if (_health == null || !_permissionsGranted) return null;
    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));

      final data = await _health!.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: weekAgo,
        endTime: now,
      );

      if (data.isEmpty) return null;

      // Sort by date descending and take the latest
      data.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final value = data.first.value;
      if (value is NumericHealthValue) {
        return value.numericValue.toDouble();
      }
      return null;
    } catch (e, st) {
      debugPrint('[HealthSync] fetchLatestWeight error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_fetch_latest_weight'));
      return null;
    }
  }

  /// In-flight dedup guard (Unit 3a, OI-45 finding 4). [syncToHive] is
  /// called both on app launch AND when the health-sync toggle is turned on
  /// — on a slow device these can genuinely overlap (a launch-time sync
  /// still awaiting [fetchLatestWeight] when the user opens Settings and
  /// re-triggers via the toggle). The weight write below guards with a
  /// plain `existing == null` read-then-write, no lock — safe within ONE
  /// call (nothing else runs between the read and the `put`), but not
  /// across two independently-dispatched calls, where both can pass their
  /// own read before either reaches its write. A second concurrent caller
  /// now awaits the FIRST call's in-flight future instead of starting an
  /// independent, overlapping run.
  Future<void>? _syncInFlight;

  Future<void> syncToHive() async {
    final inFlight = _syncInFlight;
    if (inFlight != null) return inFlight;
    final completer = Completer<void>();
    _syncInFlight = completer.future;
    // Round-2 review P1: in the common case (no concurrent follower ever
    // calls syncToHive() while this is in flight), nobody ever attaches a
    // listener to completer.future — the leader observes the real
    // success/failure via the try/catch below instead, through a SEPARATE
    // Future (this async function's own). An unlistened Future that later
    // has completeError() called on it is treated by Dart as an unhandled
    // error and reported a SECOND time to the current Zone (verified
    // empirically: runZonedGuarded's onError fires a duplicate for every
    // ordinary, non-concurrent sync failure) — in this app that means a
    // spurious extra FATAL Crashlytics report (main.dart's zone forwards to
    // FlutterError.onError -> recordFlutterFatalError) on top of whatever
    // the real caller already does. Attaching a no-op listener immediately
    // silences that duplicate report; Future listeners fan out rather than
    // consume, so a REAL follower awaiting this SAME future via
    // _syncInFlight still independently observes the real outcome below.
    unawaited(completer.future.catchError((_) {}));
    try {
      await _syncToHiveLocked();
      completer.complete();
    } catch (e, st) {
      // Round-1 review P2: completer.complete() was previously called
      // unconditionally in `finally`, regardless of whether the sync
      // succeeded. A deduped follower caller (one that got `return
      // inFlight` above) would then silently observe SUCCESS even when the
      // leader's sync actually threw — e.g. the Settings toggle handler
      // (biometric_sync_card.dart's onTap) landing behind an in-flight
      // launch-time sync that fails would believe it succeeded and never
      // record telemetry. Propagate the SAME error to every follower via
      // completeError, and rethrow so the leader's own caller sees it too.
      completer.completeError(e, st);
      rethrow;
    } finally {
      _syncInFlight = null;
    }
  }

  /// Fetches all supported health data and writes to Hive healthBox.
  /// Called on app launch (if enabled) and when the toggle is turned on.
  ///
  /// On cold launch the singleton fields [_health] and [_permissionsGranted]
  /// are reset. This method first tries a quiet permission check (no dialog)
  /// to recover previously-granted access. If that fails it falls back to
  /// [requestPermissions] which may show the system dialog.
  ///
  /// Callers MUST go through the public [syncToHive] wrapper, not this
  /// method directly — the wrapper is what closes the double-invocation gap.
  Future<void> _syncToHiveLocked() async {
    if (kIsWeb) return; // Unit 3 obs 2b — native-only; no-op on web
    _lastSyncWroteData = false;

    if (_health == null || !_permissionsGranted) {
      // First try the quiet path (no dialog). On a relaunch where the user
      // previously granted access, this will succeed silently.
      final quietOk = await _checkPermissionsQuietly();
      if (!quietOk) {
        // Fall back to the full request (may show system dialog).
        final granted = await requestPermissions();
        if (!granted) {
          debugPrint('[HealthSync] syncToHive aborted: permissions not granted');
          return;
        }
      }
    }

    final hive = HiveService.instance;
    final now = DateTime.now();
    final todayStr = istTodayStr();

    // ── Steps ────────────────────────────────────────────────
    final steps = await fetchStepsToday();
    if (steps != null) {
      // Write as a proper map entry so TodayStepsNotifier can find it
      // (it scans healthBox.values for maps with type == 'step_log').
      final stepKey = 'step_$todayStr';
      await hive.healthBox.put(stepKey, {
        'type': 'step_log',
        'date': todayStr,
        'steps': steps,
        'source': 'health_connect',
        'created_at': now.toUtc().toIso8601String(),
      });
      // Also keep legacy keys for backward compatibility
      await hive.healthBox.put('steps_today', steps);
      await hive.healthBox.put('steps_date', todayStr);
      _lastSyncWroteData = true;
      debugPrint('[HealthSync] synced steps: $steps for $todayStr');
    } else {
      debugPrint('[HealthSync] no steps data returned from Health Connect');
    }

    // ── Weight ───────────────────────────────────────────────
    final weight = await fetchLatestWeight();
    if (weight != null) {
      final weightKey = 'weight_$todayStr';
      // Only write if no manual entry exists for today
      final existing = hive.healthBox.get(weightKey);
      if (existing == null) {
        await hive.healthBox.put(weightKey, {
          'type': 'weight_log',
          'date': todayStr,
          'weight_kg': weight,
          'source': 'health_connect',
          'created_at': now.toUtc().toIso8601String(),
        });
        _lastSyncWroteData = true;
        debugPrint('[HealthSync] synced weight: $weight kg for $todayStr');
      } else {
        debugPrint('[HealthSync] weight entry already exists for $todayStr, skipping');
      }
    }
  }

  /// Whether health sync is enabled in user config.
  static bool isEnabled() {
    return HiveService.instance.configBox.get('health_sync_enabled', defaultValue: false) as bool;
  }
}
