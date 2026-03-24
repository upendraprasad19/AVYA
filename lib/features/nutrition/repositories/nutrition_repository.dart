import 'package:icanbefitter/core/services/hive_service.dart';

/// Repository for all nutrition-related Hive reads/writes.
///
/// Wraps Hive nutritionBox and healthBox access so that providers
/// and widgets never touch Hive directly.
class NutritionRepository {
  NutritionRepository._();
  static final NutritionRepository _instance = NutritionRepository._();
  static NutritionRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

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
}
