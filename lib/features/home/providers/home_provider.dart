import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

// ── Calendar Day Data ───────────────────────────────────────────

/// Status of a single day in the weekly calendar strip.
enum CalendarDayStatus {
  /// Workout is scheduled but not yet done.
  planned,

  /// Workout was completed.
  completed,

  /// Rest day — no workout scheduled.
  rest,

  /// Past day with a planned workout that was not completed.
  missed,

  /// Day is marked as travel mode.
  travel,

  /// No plan data for this date (outside plan range).
  none,
}

/// Data for one day in the 7-day calendar strip.
class CalendarDayData {
  final DateTime date;
  final String dayName; // M, T, W, T, F, S, S
  final CalendarDayStatus status;
  final bool isToday;
  final bool isSwapped;
  final String? workoutName;

  const CalendarDayData({
    required this.date,
    required this.dayName,
    required this.status,
    required this.isToday,
    this.isSwapped = false,
    this.workoutName,
  });
}

/// Provider that exposes the 7-day calendar strip data.
///
/// Queries Hive workoutBox via [WorkoutScheduleService] for the current
/// week (Mon-Sun) and returns a [CalendarDayData] per day with the
/// correct status: planned, completed, rest, missed, travel, or none.
class CalendarWeekNotifier extends Notifier<List<CalendarDayData>> {
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  List<CalendarDayData> build() {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final weekStart = todayDate.subtract(Duration(days: now.weekday - 1));
    final service = WorkoutScheduleService.instance;

    final result = <CalendarDayData>[];
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final schedule = service.getScheduleForDate(date);
      final isToday = date == todayDate;
      final isPast = date.isBefore(todayDate);

      final type = schedule?['type'] as String? ?? 'none';
      final statusStr = schedule?['status'] as String? ?? 'none';
      final isSwapped = schedule?['is_swapped'] as bool? ?? false;
      final workoutName = schedule?['workout_name'] as String?;

      CalendarDayStatus status;
      if (statusStr == 'completed') {
        status = CalendarDayStatus.completed;
      } else if (statusStr == 'travel') {
        status = CalendarDayStatus.travel;
      } else if ((type == 'workout' || type == 'custom_template') && statusStr == 'planned') {
        // Past day with planned workout that wasn't done = missed
        status = isPast && !isToday
            ? CalendarDayStatus.missed
            : CalendarDayStatus.planned;
      } else if (type == 'rest' || statusStr == 'rest') {
        status = CalendarDayStatus.rest;
      } else {
        status = CalendarDayStatus.none;
      }

      result.add(CalendarDayData(
        date: date,
        dayName: _dayLabels[i],
        status: status,
        isToday: isToday,
        isSwapped: isSwapped,
        workoutName: workoutName,
      ));
    }
    return result;
  }

  /// Force refresh when workout status changes (e.g. after completing a workout).
  void refresh() {
    ref.invalidateSelf();
  }
}

final calendarWeekProvider =
    NotifierProvider<CalendarWeekNotifier, List<CalendarDayData>>(
        CalendarWeekNotifier.new);

// ── User Greeting ────────────────────────────────────────────────

class UserGreetingNotifier extends Notifier<String> {
  @override
  String build() {
    final profile = UserRepository.instance.getProfile();
    final name = profile?['full_name'] as String? ?? 'there';
    final firstName = name.split(' ').first;
    final hour = DateTime.now().hour;

    String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    return '$greeting, $firstName';
  }
}

final userGreetingProvider =
    NotifierProvider<UserGreetingNotifier, String>(UserGreetingNotifier.new);

// ── User First Name ──────────────────────────────────────────────

class UserFirstNameNotifier extends Notifier<String> {
  @override
  String build() {
    final profile = UserRepository.instance.getProfile();
    final name = profile?['full_name'] as String? ?? 'User';
    return name.split(' ').first.toUpperCase();
  }
}

final userFirstNameProvider =
    NotifierProvider<UserFirstNameNotifier, String>(UserFirstNameNotifier.new);

// ── User Initial ─────────────────────────────────────────────────

class UserInitialNotifier extends Notifier<String> {
  @override
  String build() {
    final profile = UserRepository.instance.getProfile();
    final name = profile?['full_name'] as String? ?? 'U';
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }
}

final userInitialProvider =
    NotifierProvider<UserInitialNotifier, String>(UserInitialNotifier.new);

// ── Streak ───────────────────────────────────────────────────────

class StreakNotifier extends Notifier<int> {
  @override
  int build() {
    final progress = UserRepository.instance.getProgress();
    // Show daily streak (consecutive workout days) — more intuitive for users
    return (progress?['current_streak_days'] as int?) ?? 0;
  }
}

final streakProvider =
    NotifierProvider<StreakNotifier, int>(StreakNotifier.new);

// ── Streak Freeze ────────────────────────────────────────────────

class StreakFreezeNotifier extends Notifier<int> {
  @override
  int build() {
    _refillIfNewWeek();
    final progress = UserRepository.instance.getProgress();
    return (progress?['streak_freezes_available'] as int?) ?? 1;
  }

  /// Refills streak freezes weekly. Runs on any app launch — checks if the
  /// most recent Monday has passed since last refill. FREE=1, PRO=3.
  void _refillIfNewWeek() {
    final now = DateTime.now();
    final progress = UserRepository.instance.getProgress() ?? {};
    final lastRefill = progress['streak_freezes_last_refill'] as String?;

    // Calculate this week's Monday (00:00)
    final daysSinceMonday = (now.weekday - DateTime.monday) % 7;
    final thisMonday = DateTime(now.year, now.month, now.day - daysSinceMonday);
    final thisMondayStr = thisMonday.toIso8601String().substring(0, 10);

    // Already refilled for this week's Monday
    if (lastRefill != null && lastRefill.compareTo(thisMondayStr) >= 0) return;

    final isPro = SubscriptionService.instance.isPro();
    final maxFreezes = isPro ? 3 : 1;

    UserRepository.instance.updateProgress({
      'streak_freezes_available': maxFreezes,
      'streak_freeze_used_dates': <String>[], // Reset weekly used dates
      'streak_freezes_last_refill': thisMondayStr,
    });
  }
}

final streakFreezeProvider =
    NotifierProvider<StreakFreezeNotifier, int>(StreakFreezeNotifier.new);

// ── Streak Warning Eligibility (Bug #12) ─────────────────────────

/// Bug #12 — Derived inputs for the smart streak warning banner.
///
/// The old logic fired on Sat/Sun mornings regardless of context, which is
/// useless for users with mid-week schedules and annoying for early-morning
/// trainers. This provider replaces it with personalised, time-aware logic:
///
/// 1. **Median workout hour** — read from last 10 completed workouts
///    (more robust than mean against outlier sessions). Falls back to
///    19:00 IST for new users with <3 logs.
/// 2. **isWorkoutDayToday** — today's schedule must be a workout entry
///    (not rest, not none).
/// 3. **isTodayCompleted** — today's workout must NOT already be done.
///
/// The actual show/hide decision lives in [StreakWarningBanner.shouldShow]
/// which applies a 15:00 floor and 23:00 ceiling on top of (median + 3).
class StreakWarningEligibility {
  /// True when ALL guards pass: workout day, not yet completed, time of
  /// day past the user's personalised threshold.
  final bool shouldShow;
  /// Computed median completion hour with cold-start fallback (19:00).
  /// Useful for diagnostics — and for tests that want to assert the math.
  final int medianWorkoutHour;
  /// Whether today is a workout day per Hive schedule.
  final bool isWorkoutDayToday;
  /// Whether today's workout is already marked completed.
  final bool isTodayCompleted;

  const StreakWarningEligibility({
    required this.shouldShow,
    required this.medianWorkoutHour,
    required this.isWorkoutDayToday,
    required this.isTodayCompleted,
  });
}

class StreakWarningEligibilityNotifier
    extends Notifier<StreakWarningEligibility> {
  @override
  StreakWarningEligibility build() {
    final streakDays = ref.watch(streakProvider);
    final todaySchedule = ref.watch(todayWorkoutProvider);

    // 1. Is today a workout day? Read from today's schedule entry.
    //    `workout` and `custom_template` are both real workout days.
    //    `rest` and missing entries are not.
    final type = todaySchedule?['type'] as String? ?? 'none';
    final status = todaySchedule?['status'] as String? ?? 'none';
    final isWorkoutDayToday = type == 'workout' || type == 'custom_template';

    // 2. Has today's workout already been completed?
    final isTodayCompleted = status == 'completed';

    // 3. Personalised median workout hour with cold-start fallback.
    //    <3 logs → 19:00 IST default (sensible "after evening" threshold).
    //    Otherwise → median of last 10 completion hours.
    final hours =
        WorkoutRepository.instance.getRecentWorkoutCompletionHours(limit: 10);
    final int medianHour;
    if (hours.length < 3) {
      medianHour = 19;
    } else {
      final sorted = [...hours]..sort();
      final mid = sorted.length ~/ 2;
      medianHour = sorted.length.isOdd
          ? sorted[mid]
          : ((sorted[mid - 1] + sorted[mid]) / 2).round();
    }

    // Reuse the pure decision logic in StreakWarningBanner.shouldShow so
    // the rules stay in one place and remain unit-testable.
    final show = _evaluate(
      streakDays: streakDays,
      isWorkoutDayToday: isWorkoutDayToday,
      isTodayCompleted: isTodayCompleted,
      medianWorkoutHour: medianHour,
    );

    return StreakWarningEligibility(
      shouldShow: show,
      medianWorkoutHour: medianHour,
      isWorkoutDayToday: isWorkoutDayToday,
      isTodayCompleted: isTodayCompleted,
    );
  }

  /// Inline copy of [StreakWarningBanner.shouldShow]'s rule so we don't have
  /// to import the widget into the provider layer. The widget keeps the
  /// public method as the canonical reference; this is a passthrough.
  bool _evaluate({
    required int streakDays,
    required bool isWorkoutDayToday,
    required bool isTodayCompleted,
    required int medianWorkoutHour,
  }) {
    if (streakDays == 0) return false;
    if (!isWorkoutDayToday) return false;
    if (isTodayCompleted) return false;

    final currentHour = DateTime.now().hour;
    final rawThreshold = medianWorkoutHour + 3;
    final thresholdHour = rawThreshold.clamp(15, 23);
    return currentHour >= thresholdHour;
  }
}

final streakWarningEligibilityProvider = NotifierProvider<
    StreakWarningEligibilityNotifier,
    StreakWarningEligibility>(StreakWarningEligibilityNotifier.new);

// ── Today's Workout ──────────────────────────────────────────────

class TodayWorkoutNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() {
    // Read today's schedule from WorkoutScheduleService (single source of truth)
    return WorkoutScheduleService.instance.getScheduleForDate(DateTime.now());
  }
}

final todayWorkoutProvider =
    NotifierProvider<TodayWorkoutNotifier, Map<String, dynamic>?>(
        TodayWorkoutNotifier.new);

// ── Nutrition Summary ────────────────────────────────────────────

class NutritionSummaryData {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double calorieTarget;
  final double proteinTarget;
  final double carbTarget;
  final double fatTarget;

  const NutritionSummaryData({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.calorieTarget = 2000,
    this.proteinTarget = 120,
    this.carbTarget = 250,
    this.fatTarget = 65,
  });
}

class NutritionSummaryNotifier extends Notifier<NutritionSummaryData> {
  @override
  NutritionSummaryData build() {
    final hive = HiveService.instance;
    final nutritionBox = hive.nutritionBox;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] == todayStr) {
        calories += (log['total_calories'] as num?)?.toDouble() ?? 0;
        protein += (log['total_protein'] as num?)?.toDouble() ?? 0;
        carbs += (log['total_carbs'] as num?)?.toDouble() ?? 0;
        fat += (log['total_fat'] as num?)?.toDouble() ?? 0;
      }
    }

    // Get targets from profile
    final profile = UserRepository.instance.getProfile();
    final calorieTarget =
        (profile?['daily_calories'] as num?)?.toDouble() ?? 2000;
    final proteinTarget =
        (profile?['protein_grams'] as num?)?.toDouble() ?? 120;
    final carbTarget = (profile?['carb_grams'] as num?)?.toDouble() ?? 250;
    final fatTarget = (profile?['fat_grams'] as num?)?.toDouble() ?? 65;

    return NutritionSummaryData(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      calorieTarget: calorieTarget,
      proteinTarget: proteinTarget,
      carbTarget: carbTarget,
      fatTarget: fatTarget,
    );
  }
}

final nutritionSummaryProvider =
    NotifierProvider<NutritionSummaryNotifier, NutritionSummaryData>(
        NutritionSummaryNotifier.new);

// ── Weight History ───────────────────────────────────────────────

/// Returns ALL weight entries sorted by date (the widget handles filtering).
class WeightHistoryNotifier extends Notifier<List<WeightEntryData>> {
  @override
  List<WeightEntryData> build() {
    final hive = HiveService.instance;
    final healthBox = hive.healthBox;

    final entries = <WeightEntryData>[];
    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'weight_log' || log['weight_kg'] != null) {
        final date = log['date'] as String? ?? '';
        final weight = (log['weight_kg'] as num?)?.toDouble();
        if (weight != null && date.isNotEmpty) {
          entries.add(WeightEntryData(date: date, weight: weight));
        }
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }
}

class WeightEntryData {
  final String date;
  final double weight;
  const WeightEntryData({required this.date, required this.weight});
}

final weightHistoryProvider =
    NotifierProvider<WeightHistoryNotifier, List<WeightEntryData>>(
        WeightHistoryNotifier.new);

// ── Latest AI Coach Insight ──────────────────────────────────────

class AiInsightNotifier extends Notifier<String?> {
  @override
  String? build() {
    final now = DateTime.now();

    // 1. Always compute insight from LOCAL schedule data (source of truth)
    final insight = _computeScheduleInsight(now);

    // 2. Optionally append a coach tip from today's latest AI interaction
    final coachTip = _getLatestCoachTip(now);
    if (coachTip != null) {
      return '$insight\n💡 $coachTip';
    }

    return insight;
  }

  /// Build insight from today's workout schedule in Hive.
  String _computeScheduleInsight(DateTime now) {
    final schedule = WorkoutScheduleService.instance.getScheduleForDate(now);
    if (schedule != null) {
      final type = schedule['type'] as String? ?? 'rest';
      final status = schedule['status'] as String? ?? 'planned';
      final name = schedule['workout_name'] as String? ?? 'Workout';
      final exercises = schedule['exercises'] as List? ?? [];
      if (status == 'completed') {
        return '$name completed today — ${exercises.length} exercises. Great work 💪';
      } else if (type == 'workout' || type == 'custom_template') {
        return '$name is scheduled for today — ${exercises.length} exercises. Ready when you are!';
      } else if (type == 'rest') {
        return 'Rest day today. Recovery is part of the plan 🧘';
      }
    }
    return 'No workout scheduled for today. A good day for active recovery!';
  }

  /// Extract a short tip from the latest AI coach response today.
  /// Returns the last sentence (≤80 chars) or null.
  String? _getLatestCoachTip(DateTime now) {
    final coachBox = HiveService.instance.coachBox;
    final todayPrefix = formatDateKey(now);
    String? latestResponse;
    String latestDate = '';

    for (final raw in coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      if (!createdAt.startsWith(todayPrefix)) continue;
      final response = interaction['ai_response'] as String?;
      if (response != null && createdAt.compareTo(latestDate) > 0) {
        latestDate = createdAt;
        latestResponse = response;
      }
    }

    if (latestResponse == null) return null;

    // Extract last sentence as a concise tip — skip if it's too long
    final sentences = latestResponse.split(RegExp(r'[.!?]\s+'));
    final tip = sentences.last.trim();
    if (tip.length > 80 || tip.length < 10) return null;
    return tip;
  }
}

final aiInsightProvider =
    NotifierProvider<AiInsightNotifier, String?>(AiInsightNotifier.new);

// ── Recent Food Logs ─────────────────────────────────────────────

class RecentFoodLogEntry {
  final String name;
  final double protein;
  final double carbs;
  final double fat;
  final double calories;

  const RecentFoodLogEntry({
    required this.name,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.calories,
  });
}

class RecentFoodLogsNotifier extends Notifier<List<RecentFoodLogEntry>> {
  @override
  List<RecentFoodLogEntry> build() {
    final hive = HiveService.instance;
    final nutritionBox = hive.nutritionBox;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final logs = <RecentFoodLogEntry>[];
    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] == todayStr) {
        final name = log['food_name'] as String? ??
            log['meal_name'] as String? ??
            log['name'] as String? ??
            'Unknown';
        logs.add(RecentFoodLogEntry(
          name: name,
          protein: (log['total_protein'] as num?)?.toDouble() ?? 0,
          carbs: (log['total_carbs'] as num?)?.toDouble() ?? 0,
          fat: (log['total_fat'] as num?)?.toDouble() ?? 0,
          calories: (log['total_calories'] as num?)?.toDouble() ?? 0,
        ));
      }
    }

    return logs;
  }
}

final recentFoodLogsProvider =
    NotifierProvider<RecentFoodLogsNotifier, List<RecentFoodLogEntry>>(
        RecentFoodLogsNotifier.new);

// ── Daily Quote ────────────────────────────────────────────────────

class DailyQuoteData {
  final String quote;
  final String author;

  const DailyQuoteData({required this.quote, required this.author});
}

class DailyQuoteNotifier extends Notifier<DailyQuoteData> {
  static const _defaultQuotes = [
    DailyQuoteData(
      quote: 'The only bad workout is the one that didn\'t happen.',
      author: 'Unknown',
    ),
    DailyQuoteData(
      quote: 'Take care of your body. It\'s the only place you have to live.',
      author: 'Jim Rohn',
    ),
    DailyQuoteData(
      quote: 'Strength does not come from the body. It comes from the will.',
      author: 'Gandhi',
    ),
    DailyQuoteData(
      quote: 'The pain you feel today will be the strength you feel tomorrow.',
      author: 'Arnold Schwarzenegger',
    ),
    DailyQuoteData(
      quote: 'Fitness is not about being better than someone else. It\'s about being better than you used to be.',
      author: 'Khloe Kardashian',
    ),
    DailyQuoteData(
      quote: 'Your body can stand almost anything. It\'s your mind that you have to convince.',
      author: 'Andrew Murphy',
    ),
    DailyQuoteData(
      quote: 'Success isn\'t always about greatness. It\'s about consistency.',
      author: 'Dwayne Johnson',
    ),
  ];

  @override
  DailyQuoteData build() {
    // Use day of year as index to rotate quotes daily.
    final dayOfYear = DateTime.now().difference(
      DateTime(DateTime.now().year, 1, 1),
    ).inDays;
    final index = dayOfYear % _defaultQuotes.length;
    return _defaultQuotes[index];
  }
}

final dailyQuoteProvider =
    NotifierProvider<DailyQuoteNotifier, DailyQuoteData>(
        DailyQuoteNotifier.new);

// ── Today's Steps ─────────────────────────────────────────────────

class TodayStepsNotifier extends Notifier<int> {
  @override
  int build() {
    final hive = HiveService.instance;
    final healthBox = hive.healthBox;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'step_log' && log['date'] == todayStr) {
        return (log['steps'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }
}

final todayStepsProvider =
    NotifierProvider<TodayStepsNotifier, int>(TodayStepsNotifier.new);

// ── Weight Log ────────────────────────────────────────────────────

class WeightLogNotifier extends Notifier<void> {
  @override
  void build() {}

  void logWeight(double weightKg) {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final healthBox = HiveService.instance.healthBox;
    healthBox.put('weight_$dateStr', {
      'type': 'weight_log',
      'date': dateStr,
      'weight_kg': weightKg,
      'created_at': today.toIso8601String(),
    });
    // Also update profile current_weight_kg
    final userBox = HiveService.instance.userBox;
    final profile =
        Map<String, dynamic>.from(userBox.get('profile') as Map? ?? {});
    profile['current_weight_kg'] = weightKg;
    userBox.put('profile', profile);
    BadgeService.instance.checkAll();
  }
}

final weightLogNotifierProvider =
    NotifierProvider<WeightLogNotifier, void>(WeightLogNotifier.new);

// ── Today Weight Logged Check ────────────────────────────────────

class TodayWeightLoggedNotifier extends Notifier<bool> {
  @override
  bool build() {
    final healthBox = HiveService.instance.healthBox;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return healthBox.get('weight_$todayStr') != null;
  }

  void refresh() => ref.invalidateSelf();
}

final todayWeightLoggedProvider =
    NotifierProvider<TodayWeightLoggedNotifier, bool>(
        TodayWeightLoggedNotifier.new);

// ── All Exercise PRs ─────────────────────────────────────────────

/// Loads PR records for every exercise the user has ever logged.
/// Invalidated by [completeWorkout()] so home screen refreshes immediately.
class AllExercisePRsNotifier extends Notifier<List<ExercisePR>> {
  @override
  List<ExercisePR> build() {
    return WorkoutRepository.instance.loadAllExercisePRs();
  }
}

final allExercisePRsProvider =
    NotifierProvider<AllExercisePRsNotifier, List<ExercisePR>>(
        AllExercisePRsNotifier.new);
