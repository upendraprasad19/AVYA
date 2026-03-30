import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// Severity level for a coaching insight.
enum InsightSeverity { high, medium, low }

/// A single coaching insight detected from local Hive data.
///
/// Used in two places:
/// - [coachNotice] is injected into the AI system prompt so the coach
///   can proactively address the issue.
/// - [userMessage] is shown on the dashboard insight card.
class CoachingInsight {
  final String patternId;
  final InsightSeverity severity;

  /// Injected into the AI coach system prompt.
  final String coachNotice;

  /// Shown on the dashboard insight card to the user.
  final String userMessage;

  /// Whether this insight should trigger a push notification.
  final bool pushWorthy;

  const CoachingInsight({
    required this.patternId,
    required this.severity,
    required this.coachNotice,
    required this.userMessage,
    this.pushWorthy = false,
  });

  @override
  String toString() => 'CoachingInsight($patternId, $severity)';
}

/// Detects 12 coaching patterns from local Hive data.
///
/// All patterns read from Hive only — zero network cost.
/// Results are cached in configBox with a date stamp so they are
/// only recomputed once per day.
class PatternDetector {
  PatternDetector._();
  static final PatternDetector _instance = PatternDetector._();
  static PatternDetector get instance => _instance;

  final WorkoutRepository _workouts = WorkoutRepository.instance;
  final NutritionRepository _nutrition = NutritionRepository.instance;
  final UserRepository _user = UserRepository.instance;
  final HiveService _hive = HiveService.instance;

  /// Run all 12 patterns and return detected insights.
  ///
  /// Each pattern catches its own errors silently — partial data is OK.
  /// Results are cached in configBox['pattern_insights'] with today's date.
  List<CoachingInsight> analyze() {
    final insights = <CoachingInsight>[];

    _tryAdd(insights, _streakRisk);
    _tryAdd(insights, _plateauDetector);
    _tryAdd(insights, _proteinDeficit);
    _tryAdd(insights, _weightTrendAlert);
    _tryAdd(insights, _sleepDeficit);
    _tryAdd(insights, _hydrationDeficit);
    _tryAdd(insights, _missedWorkouts);
    _tryAdd(insights, _goalDrift);
    _tryAdd(insights, _recoveryEnforcer);
    _tryAdd(insights, _dayOfWeekPattern);
    _tryAdd(insights, _milestoneCountdown);
    _tryAdd(insights, _weekendNutrition);

    // Sort by severity: high first, then medium, then low.
    insights.sort((a, b) => a.severity.index.compareTo(b.severity.index));

    // Cache results.
    _hive.configBox.put('pattern_insights', {
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'count': insights.length,
      'top_pattern': insights.isNotEmpty ? insights.first.patternId : null,
      'pattern_ids': insights.map((i) => i.patternId).toList(),
    });

    return insights;
  }

  /// Try to run a detector function and add result to list if non-null.
  void _tryAdd(
    List<CoachingInsight> list,
    CoachingInsight? Function() detector,
  ) {
    try {
      final result = detector();
      if (result != null) list.add(result);
    } catch (_) {
      // Partial data is OK — skip this pattern silently.
    }
  }

  // ── 1. Streak Risk ───────────────────────────────────────── HIGH

  /// IF current_streak_weeks > 2 AND no workout today AND time > 7pm.
  CoachingInsight? _streakRisk() {
    final progress = _user.getProgress();
    if (progress == null) return null;

    final streakWeeks =
        (progress['current_streak_weeks'] as num?)?.toInt() ?? 0;
    if (streakWeeks <= 2) return null;

    final now = DateTime.now();
    final todaySchedule = _workouts.getTodaySchedule();
    if (todaySchedule == null) return null;
    if (todaySchedule['type'] != 'workout') return null;
    if (todaySchedule['status'] == 'completed') return null;

    // Only alert after 7pm.
    if (now.hour < 19) return null;

    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    return CoachingInsight(
      patternId: 'streak_risk',
      severity: InsightSeverity.high,
      coachNotice: "User's $streakWeeks-week streak at risk. "
          "No workout today. It's $timeStr.",
      userMessage: 'Your $streakWeeks-week streak is at risk! '
          "You haven't worked out today.",
      pushWorthy: true,
    );
  }

  // ── 2. Plateau Detector ──────────────────────────────────── HIGH

  /// FOR each of top exercises: IF max weight unchanged 6+ weeks.
  CoachingInsight? _plateauDetector() {
    final prMap = _workouts.loadKeyLiftPRs();
    // Check each lift for plateau.
    final liftNames = {
      'bench': 'Bench Press',
      'squat': 'Squat',
      'deadlift': 'Deadlift',
      'ohp': 'Overhead Press',
    };

    for (final entry in liftNames.entries) {
      final prKey = entry.key;
      final displayName = entry.value;
      final current = prMap[prKey]?['current'] ?? 0.0;
      if (current <= 0) continue;

      // Get PR history over last 90 days for this exercise.
      final history = _workouts.getExercisePRHistory(
        displayName,
        days: 90,
      );
      if (history.length < 3) continue;

      // Check if max weight has been the same for 6+ weeks.
      final sixWeeksAgo =
          DateTime.now().subtract(const Duration(days: 42));
      final recentEntries = history.where((h) {
        final d = DateTime.tryParse(h['date'] as String? ?? '');
        return d != null && d.isAfter(sixWeeksAgo);
      }).toList();

      if (recentEntries.isEmpty) continue;

      final maxRecent = recentEntries
          .map((h) => (h['weight_kg'] as num?)?.toDouble() ?? 0)
          .reduce((a, b) => a > b ? a : b);

      // Check older entries too.
      final olderEntries = history.where((h) {
        final d = DateTime.tryParse(h['date'] as String? ?? '');
        return d != null && d.isBefore(sixWeeksAgo);
      }).toList();

      if (olderEntries.isEmpty) continue;

      final maxOlder = olderEntries
          .map((h) => (h['weight_kg'] as num?)?.toDouble() ?? 0)
          .reduce((a, b) => a > b ? a : b);

      // Plateau: max hasn't increased in 6+ weeks.
      if (maxRecent <= maxOlder) {
        // Estimate weeks stuck.
        final weeksCounts = _workouts.getExtendedWeeklyWorkoutCounts(
          weeks: 12,
        );
        final weeksStuck = weeksCounts.length.clamp(6, 12);

        return CoachingInsight(
          patternId: 'plateau_$prKey',
          severity: InsightSeverity.high,
          coachNotice: "$displayName PR stuck at ${current}kg "
              "for $weeksStuck+ weeks.",
          userMessage: '$displayName plateau detected: ${current}kg '
              'for $weeksStuck+ weeks. Time to adjust!',
          pushWorthy: true,
        );
      }
    }

    return null;
  }

  // ── 3. Protein Deficit ───────────────────────────────────── HIGH

  /// IF protein < target*0.8 for 4+ consecutive days.
  CoachingInsight? _proteinDeficit() {
    final streak = _nutrition.getProteinDeficitStreak();
    if (streak < 4) return null;

    final profile = _user.getProfile();
    final target = (profile?['protein_grams'] as num?)?.toInt() ??
        (profile?['protein_target'] as num?)?.toInt() ??
        0;
    if (target <= 0) return null;

    // Calculate average protein for the deficit period.
    final dailyData = _nutrition.getDailyMacros(days: streak);
    double totalProtein = 0;
    int count = 0;
    for (final day in dailyData) {
      totalProtein += (day['protein'] as num?)?.toDouble() ?? 0;
      count++;
    }
    final avg = count > 0 ? (totalProtein / count).round() : 0;

    return CoachingInsight(
      patternId: 'protein_deficit',
      severity: InsightSeverity.high,
      coachNotice: "Protein below target $streak days straight. "
          "Avg: ${avg}g. Target: ${target}g.",
      userMessage: 'Protein has been low for $streak days. '
          "You're averaging ${avg}g vs your ${target}g target.",
      pushWorthy: true,
    );
  }

  // ── 4. Weight Trend Alert ────────────────────────────────── HIGH

  /// IF (goal=fat_loss AND weight up >1kg in 14d) OR
  /// (goal=build_muscle AND weight down >1kg in 14d).
  CoachingInsight? _weightTrendAlert() {
    final profile = _user.getProfile();
    if (profile == null) return null;
    final goal = profile['primary_goal'] as String? ?? '';

    final weightHistory = _nutrition.getWeightHistory(days: 14);
    if (weightHistory.length < 2) return null;

    final oldest =
        (weightHistory.first['weight_kg'] as num?)?.toDouble() ?? 0;
    final newest =
        (weightHistory.last['weight_kg'] as num?)?.toDouble() ?? 0;
    if (oldest <= 0 || newest <= 0) return null;

    final delta = newest - oldest;

    if (goal == 'lose_fat' && delta > 1.0) {
      return CoachingInsight(
        patternId: 'weight_trend_up',
        severity: InsightSeverity.high,
        coachNotice: "Weight trending up by ${delta.toStringAsFixed(1)}kg "
            "in 14 days. Opposite of fat loss goal.",
        userMessage: 'Weight up ${delta.toStringAsFixed(1)}kg in 2 weeks. '
            'Review calories and activity.',
      );
    }

    if (goal == 'build_muscle' && delta < -1.0) {
      return CoachingInsight(
        patternId: 'weight_trend_down',
        severity: InsightSeverity.high,
        coachNotice: "Weight trending down by "
            "${delta.abs().toStringAsFixed(1)}kg in 14 days. "
            "Opposite of muscle building goal.",
        userMessage: 'Weight down ${delta.abs().toStringAsFixed(1)}kg '
            'in 2 weeks. You may need to eat more.',
      );
    }

    return null;
  }

  // ── 5. Sleep Deficit ─────────────────────────────────────── MEDIUM

  /// IF avg sleep < 7h for 3+ days.
  CoachingInsight? _sleepDeficit() {
    final stats = _nutrition.getSleepStats(days: 7);
    final avgHours = (stats['avg_hours'] as num?)?.toDouble() ?? 0;
    final belowSeven = (stats['nights_below_7h'] as num?)?.toInt() ?? 0;

    if (avgHours <= 0 || belowSeven < 3) return null;

    return CoachingInsight(
      patternId: 'sleep_deficit',
      severity: InsightSeverity.medium,
      coachNotice: "Sleep avg ${avgHours.toStringAsFixed(1)}h over last "
          "7 days. $belowSeven nights below 7h threshold.",
      userMessage: 'Sleep averaging ${avgHours.toStringAsFixed(1)}h. '
          '$belowSeven nights below 7 hours this week.',
    );
  }

  // ── 6. Hydration Deficit ─────────────────────────────────── MEDIUM

  /// IF water < 2000ml for 3+ consecutive days.
  CoachingInsight? _hydrationDeficit() {
    final streak = _nutrition.getHydrationDeficitStreak();
    if (streak < 3) return null;

    return CoachingInsight(
      patternId: 'hydration_deficit',
      severity: InsightSeverity.medium,
      coachNotice: "Hydration below 2L for $streak consecutive days.",
      userMessage: "You've had less than 2L water for "
          '$streak days in a row.',
    );
  }

  // ── 7. Missed Workouts ───────────────────────────────────── MEDIUM

  /// IF no workout for 4+ days.
  CoachingInsight? _missedWorkouts() {
    final daysSince = _workouts.getDaysSinceLastWorkout();
    if (daysSince < 4) return null;

    return CoachingInsight(
      patternId: 'missed_workouts',
      severity: InsightSeverity.medium,
      coachNotice: "No workout logged in $daysSince days.",
      userMessage: "It's been $daysSince days since your last workout. "
          "Time to get moving!",
    );
  }

  // ── 8. Goal Drift ────────────────────────────────────────── MEDIUM

  /// IF goal=fat_loss AND calories > TDEE for 4+ days this week.
  CoachingInsight? _goalDrift() {
    final profile = _user.getProfile();
    if (profile == null) return null;
    final goal = profile['primary_goal'] as String? ?? '';
    if (goal != 'lose_fat') return null;

    final tdee = (profile['tdee'] as num?)?.toInt() ?? 0;
    if (tdee <= 0) return null;

    final now = DateTime.now();
    int daysAbove = 0;

    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = _formatDate(date);
      final cal = _nutrition.getCaloriesForDate(dateStr);

      // Only count days with actual logging.
      if (cal > 0 && cal > tdee) {
        daysAbove++;
      }
    }

    if (daysAbove < 4) return null;

    return CoachingInsight(
      patternId: 'goal_drift',
      severity: InsightSeverity.medium,
      coachNotice: "Goal: fat loss. Calories above maintenance "
          "$daysAbove of last 7 days.",
      userMessage: 'You exceeded your calorie target $daysAbove of '
          'the last 7 days. Stay on track with your fat loss goal!',
    );
  }

  // ── 9. Recovery Enforcer ─────────────────────────────────── MEDIUM

  /// IF 6+ workouts in last 7 days.
  CoachingInsight? _recoveryEnforcer() {
    final count = _workouts.getWorkoutsInLastDays(days: 7);
    if (count < 6) return null;

    return CoachingInsight(
      patternId: 'recovery_enforcer',
      severity: InsightSeverity.medium,
      coachNotice: "$count workouts in 7 days. No rest day. "
          "Recovery risk.",
      userMessage: "$count workouts in 7 days! "
          "Take a rest day for proper recovery.",
    );
  }

  // ── 10. Day-of-Week Pattern ──────────────────────────────── MEDIUM

  /// IF any day has <50% completion rate over 8 weeks.
  CoachingInsight? _dayOfWeekPattern() {
    final rates = _workouts.getDayOfWeekCompletionRates(weeks: 8);

    // Find the worst day with enough data (at least some scheduled).
    String? worstDay;
    double worstRate = 1.0;

    for (final entry in rates.entries) {
      if (entry.value < 0.5 && entry.value < worstRate) {
        worstRate = entry.value;
        worstDay = entry.key;
      }
    }

    if (worstDay == null) return null;

    final pct = (worstRate * 100).round();

    return CoachingInsight(
      patternId: 'day_of_week_pattern',
      severity: InsightSeverity.medium,
      coachNotice: "Skips $worstDay workouts ${100 - pct}% of the time.",
      userMessage: 'You tend to skip $worstDay workouts '
          '(only $pct% completion). Consider swapping that day.',
    );
  }

  // ── 11. Milestone Countdown ──────────────────────────────── LOW

  /// IF total_workouts within 3 of 50/100/200/365.
  CoachingInsight? _milestoneCountdown() {
    final progress = _user.getProgress();
    if (progress == null) return null;

    final total =
        (progress['total_workouts_done'] as num?)?.toInt() ?? 0;
    if (total <= 0) return null;

    const milestones = [50, 100, 200, 365, 500, 1000];

    for (final milestone in milestones) {
      final remaining = milestone - total;
      if (remaining > 0 && remaining <= 3) {
        return CoachingInsight(
          patternId: 'milestone_$milestone',
          severity: InsightSeverity.low,
          coachNotice: "$remaining workouts from $milestone total.",
          userMessage: 'Just $remaining more workouts to hit $milestone! '
              "You're at $total now.",
        );
      }
    }

    return null;
  }

  // ── 12. Weekend Nutrition ────────────────────────────────── LOW

  /// IF weekend avg > weekday avg by 25%+ for 4+ weeks.
  CoachingInsight? _weekendNutrition() {
    final data = _nutrition.getWeekdayVsWeekendCalories(weeks: 4);
    final delta = (data['delta_percent'] as num?)?.toDouble() ?? 0;
    final weekdayAvg = (data['weekday_avg'] as num?)?.toDouble() ?? 0;
    final weekendAvg = (data['weekend_avg'] as num?)?.toDouble() ?? 0;

    // Need real data in both groups.
    if (weekdayAvg <= 0 || weekendAvg <= 0) return null;
    if (delta < 25) return null;

    final pct = delta.round();

    return CoachingInsight(
      patternId: 'weekend_nutrition',
      severity: InsightSeverity.low,
      coachNotice: "Weekend calories consistently $pct% higher "
          "than weekdays. Weekday avg: ${weekdayAvg.round()}, "
          "Weekend avg: ${weekendAvg.round()}.",
      userMessage: 'Weekend eating is $pct% higher than weekdays '
          '(${weekendAvg.round()} vs ${weekdayAvg.round()} cal).',
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
