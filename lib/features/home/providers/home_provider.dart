import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

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

class WeightHistoryNotifier extends Notifier<List<double>> {
  @override
  List<double> build() {
    final hive = HiveService.instance;
    final healthBox = hive.healthBox;

    final entries = <MapEntry<String, double>>[];
    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'weight_log' || log['weight_kg'] != null) {
        final date = log['date'] as String? ?? '';
        final weight = (log['weight_kg'] as num?)?.toDouble();
        if (weight != null) {
          entries.add(MapEntry(date, weight));
        }
      }
    }

    // Sort by date and take last 7
    entries.sort((a, b) => a.key.compareTo(b.key));
    final last7 = entries.length > 7
        ? entries.sublist(entries.length - 7)
        : entries;

    return last7.map((e) => e.value).toList();
  }
}

final weightHistoryProvider =
    NotifierProvider<WeightHistoryNotifier, List<double>>(
        WeightHistoryNotifier.new);

// ── Latest AI Coach Insight ──────────────────────────────────────

class AiInsightNotifier extends Notifier<String?> {
  @override
  String? build() {
    final hive = HiveService.instance;
    final coachBox = hive.coachBox;

    String? latestMessage;
    String latestDate = '';

    for (final raw in coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      final response = interaction['ai_response'] as String?;
      if (response != null && createdAt.compareTo(latestDate) > 0) {
        latestDate = createdAt;
        latestMessage = response;
      }
    }

    return latestMessage;
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
