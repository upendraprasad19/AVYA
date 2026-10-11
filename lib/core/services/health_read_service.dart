import '../constants/body_measurement_sites.dart';
import '../constants/body_measurement_specs.dart';
import '../utils/ist_date.dart';
import '../utils/readiness.dart';
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
///   - `measurement_<istDate>`: Map { date, chest, waist, hips, arms (cm, any may be
///     null or absent), source, updated_at_ms, ... }
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

  /// ⑥ Batch 6 (W2.3) — the readiness check-in for the IST date containing
  /// [date], or null if none logged that day. Drives the active-workout
  /// re-entry gate (skip the sheet + re-apply the SAME mode on resume — never
  /// re-prompt) and the session adjustment.
  ReadinessCheckin? readinessForDate(DateTime date) {
    final box = HiveService.instance.healthBox;
    final raw = box.get('readiness_${istDateStr(date)}');
    if (raw is! Map) return null;
    return ReadinessCheckin.fromMap(raw);
  }

  /// ⑥ Batch 6 (W3.7) — every logged readiness check-in, NEWEST FIRST (scans
  /// `readiness_<istDate>` keys). Feeds the PRO Weekly-Report readiness trend.
  List<ReadinessCheckin> readinessHistory() {
    final box = HiveService.instance.healthBox;
    final out = <ReadinessCheckin>[];
    for (final entry in box.toMap().entries) {
      if (!entry.key.toString().startsWith('readiness_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      out.add(ReadinessCheckin.fromMap(raw));
    }
    out.sort((a, b) => b.date.compareTo(a.date)); // lexical YYYY-MM-DD desc
    return out;
  }

  /// Every VALID body-measurement record, NEWEST FIRST (L2b Landing A, OI-297;
  /// scans the `measurement_<istDate>` keys).
  ///
  /// The read path for what a person sees or the coach is told: the AI snapshot
  /// goes through [latestBySite], and the Landing B sheet and prompt will go
  /// through this list. (The sync push and the restore handle the raw records
  /// themselves; Landing A does not change them.)
  ///
  /// A record is valid when its `date` is a real IST calendar day written
  /// `YYYY-MM-DD` that is not later than today (a wrong device clock stored a
  /// future date: it would otherwise be the "newest" value and shadow every
  /// real entry until the day came), and an entry keeps only the sites whose
  /// value is inside the [kBodyMeasurementSpecs] bounds; a record with no such
  /// site is dropped. Order: `date` descending, then `updated_at_ms` descending
  /// (a non-number counts as 0: restored and pulled records carry none), then
  /// the Hive key descending, so two records with one date still sort the same
  /// way on every run. Every read is a type test, never a cast: a malformed
  /// record is skipped, it cannot throw.
  List<MeasurementEntry> measurementHistory() {
    final box = HiveService.instance.healthBox;
    final today = istTodayStr();
    final rows = <_MeasurementRow>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('measurement_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final date = raw['date'];
      if (date is! String || !_isRealIstDateKey(date)) continue;
      if (date.compareTo(today) > 0) continue;
      final sites = <String, double>{};
      for (final site in kBodyMeasurementSites) {
        final v = raw[site];
        if (v is! num) continue;
        final cm = v.toDouble();
        if (isValidBodyMeasurementCm(site, cm)) sites[site] = cm;
      }
      if (sites.isEmpty) continue;
      final stamp = raw['updated_at_ms'];
      rows.add(_MeasurementRow(
        key: key,
        updatedAtMs: stamp is num ? stamp : 0,
        entry: MeasurementEntry(date: date, sites: sites),
      ));
    }
    rows.sort((a, b) {
      final byDate = b.entry.date.compareTo(a.entry.date);
      if (byDate != 0) return byDate;
      final byStamp = b.updatedAtMs.compareTo(a.updatedAtMs);
      if (byStamp != 0) return byStamp;
      return b.key.compareTo(a.key);
    });
    return [for (final r in rows) r.entry];
  }

  /// The newest valid value of each site, with the day it was logged
  /// (`latestBySiteOf(measurementHistory())`). A site never measured is absent.
  Map<String, ({double cm, String date})> latestBySite() =>
      latestBySiteOf(measurementHistory());

  /// PURE: the newest value per site in [newestFirst], which MUST be ordered
  /// newest first (the order [measurementHistory] returns). The result is built
  /// by walking [kBodyMeasurementSites], so its key order is the registry's and
  /// not the order the records happen to sit in the box. A site whose newest
  /// record holds no valid value falls through to the newest older record that
  /// does.
  static Map<String, ({double cm, String date})> latestBySiteOf(
      List<MeasurementEntry> newestFirst) {
    final out = <String, ({double cm, String date})>{};
    for (final site in kBodyMeasurementSites) {
      for (final entry in newestFirst) {
        final cm = entry.sites[site];
        if (cm == null) continue;
        out[site] = (cm: cm, date: entry.date);
        break;
      }
    }
    return out;
  }
}

/// One valid body-measurement day as [HealthReadService.measurementHistory]
/// returns it: the IST day (`YYYY-MM-DD`) and the sites of that record whose
/// value is within bounds (centimetres, registry tokens only).
class MeasurementEntry {
  const MeasurementEntry({required this.date, required this.sites});

  final String date;
  final Map<String, double> sites;
}

/// A [MeasurementEntry] with the two tie-break keys the sort needs.
class _MeasurementRow {
  const _MeasurementRow({
    required this.key,
    required this.updatedAtMs,
    required this.entry,
  });

  final String key;
  final num updatedAtMs;
  final MeasurementEntry entry;
}

final RegExp _istDateKeyShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// True when [s] is exactly `YYYY-MM-DD` AND names a day that exists. Dart
/// normalises an impossible date instead of failing (`DateTime.utc(2026, 13,
/// 45)` is a valid object, and so is `DateTime.tryParse('2026-02-30')`), so
/// the check is numeric: the three parts must come back unchanged from a
/// `DateTime.utc`. Not a string rebuilt with `padLeft` (the date-key drift
/// gate bans that).
bool _isRealIstDateKey(String s) {
  if (!_istDateKeyShape.hasMatch(s)) return false;
  final y = int.parse(s.substring(0, 4));
  final m = int.parse(s.substring(5, 7));
  final d = int.parse(s.substring(8, 10));
  final t = DateTime.utc(y, m, d);
  return t.year == y && t.month == m && t.day == d;
}
