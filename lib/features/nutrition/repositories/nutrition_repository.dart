import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

typedef NutritionHistoryInputs = ({
  List<Object?> rows,
  Map<String, int> waterByDay,
  Set<String> trainingDays,
  String? onboardingDay,
  List<TargetEntry> targets,
});

/// Repository for all nutrition-related Hive reads/writes.
///
/// Wraps Hive nutritionBox and healthBox access so that providers
/// and widgets never touch Hive directly.
class NutritionRepository {
  NutritionRepository._();
  static final NutritionRepository _instance = NutritionRepository._();
  static NutritionRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

  // ── Nutrition History (plan docs/plans/nutrition-history.md) ──

  /// Everything the History screen derives its series from, read in one go:
  /// every nutritionBox value (the pure builder applies the day predicate of
  /// [dailyMacros]), water per day, the days with a logged workout, the
  /// onboarding day and the recorded target history.
  NutritionHistoryInputs loadHistoryInputs() {
    final profile = _hive.userBox.get('profile');
    final onboarded = DateTime.tryParse(
        (profile is Map ? profile['onboarding_completed_at'] as String? : null) ??
            '');
    return (
      rows: _hive.nutritionBox.values.toList(growable: false),
      waterByDay: HealthReadService.instance.waterMlByDay(),
      trainingDays: WorkoutReadService.instance.datesWithExerciseLogs(),
      onboardingDay: onboarded == null ? null : istDateStr(onboarded),
      targets: TargetHistoryService.read(),
    );
  }

  /// The meal rows of one IST day (`yyyy-MM-dd`), in slot order: the rows
  /// [dailyMacros] sums for that day that carry a `meal_type`.
  List<Map<String, dynamic>> mealsForDay(String dayKey) {
    const order = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final out = <Map<String, dynamic>>[];
    final Iterable<dynamic> values;
    try {
      values = _hive.nutritionBox.values;
    } catch (_) {
      // No session to read (sign-out / account-swap window, class a2d9f4).
      return out;
    }
    for (final raw in values) {
      if (raw is! Map) continue;
      if (raw['is_saved_meal'] == true) continue;
      if (raw['date'] != dayKey || raw['meal_type'] is! String) continue;
      out.add(Map<String, dynamic>.from(raw));
    }
    int rank(Map<String, dynamic> m) {
      final i = order.indexOf((m['meal_type'] as String).toLowerCase());
      return i < 0 ? order.length - 1 : i;
    }

    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  /// Records today's targets in the target history when they changed
  /// (`TargetHistoryService.reconcile`). Returns whether it wrote.
  bool reconcileTargetHistory() => TargetHistoryService.reconcile();

  // ── Daily Macros (single source of truth, F7) ─────────────────

  /// Returns summed macros for [date]. Single source of truth shared by
  /// the Home nutrition card (`nutritionSummaryProvider`) and the Nutrition
  /// screen (`dailyNutritionProvider`). F7 · Previously each feature
  /// summed independently — same math, but small divergences (per-item
  /// Atwater fallback, meal_type filtering) could produce mismatched
  /// totals. Centralising prevents drift.
  ///
  /// Values come from `nutritionBox` entries whose `date` field matches
  /// the given date in `YYYY-MM-DD` format. Each log's `total_calories`
  /// etc. are already computed at log time with per-item Atwater fallback
  /// (see `_ScanResultEditor` and `logFoodItem`).
  Map<String, double> dailyMacros(DateTime date) {
    // OI-02 (closes-diagnose: 2026-05-17-oi-02-read-services) —
    // delegates to canonical NutritionReadService. Public API preserved
    // (Map<String,double>) so the 2 consumers (nutrition_provider +
    // home_provider) don't need updates; service returns Map<String,num>
    // which we widen to double here.
    final raw = NutritionReadService.instance.totalMacrosForDate(date);
    return {
      'calories': raw['calories']!.toDouble(),
      'protein': raw['protein']!.toDouble(),
      'carbs': raw['carbs']!.toDouble(),
      'fat': raw['fat']!.toDouble(),
      'fiber': raw['fiber']!.toDouble(),
    };
  }

  // ── Weight Trend ──────────────────────────────────────────────

  /// Returns the last [limit] weight entries sorted by date ascending.
  List<Map<String, dynamic>> getWeightEntries({int limit = 10}) {
    final entries = <Map<String, dynamic>>[];

    for (final raw in _hive.healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['weight_kg'] != null && log['date'] != null) {
        entries.add(log);
      }
    }

    entries.sort((a, b) =>
        (a['date'] as String? ?? '').compareTo(b['date'] as String? ?? ''));

    if (entries.length > limit) {
      return entries.sublist(entries.length - limit);
    }
    return entries;
  }

  // ── Nutrition Compliance ──────────────────────────────────────

  /// Returns the number of unique days with nutrition logs in the last 7 days.
  int getNutritionDaysLoggedThisWeek() {
    final now = DateTime.now();
    final loggedDates = <String>{};

    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      if (date != null) {
        final d = DateTime.tryParse(date);
        if (d != null && now.difference(d).inDays < 7) {
          loggedDates.add(date);
        }
      }
    }

    return loggedDates.length;
  }

  // ── Daily Macros ─────────────────────────────────────────────────

  /// Daily macros for a date range.
  ///
  /// Aggregates all nutrition logs by date: sum calories, protein, carbs, fat.
  /// Returns `[{date, calories, protein, carbs, fat}]` ordered by date ascending.
  List<Map<String, dynamic>> getDailyMacros({int days = 30}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final dateMap = <String, Map<String, double>>{};

    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;

      final entry = dateMap.putIfAbsent(dateStr, () => {
        'calories': 0.0,
        'protein': 0.0,
        'carbs': 0.0,
        'fat': 0.0,
      });

      entry['calories'] = (entry['calories'] ?? 0) +
          ((log['total_calories'] as num?)?.toDouble() ??
              (log['calories'] as num?)?.toDouble() ??
              0);
      entry['protein'] = (entry['protein'] ?? 0) +
          ((log['total_protein'] as num?)?.toDouble() ??
              (log['protein'] as num?)?.toDouble() ??
              0);
      entry['carbs'] = (entry['carbs'] ?? 0) +
          ((log['total_carbs'] as num?)?.toDouble() ??
              (log['carbs'] as num?)?.toDouble() ??
              0);
      entry['fat'] = (entry['fat'] ?? 0) +
          ((log['total_fat'] as num?)?.toDouble() ??
              (log['fat'] as num?)?.toDouble() ??
              0);
    }

    final results = dateMap.entries.map((e) => {
          'date': e.key,
          'calories': e.value['calories'] ?? 0.0,
          'protein': e.value['protein'] ?? 0.0,
          'carbs': e.value['carbs'] ?? 0.0,
          'fat': e.value['fat'] ?? 0.0,
        }).toList()
      ..sort((a, b) =>
          (a['date']! as String).compareTo(b['date']! as String));

    return results;
  }

  // ── Weekly Nutrition Averages ─────────────────────────────────────

  /// Weekly nutrition averages.
  ///
  /// Groups daily macros by week and calculates averages.
  /// Returns `[{week_start, avg_calories, avg_protein, avg_carbs, avg_fat}]`.
  List<Map<String, dynamic>> getWeeklyAverages({int weeks = 8}) {
    final dailyData = getDailyMacros(days: weeks * 7);
    if (dailyData.isEmpty) return [];

    final weekMap = <String, List<Map<String, dynamic>>>{};

    for (final day in dailyData) {
      final dateStr = day['date'] as String;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      final weekStart = _getWeekStart(date);
      final weekKey = _formatDate(weekStart);
      weekMap.putIfAbsent(weekKey, () => []).add(day);
    }

    final results = <Map<String, dynamic>>[];
    for (final entry in weekMap.entries) {
      final days = entry.value;
      final count = days.length;
      if (count == 0) continue;

      double totalCal = 0, totalProt = 0, totalCarb = 0, totalFat = 0;
      for (final d in days) {
        totalCal += (d['calories'] as num?)?.toDouble() ?? 0;
        totalProt += (d['protein'] as num?)?.toDouble() ?? 0;
        totalCarb += (d['carbs'] as num?)?.toDouble() ?? 0;
        totalFat += (d['fat'] as num?)?.toDouble() ?? 0;
      }

      results.add({
        'week_start': entry.key,
        'avg_calories': totalCal / count,
        'avg_protein': totalProt / count,
        'avg_carbs': totalCarb / count,
        'avg_fat': totalFat / count,
      });
    }

    results.sort((a, b) =>
        (a['week_start'] as String).compareTo(b['week_start'] as String));
    return results;
  }

  // ── Protein Deficit Streak ───────────────────────────────────────

  /// Consecutive days below protein target (counting backwards from today).
  ///
  /// Reads protein target from profile. A day is deficit if logged protein
  /// is below target * 0.8. Stops counting when a day meets or exceeds target.
  /// Returns 0 if today meets target or no data.
  int getProteinDeficitStreak() {
    final profile = _hive.userBox.get('profile');
    int proteinTarget = 0;
    if (profile is Map) {
      proteinTarget = (profile['protein_grams'] as num?)?.toInt() ??
          (profile['protein_target'] as num?)?.toInt() ??
          0;
    }
    if (proteinTarget <= 0) return 0;

    final threshold = proteinTarget * 0.8;
    final now = DateTime.now();
    int streak = 0;

    // Build a map of date -> total protein.
    final proteinByDate = <String, double>{};
    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final prot = (log['total_protein'] as num?)?.toDouble() ??
          (log['protein'] as num?)?.toDouble() ??
          0;
      proteinByDate[dateStr] =
          (proteinByDate[dateStr] ?? 0) + prot;
    }

    // Count backwards from today.
    for (int i = 0; i < 90; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = _formatDate(date);
      final dayProtein = proteinByDate[dateStr];

      // If no log for the day, count as deficit.
      if (dayProtein == null || dayProtein < threshold) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  // ── Weekend vs Weekday Calories ──────────────────────────────────

  /// Weekend vs weekday calorie comparison.
  ///
  /// Returns `{weekday_avg, weekend_avg, delta_percent}`.
  /// delta_percent = ((weekend - weekday) / weekday * 100).
  Map<String, double> getWeekdayVsWeekendCalories({int weeks = 4}) {
    final dailyData = getDailyMacros(days: weeks * 7);
    double weekdayTotal = 0, weekendTotal = 0;
    int weekdayCount = 0, weekendCount = 0;

    for (final day in dailyData) {
      final dateStr = day['date'] as String;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      final cal = (day['calories'] as num?)?.toDouble() ?? 0;

      if (date.weekday >= 6) {
        // Saturday=6, Sunday=7
        weekendTotal += cal;
        weekendCount++;
      } else {
        weekdayTotal += cal;
        weekdayCount++;
      }
    }

    final weekdayAvg = weekdayCount > 0 ? weekdayTotal / weekdayCount : 0.0;
    final weekendAvg = weekendCount > 0 ? weekendTotal / weekendCount : 0.0;
    final delta = weekdayAvg > 0
        ? ((weekendAvg - weekdayAvg) / weekdayAvg * 100)
        : 0.0;

    return {
      'weekday_avg': weekdayAvg,
      'weekend_avg': weekendAvg,
      'delta_percent': delta,
    };
  }

  // ── Weight History ───────────────────────────────────────────────

  /// Weight entries with date range (improvement over limit-only method).
  ///
  /// Returns `[{date, weight_kg}]` ordered by date ascending.
  List<Map<String, dynamic>> getWeightHistory({int days = 90}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final entries = <Map<String, dynamic>>[];

    for (final raw in _hive.healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final weight = log['weight_kg'];
      if (weight == null) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;

      entries.add({
        'date': dateStr,
        'weight_kg': (weight as num).toDouble(),
      });
    }

    entries.sort((a, b) =>
        (a['date'] as String).compareTo(b['date'] as String));
    return entries;
  }

  // ── Sleep Stats ──────────────────────────────────────────────────

  /// Sleep averages for the last [days] days.
  ///
  /// Returns `{avg_hours, nights_below_7h, avg_quality_score}`.
  /// Quality scoring: good=3, fair=2, poor=1. Default 0 if no data.
  Map<String, dynamic> getSleepStats({int days = 7}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    double totalHours = 0;
    int count = 0;
    int belowSeven = 0;
    double totalQuality = 0;

    for (final raw in _hive.healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      // Only match sleep entries.
      final hours = (log['duration_hrs'] as num?)?.toDouble() ??
          (log['sleep_hours'] as num?)?.toDouble();
      if (hours == null) continue;

      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;

      totalHours += hours;
      count++;
      if (hours < 7) belowSeven++;

      final quality = (log['quality'] as String? ?? '').toLowerCase();
      switch (quality) {
        case 'good':
          totalQuality += 3;
          break;
        case 'fair':
          totalQuality += 2;
          break;
        case 'poor':
          totalQuality += 1;
          break;
      }
    }

    return {
      'avg_hours': count > 0 ? (totalHours / count) : 0.0,
      'nights_below_7h': belowSeven,
      'avg_quality_score': count > 0 ? (totalQuality / count) : 0.0,
    };
  }

  // ── Hydration Deficit Streak ─────────────────────────────────────

  /// Consecutive days hydration below 2000ml (counting backwards from today).
  int getHydrationDeficitStreak() {
    final now = DateTime.now();
    int streak = 0;

    for (int i = 0; i < 90; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = _formatDate(date);
      final key = 'water_ml_$dateStr';
      final ml = (_hive.healthBox.get(key) as num?)?.toInt() ?? 0;

      if (ml < 2000) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  // ── Daily Calories for a Date ────────────────────────────────────

  /// Returns total calories logged for a specific date string.
  double getCaloriesForDate(String dateStr) {
    double total = 0;
    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != dateStr) continue;
      total += (log['total_calories'] as num?)?.toDouble() ??
          (log['calories'] as num?)?.toDouble() ??
          0;
    }
    return total;
  }

  // ── Helpers ──────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    // Writer keys `nlog_*` rows with `istDateStr(date)` — the reader's date
    // key MUST match (was device-local → missed rows off-IST).
    return istDateStr(date);
  }

  /// Returns the Monday of the week containing [date].
  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  // ── Supabase Sync — REMOVED in audit 2026-05-20 / A8 ──────────────
  //
  // Previously this section contained two static methods:
  //   - syncLogToSupabase: zero callers (dead code).
  //   - syncCustomFoodToSupabase: one caller in nutrition_provider.dart;
  //     duplicated `SyncService.instance.syncCustomItemsNow()` on the next
  //     line of that caller (same fire-and-forget shape).
  //
  // Both swallowed errors via `debugPrint` → the silent-drop class fixed
  // for log-client-error in #16.1 D never reached this path because it
  // bypassed `ErrorTelemetry` entirely (`feedback_observability_silent_drop`).
  //
  // Canonical replacement: `SyncService.instance.syncCustomItemsNow()` +
  // `sync_nutrition.dart` (hot-path writer at line 90). Both go through
  // canonical telemetry sinks.
  //
  // _nutritionSyncNamespace constant was unused after the deletion and
  // also removed.

}
