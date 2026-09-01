import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

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

  /// WARNING: Sleep is tracked SEPARATELY from [_types] on purpose. Health
  /// Connect treats sleep as its own permission; folding it into [_types] would
  /// make `hasPermissions(_types)` false for anyone who denies sleep, and
  /// `_syncToHiveLocked` aborts the WHOLE sync on that -- silently breaking
  /// steps + weight for existing users. Sleep must fail soft, both ways.
  ///
  /// WARNING: SLEEP_SESSION, never SLEEP_ASLEEP. The plugin returns the whole
  /// session only for SLEEP_SESSION; every other sleep type matches individual
  /// STAGES, so a stageless session (manual entry, Google Fit import) or a
  /// granular tracker (light/deep/REM) yields ZERO points. Verified against
  /// health-13.3.1 HealthDataReader.handleSleepData + mapSleepStageToType.
  /// (iOS has no SLEEP_SESSION in dataTypeKeysIOS -- revisit at an iOS port.)
  static const _sleepTypes = [HealthDataType.SLEEP_SESSION];

  /// Derived, never hardcoded: the plugin throws ArgumentError when the
  /// permissions list length differs from the types list length.
  static final _sleepPermissions =
      _sleepTypes.map((_) => HealthDataAccess.READ).toList();

  bool _sleepPermissionGranted = false;

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

  /// Total slept hours for LAST NIGHT, or null when unavailable.
  ///
  /// WARNING: NEVER requests permission -- it only READS an already-granted
  /// one. Requesting here would fire a Health Connect dialog at cold launch
  /// with no user gesture, and re-fire every launch (the granted flag is
  /// in-memory on a singleton, so it resets each cold start); Android throttles
  /// repeated requests and then silently refuses, burning the grant. The ASK
  /// lives on an explicit user action -- see [requestSleepPermission].
  Future<double?> fetchSleepHoursLastNight() async {
    if (kIsWeb) return null; // native-only, mirrors steps/weight
    try {
      // Idempotent and dialog-free. Needed because this runs ABOVE the
      // steps/weight permission block, which is the only other place the
      // plugin gets configured.
      _ensureConfigured();
      if (!_sleepPermissionGranted) {
        final has = await _health!
            .hasPermissions(_sleepTypes, permissions: _sleepPermissions);
        _sleepPermissionGranted = has == true;
        if (!_sleepPermissionGranted) {
          debugPrint(
              '[HealthSync] sleep permission absent - skipping (no prompt)');
          return null;
        }
      }
      // 18:00 yesterday -> now, with each interval CLAMPED to the window so a
      // session starting before it is not counted whole.
      final now = DateTime.now();
      final windowStart = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(hours: 6));
      final points = await _health!.getHealthDataFromTypes(
        startTime: windowStart,
        endTime: now,
        types: _sleepTypes,
      );
      if (points.isEmpty) return null;
      var minutes = 0.0;
      for (final pt in points) {
        final from =
            pt.dateFrom.isBefore(windowStart) ? windowStart : pt.dateFrom;
        final to = pt.dateTo.isAfter(now) ? now : pt.dateTo;
        final mins = to.difference(from).inMinutes;
        if (mins > 0) minutes += mins.toDouble();
      }
      if (minutes <= 0) return null;
      return minutes / 60.0;
    } catch (e, st) {
      debugPrint('[HealthSync] fetchSleepHoursLastNight error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_fetch_sleep'));
      return null;
    }
  }

  /// Whether a Health-Connect sleep reading should be written for today.
  ///
  /// Pure so the decision is testable and mutation-provable on its own -- the
  /// enclosing sync method needs a live plugin and cannot be exercised in this
  /// suite. A manual / AI-coach entry ALWAYS wins: [existingRow] non-null means
  /// somebody already logged today and the sync must not overwrite them.
  static bool shouldWriteSyncedSleep(double? hours, Object? existingRow) =>
      hours != null && hours > 0 && existingRow == null;

  /// Fetches sleep ONLY, without touching the steps/weight permission path.
  ///
  /// WARNING: do NOT call syncToHive() for a sleep-only user action. That path
  /// falls through to _checkPermissionsQuietly()/requestPermissions(), which
  /// shows the full native STEPS+WEIGHT consent dialog -- a dialog with no
  /// relationship to what the user tapped -- and can write step/weight rows
  /// while health_sync_enabled is still false. The mirror of "a steps denial
  /// must not kill sleep" is "a sleep-only action must not reach steps".
  Future<bool> syncSleepOnly() async {
    if (kIsWeb) return false;
    try {
      final hours = await fetchSleepHoursLastNight();
      final hive = HiveService.instance;
      final todayStr = istTodayStr();
      if (!shouldWriteSyncedSleep(
          hours, hive.healthBox.get('sleep_log_$todayStr'))) {
        return false;
      }
      await HealthWriteService.instance.logSleep(
        date: nowWall(),
        hours: hours!,
        quality: 'auto',
        source: WriteSource.healthConnect,
      );
      debugPrint('[HealthSync] synced sleep (sleep-only): ${hours}h for $todayStr');
      return true;
    } catch (e, st) {
      debugPrint('[HealthSync] syncSleepOnly error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_sleep_only'));
      return false;
    }
  }

  /// Requests the sleep permission. Call ONLY from an explicit user action
  /// (the Profile health-sync toggle, or the readiness sheet's sync nudge).
  Future<bool> requestSleepPermission() async {
    if (kIsWeb) return false;
    try {
      _ensureConfigured();
      _sleepPermissionGranted = await _health!
          .requestAuthorization(_sleepTypes, permissions: _sleepPermissions);
      debugPrint(
          '[HealthSync] sleep permission granted=$_sleepPermissionGranted');
      return _sleepPermissionGranted;
    } catch (e, st) {
      debugPrint('[HealthSync] requestSleepPermission error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_request_sleep_permission'));
      return false;
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

    // Declared ABOVE the steps/weight permission gate so the sleep block below
    // can run regardless of it -- the two tracks must not be able to disable
    // each other in EITHER direction.
    final hive = HiveService.instance;
    final now = DateTime.now();
    final todayStr = istTodayStr();

    // -- Sleep --------------------------------------------------
    // Feeds the readiness check-in's SLEEP axis. Runs BEFORE the steps/weight
    // gate: a steps denial must not kill sleep, just as a sleep denial must not
    // kill steps. A manual / AI-coach entry ALWAYS wins, matching Weight below.
    final sleepHours = await fetchSleepHoursLastNight();
    if (shouldWriteSyncedSleep(
        sleepHours, hive.healthBox.get('sleep_log_$todayStr'))) {
      // Through the WriteService, not a raw put: it stamps `duration_hrs`
      // alongside `sleep_hours` (the cloud push reads duration_hrs with NO
      // fallback, so a raw put would upsert NULL over a good row), takes the
      // per-day lock, and fires the cloud sync.
      await HealthWriteService.instance.logSleep(
        // nowWall(), NOT `now` (raw DateTime.now()): the guard above keys on
        // istTodayStr(), which honours the dev-panel test clock. Passing the
        // raw clock lets the guard check one date and the write land on
        // another under time-travel -- which is exactly the surface used to
        // verify this feature on-device.
        date: nowWall(),
        hours: sleepHours!,
        quality: 'auto',
        source: WriteSource.healthConnect,
      );
      debugPrint('[HealthSync] synced sleep: ${sleepHours}h for $todayStr');
    }

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
