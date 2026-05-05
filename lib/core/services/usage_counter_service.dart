import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

/// Tracks daily and monthly usage counters for gated features.
///
/// All counters are user-scoped and stored in the per-user `userBox`
/// via [MigratedKey] — sign-out → sign-up cannot reset another user's
/// counters. Call [checkAndResetCounters] on app launch to reset stale
/// counters by IST date.
class UsageCounterService {
  UsageCounterService._();
  static final UsageCounterService _instance = UsageCounterService._();
  static UsageCounterService get instance => _instance;

  // ── Hive Keys ───────────────────────────────────────────────────

  static const String _aiTextLogCountToday = 'ai_text_log_count_today';
  static const String _scanMealCountToday = 'scan_meal_count_today';
  static const String _cartAuditorCountToday = 'cart_auditor_count_today';
  static const String _lastDailyReset = 'last_daily_reset';

  // ── Feature → Counter Key Mapping ────────────────────────────────

  /// Returns the Hive key for a feature's counter.
  /// All counters are now daily (no monthly counters).
  String? _counterKey(String feature, bool isPro) {
    if (feature == AppConstants.featureAiTextLogPro) {
      return _aiTextLogCountToday;
    }
    if (feature == AppConstants.featureScanMealPro) {
      return _scanMealCountToday;
    }
    if (feature == AppConstants.featureCartAuditorPro) {
      return _cartAuditorCountToday;
    }
    return null;
  }

  /// Returns the maximum allowed uses for a feature.
  /// PRO AI text logs are unlimited (returns max int).
  int _limit(String feature, bool isPro) {
    if (feature == AppConstants.featureAiTextLogPro) {
      // PRO: unlimited AI text logs
      return isPro ? 999999 : AppConstants.freeAiTextLogsPerDay;
    }
    if (feature == AppConstants.featureScanMealPro) {
      return isPro
          ? AppConstants.proScanMealPerDay
          : AppConstants.freeScanMealPerDay;
    }
    if (feature == AppConstants.featureCartAuditorPro) {
      return isPro
          ? AppConstants.proCartAuditorPerDay
          : AppConstants.freeCartAuditorPerDay;
    }
    return 0;
  }

  // ── Public API ──────────────────────────────────────────────────

  /// Returns `true` if the user has remaining uses for [feature].
  bool canUse(String feature, bool isPro) {
    final key = _counterKey(feature, isPro);
    if (key == null) return false;

    final used = MigratedKey.readWithDefault<int>(key, 0);
    return used < _limit(feature, isPro);
  }

  /// Increments the usage counter for [feature].
  ///
  /// Call this AFTER the feature action succeeds.
  Future<void> increment(String feature, bool isPro) async {
    final key = _counterKey(feature, isPro);
    if (key == null) return;

    final current = MigratedKey.readWithDefault<int>(key, 0);
    await MigratedKey.write(key, current + 1);
  }

  /// Returns how many uses remain for [feature].
  int remaining(String feature, bool isPro) {
    final key = _counterKey(feature, isPro);
    if (key == null) return 0;

    final used = MigratedKey.readWithDefault<int>(key, 0);
    final max = _limit(feature, isPro);
    return (max - used).clamp(0, max);
  }

  /// Returns the current count for [feature].
  int used(String feature, bool isPro) {
    final key = _counterKey(feature, isPro);
    if (key == null) return 0;
    return MigratedKey.readWithDefault<int>(key, 0);
  }

  // ── Reset Logic ─────────────────────────────────────────────────

  /// Check if counters need resetting and reset them.
  ///
  /// Must be called on app launch (in main.dart after Hive init).
  /// Resets daily counters if the IST date has changed.
  Future<void> checkAndResetCounters() async {
    final now = DateTime.now();
    final todayStr = istDateStr(now);

    // ── Daily reset (all counters are now daily) ─────────────────
    final lastDaily = MigratedKey.read<String>(_lastDailyReset);
    if (lastDaily != todayStr) {
      await MigratedKey.write(_aiTextLogCountToday, 0);
      await MigratedKey.write(_scanMealCountToday, 0);
      await MigratedKey.write(_cartAuditorCountToday, 0);
      await MigratedKey.write(_lastDailyReset, todayStr);
    }
  }

}
