import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

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

  /// Supported data types to read from Health Connect / HealthKit.
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.WEIGHT,
  ];

  static final _permissions = _types.map((_) => HealthDataAccess.READ).toList();

  /// Request Health Connect / HealthKit permissions.
  /// Returns true if all requested permissions are granted.
  Future<bool> requestPermissions() async {
    try {
      _health = Health();
      _health!.configure();
      _permissionsGranted = await _health!.requestAuthorization(
        _types,
        permissions: _permissions,
      );
      debugPrint('[HealthSyncService] permissions granted: $_permissionsGranted');
      return _permissionsGranted;
    } catch (e) {
      debugPrint('[HealthSyncService.requestPermissions] $e');
      return false;
    }
  }

  /// Fetch total steps for today from Health Connect.
  Future<int?> fetchStepsToday() async {
    if (_health == null || !_permissionsGranted) return null;
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await _health!.getTotalStepsInInterval(midnight, now);
      return steps;
    } catch (e) {
      debugPrint('[HealthSyncService.fetchStepsToday] $e');
      return null;
    }
  }

  /// Fetch the latest weight entry from the last 7 days.
  Future<double?> fetchLatestWeight() async {
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
    } catch (e) {
      debugPrint('[HealthSyncService.fetchLatestWeight] $e');
      return null;
    }
  }

  /// Fetches all supported health data and writes to Hive healthBox.
  /// Called on app launch (if enabled) and when the toggle is turned on.
  Future<void> syncToHive() async {
    if (_health == null || !_permissionsGranted) {
      final granted = await requestPermissions();
      if (!granted) return;
    }

    final hive = HiveService.instance;
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

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
        'created_at': now.toIso8601String(),
      });
      // Also keep legacy keys for backward compatibility
      await hive.healthBox.put('steps_today', steps);
      await hive.healthBox.put('steps_date', todayStr);
      debugPrint('[HealthSyncService] synced steps: $steps');
    }

    // ── Weight ───────────────────────────────────────────────
    final weight = await fetchLatestWeight();
    if (weight != null) {
      final weightKey = 'weight_$todayStr';
      // Only write if no manual entry exists for today
      if (hive.healthBox.get(weightKey) == null) {
        await hive.healthBox.put(weightKey, {
          'type': 'weight_log',
          'date': todayStr,
          'weight_kg': weight,
          'source': 'health_connect',
          'created_at': now.toIso8601String(),
        });
        debugPrint('[HealthSyncService] synced weight: $weight kg');
      }
    }
  }

  /// Whether health sync is enabled in user config.
  static bool isEnabled() {
    return HiveService.instance.configBox.get('health_sync_enabled', defaultValue: false) as bool;
  }
}
