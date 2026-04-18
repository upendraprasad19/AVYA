import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:uuid/uuid.dart';

/// Repository for all nutrition-related Hive reads/writes.
///
/// Wraps Hive nutritionBox and healthBox access so that providers
/// and widgets never touch Hive directly.
class NutritionRepository {
  NutritionRepository._();
  static final NutritionRepository _instance = NutritionRepository._();
  static NutritionRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

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
    final dateStr = '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    double fiber = 0;

    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != dateStr) continue;
      // Exclude saved-meal templates — they're not actual logs.
      if (log['is_saved_meal'] == true) continue;

      calories += (log['total_calories'] as num?)?.toDouble() ?? 0;
      protein += (log['total_protein'] as num?)?.toDouble() ?? 0;
      carbs += (log['total_carbs'] as num?)?.toDouble() ?? 0;
      fat += (log['total_fat'] as num?)?.toDouble() ?? 0;
      fiber += (log['total_fiber'] as num?)?.toDouble() ?? 0;
    }

    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
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

  // ── Weekly Report Data ────────────────────────────────────────

  /// Computes weekly nutrition report data from the last 7 days of logs.
  ///
  /// Returns a map with keys: avgCalories, calTarget, proteinDays, bestDay.
  Map<String, String> computeWeeklyReportData() {
    final now = DateTime.now();
    double totalCalories = 0;
    double totalProtein = 0;
    final loggedDates = <String>{};
    String bestDay = '--';
    double bestDayCal = 0;

    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      if (date == null) continue;
      final d = DateTime.tryParse(date);
      if (d == null || now.difference(d).inDays >= 7) continue;

      loggedDates.add(date);
      final cal = (log['total_calories'] as num?)?.toDouble() ?? 0;
      final prot = (log['total_protein'] as num?)?.toDouble() ?? 0;
      totalCalories += cal;
      totalProtein += prot;

      if (cal > bestDayCal) {
        bestDayCal = cal;
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        bestDay = weekdays[d.weekday - 1];
      }
    }

    final daysLogged = loggedDates.length;
    final avgCal = daysLogged > 0
        ? (totalCalories / daysLogged).toStringAsFixed(0)
        : '--';

    // Get target from profile
    final profile = _hive.userBox.get('profile');
    String calTarget = '--';
    int proteinTarget = 0;
    if (profile is Map) {
      final tdee = (profile['tdee'] as num?)?.toInt();
      proteinTarget = (profile['protein_target'] as num?)?.toInt() ?? 0;
      if (tdee != null) calTarget = '$tdee';
    }

    // Count days protein was on target (within 20%)
    int proteinOnTarget = 0;
    if (proteinTarget > 0 && daysLogged > 0) {
      final avgProt = totalProtein / daysLogged;
      if (avgProt >= proteinTarget * 0.8) {
        proteinOnTarget = daysLogged;
      }
    }

    return {
      'avgCalories': avgCal,
      'calTarget': calTarget,
      'proteinDays': '$proteinOnTarget/$daysLogged',
      'bestDay': bestDay,
    };
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
          (a['date'] as String).compareTo(b['date'] as String));

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
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Returns the Monday of the week containing [date].
  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  // ── Supabase Sync (background, fire-and-forget) ──────────────────

  /// Namespace used to derive a stable UUID from the Hive key. Must match
  /// SyncService._syncNamespace so the full sync + the immediate per-log
  /// sync agree on the same row id (no duplicates on replay).
  static const _nutritionSyncNamespace =
      '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  /// Syncs a nutrition log to the Supabase `nutrition_logs` table.
  ///
  /// Fire-and-forget: catches all errors and logs them via debugPrint.
  /// The caller should have already written to Hive before calling this.
  ///
  /// Schema contract (verified 2026-04-18 — see diagnosis commit):
  /// Supabase `nutrition_logs` has these columns — NOTHING else:
  /// `id uuid, user_id uuid, date date, total_calories numeric,
  ///  total_protein numeric, total_carbs numeric, total_fat numeric,
  ///  meal_type text, created_at timestamptz`.
  ///
  /// Hive stores the richer map (food_id, food_name, quantity_g,
  /// total_fiber, source) for local UI, but those columns don't exist
  /// on the cloud table. Before this fix, the client sent the full map
  /// AND the Hive key string as `id`; Postgres rejected both the extra
  /// columns and the non-uuid id, silently 400-ing every write. Result:
  /// nutrition_logs stayed at 0 rows for the test user despite dozens
  /// of food logs. We now project to schema-matching columns only and
  /// coerce the id to a deterministic v5 UUID.
  static Future<void> syncLogToSupabase({
    required Map<String, dynamic> data,
  }) async {
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;

      final localKey = data['id'] as String? ?? '';
      if (localKey.isEmpty) return;
      final cloudId =
          const Uuid().v5(_nutritionSyncNamespace, localKey);

      final payload = <String, dynamic>{
        'id': cloudId,
        'user_id': userId,
        if (data['date'] != null) 'date': data['date'],
        if (data['meal_type'] != null) 'meal_type': data['meal_type'],
        if (data['total_calories'] != null)
          'total_calories': data['total_calories'],
        if (data['total_protein'] != null)
          'total_protein': data['total_protein'],
        if (data['total_carbs'] != null)
          'total_carbs': data['total_carbs'],
        if (data['total_fat'] != null) 'total_fat': data['total_fat'],
        if (data['created_at'] != null) 'created_at': data['created_at'],
      };

      await SupabaseService.instance.client.from('nutrition_logs').upsert(
        payload,
        onConflict: 'id',
      );
    } catch (e) {
      debugPrint('[NutritionRepository] syncLogToSupabase failed: $e');
    }
  }

  /// Syncs a user-created custom food to the Supabase `user_custom_foods` table.
  ///
  /// Fire-and-forget: catches all errors and logs them via debugPrint.
  /// The caller should have already written to Hive before calling this.
  static Future<void> syncCustomFoodToSupabase({
    required Map<String, dynamic> data,
  }) async {
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;
      await SupabaseService.instance.client.from('user_custom_foods').insert({
        'user_id': userId,
        'name': data['name'],
        'calories_per_100g': data['calories_per_100g'],
        'protein_per_100g': data['protein_per_100g'],
        'carbs_per_100g': data['carbs_per_100g'],
        'fat_per_100g': data['fat_per_100g'],
        'fiber_per_100g': data['fiber_per_100g'],
        'standard_serving_desc': data['standard_serving_desc'],
        'standard_serving_g': data['standard_serving_g'],
        'calories_std': data['calories_std'],
        'protein_std': data['protein_std'],
        'carbs_std': data['carbs_std'],
        'fat_std': data['fat_std'],
      });
    } catch (e) {
      debugPrint('[NutritionRepository] syncCustomFoodToSupabase failed: $e');
    }
  }
}
