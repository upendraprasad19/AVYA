import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

/// Last-7-days numeric series feeding the [WeeklyReportCard]'s 4-up
/// sparkline grid.
///
/// Each list has length 7, ordered oldest → newest. Days with no data:
///   * `weight`   — forward-filled from the previous day (or 0 when
///     the user has logged nothing yet in the window);
///   * `calories` / `protein` / `workouts` — 0 so the gap reads as a
///     valley, which matches the visual intent of "no activity".
///
/// Pure Hive read — no network, no Supabase. Safe to rebuild on every
/// profile screen rebuild; invalidate when the user logs a workout or
/// meal if you want the sparkline to refresh without an app restart.
class WeeklyReportSeries {
  final List<double> weight;
  final List<double> calories;
  final List<double> protein;
  final List<double> workouts;

  const WeeklyReportSeries({
    required this.weight,
    required this.calories,
    required this.protein,
    required this.workouts,
  });

  /// True when every series is effectively empty (no data at all for
  /// the window). Card renders a "no data yet" empty state in this case.
  bool get isEmpty =>
      weight.every((v) => v == 0) &&
      calories.every((v) => v == 0) &&
      protein.every((v) => v == 0) &&
      workouts.every((v) => v == 0);
}

class WeeklyReportDataNotifier extends Notifier<WeeklyReportSeries> {
  @override
  WeeklyReportSeries build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final hive = HiveService.instance;
    final today = DateTime.now();

    // Generate 7 date strings (oldest → newest).
    final dates = <String>[
      for (var i = 6; i >= 0; i--) _fmt(today.subtract(Duration(days: i))),
    ];

    // ── Weight ───────────────────────────────────────────────────
    // Pull all weight logs, index last-known-per-day, then forward-fill
    // across the 7-day window so the line doesn't spike to 0 on days
    // the user didn't log.
    final weightByDate = <String, double>{};
    for (final raw in hive.healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      final kg = (log['weight_kg'] as num?)?.toDouble();
      if (date == null || kg == null) continue;
      // Last write wins (typical when user logs multiple times on one day).
      weightByDate[date] = kg;
    }
    final weight = <double>[];
    double lastKnown = 0;
    for (final d in dates) {
      if (weightByDate.containsKey(d)) {
        lastKnown = weightByDate[d]!;
      }
      weight.add(lastKnown);
    }

    // ── Calories + Protein ───────────────────────────────────────
    final calByDate = <String, double>{for (final d in dates) d: 0};
    final protByDate = <String, double>{for (final d in dates) d: 0};
    for (final raw in hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      if (date == null || !calByDate.containsKey(date)) continue;
      // Skip saved-meal templates — they shouldn't count as consumed.
      if (log['is_saved_meal'] == true) continue;
      calByDate[date] =
          calByDate[date]! + ((log['total_calories'] as num?)?.toDouble() ?? 0);
      protByDate[date] =
          protByDate[date]! + ((log['total_protein'] as num?)?.toDouble() ?? 0);
    }
    final calories = [for (final d in dates) calByDate[d]!];
    final protein = [for (final d in dates) protByDate[d]!];

    // ── Workouts ─────────────────────────────────────────────────
    // Count as "1" for any day with at least one wlog_* entry, "0"
    // otherwise. Deduplicates by date so a user who logs two sessions
    // on the same day still shows as one bar.
    final workoutDates = <String>{};
    for (final key in hive.workoutBox.keys) {
      if (key is! String || !key.startsWith('wlog_')) continue;
      final raw = hive.workoutBox.get(key);
      if (raw is! Map) continue;
      final date = raw['date'] as String?;
      if (date != null) workoutDates.add(date);
    }
    final workouts = [
      for (final d in dates) workoutDates.contains(d) ? 1.0 : 0.0,
    ];

    return WeeklyReportSeries(
      weight: weight,
      calories: calories,
      protein: protein,
      workouts: workouts,
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final weeklyReportDataProvider =
    NotifierProvider<WeeklyReportDataNotifier, WeeklyReportSeries>(
        WeeklyReportDataNotifier.new);
