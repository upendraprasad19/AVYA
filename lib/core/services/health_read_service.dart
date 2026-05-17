import '../utils/ist_date.dart';
import 'hive_service.dart';

/// Canonical READ service for health-domain Hive surfaces.
///
/// Mirrors `HealthWriteService` on the writer side. Sleep/weight/water
/// readers previously each grovelled through `healthBox.values` with
/// slightly different filter predicates — centralising here pins the
/// semantic and surfaces drift instantly.
///
/// closes-OI: OI-02 (architecture-gap — no symmetric ReadServices)
///
/// Hive key shapes (from `HealthWriteService`):
///   - `sleep_log_<istDate>`  : Map { date, sleep_hours, duration_hrs, quality, ... }
///   - `weight_<istDate>`     : Map { date, weight_kg, type:'weight_log', ... }
///   - `water_ml_<istDate>`   : int (bare total ml — legacy shape preserved)
///   - `hydration_<istDate>`  : Map { date, water_ml, urine_color_index, hydration_score, ... }
///   - `urine_color_<istDate>`: Map { date, label, index, ... }
class HealthReadService {
  HealthReadService._();
  static final HealthReadService instance = HealthReadService._();

  /// Returns the most recent logged bodyweight (kg) across every
  /// `weight_<istDate>` entry in healthBox. Sorted by stamped `date`
  /// (lexical `YYYY-MM-DD` ordering); returns null when no weight has
  /// ever been logged.
  ///
  /// Used by: home weight tile, AI snapshot weight_kg, profile completeness.
  double? latestWeightKg() {
    final box = HiveService.instance.healthBox;
    String? bestDate;
    double? bestWeight;
    for (final entry in box.toMap().entries) {
      final keyStr = entry.key.toString();
      if (!keyStr.startsWith('weight_')) continue;
      // Exclude `weight_log_*` legacy multi-entry shape if it ever lands —
      // we only want the per-day overwrite key.
      if (keyStr.startsWith('weight_log_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final w = (map['weight_kg'] as num?)?.toDouble();
      final d = map['date'] as String?;
      if (w == null || w <= 0 || d == null || d.isEmpty) continue;
      if (bestDate == null || d.compareTo(bestDate) > 0) {
        bestDate = d;
        bestWeight = w;
      }
    }
    return bestWeight;
  }

  /// Returns logged sleep hours for the IST date containing [date], or
  /// null if no `sleep_log_<istDate>` entry exists.
  ///
  /// Reads both `sleep_hours` (canonical, written by HealthWriteService)
  /// and `duration_hrs` (legacy alias preserved by the writer for
  /// `sync_health.dart` list-key compat).
  double? sleepHoursForDate(DateTime date) {
    final box = HiveService.instance.healthBox;
    final key = 'sleep_log_${istDateStr(date)}';
    final raw = box.get(key);
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return (map['sleep_hours'] as num?)?.toDouble() ??
        (map['duration_hrs'] as num?)?.toDouble();
  }

  /// Returns total water (ml) logged for the IST date containing [date].
  /// Reads the bare-int `water_ml_<istDate>` key written by
  /// `HealthWriteService.setWaterMl`. Returns 0 (not null) when the key
  /// is absent — water is an additive total and "0 ml logged" and
  /// "haven't touched the water card today" are the same state for UI.
  int waterMlForDate(DateTime date) {
    final box = HiveService.instance.healthBox;
    final key = 'water_ml_${istDateStr(date)}';
    final raw = box.get(key);
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }
}
