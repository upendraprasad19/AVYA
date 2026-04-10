import 'dart:async';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import '../repositories/workout_repository.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

// ── Last Performance Data ────────────────────────────────────────

class LastPerformanceData {
  final double? lastWeight;
  final int? lastReps;
  final int? lastSets;
  final DateTime? lastDate;
  final double? suggestedWeight; // lastWeight + 2.5 (or null for bodyweight/timed/cardio)

  const LastPerformanceData({
    this.lastWeight,
    this.lastReps,
    this.lastSets,
    this.lastDate,
    this.suggestedWeight,
  });

  bool get hasData => lastWeight != null || lastReps != null;
}

LastPerformanceData _getLastPerformance(String exerciseName) {
  final hive = HiveService.instance;
  final nameLower = exerciseName.toLowerCase();

  DateTime? latestDate;
  double? lastWeight;
  int? lastReps;
  int? lastSets;
  String? loggingType;

  for (final raw in hive.workoutBox.values) {
    if (raw is! Map) continue;
    final log = Map<String, dynamic>.from(raw);
    if (log['type'] != 'exercise_log') continue;

    final logName = (log['exercise_name'] as String? ?? '').toLowerCase();
    if (logName.isEmpty) continue;
    // Exact match first; fuzzy contains only when both names are long enough
    // to avoid false positives like "Press" matching "Leg Press"
    if (logName != nameLower) {
      if (nameLower.length < 6 || logName.length < 6) continue;
      if (!logName.contains(nameLower) && !nameLower.contains(logName)) continue;
    }

    final dateStr = log['date'] as String?;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null) continue;

    if (latestDate == null || date.isAfter(latestDate)) {
      latestDate = date;
      lastWeight = (log['weight_kg'] as num?)?.toDouble();
      lastReps = (log['reps_completed'] as int?);
      lastSets = (log['sets_completed'] as int?);
      loggingType = log['logging_type'] as String?;
    }
  }

  double? suggested;
  if (lastWeight != null &&
      lastWeight > 0 &&
      (loggingType == 'weight_reps' || loggingType == 'weighted_bodyweight')) {
    suggested = lastWeight + 2.5;
  }

  return LastPerformanceData(
    lastWeight: lastWeight,
    lastReps: lastReps,
    lastSets: lastSets,
    lastDate: latestDate,
    suggestedWeight: suggested,
  );
}

final lastPerformanceProvider =
    Provider.family<LastPerformanceData, String>((ref, exerciseName) {
  return _getLastPerformance(exerciseName);
});

final exerciseHistoryProvider =
    Provider.family<List<double>, String>((ref, exerciseName) {
  final hive = HiveService.instance;
  final nameLower = exerciseName.toLowerCase();
  final entries = <MapEntry<DateTime, double>>[];

  for (final raw in hive.workoutBox.values) {
    if (raw is! Map) continue;
    final log = Map<String, dynamic>.from(raw);
    if (log['type'] != 'exercise_log') continue;

    final logName = (log['exercise_name'] as String? ?? '').toLowerCase();
    if (logName.isEmpty) continue;
    if (logName != nameLower) {
      if (nameLower.length < 6 || logName.length < 6) continue;
      if (!logName.contains(nameLower) && !nameLower.contains(logName)) continue;
    }

    final weight = (log['weight_kg'] as num?)?.toDouble();
    if (weight == null || weight <= 0) continue;

    final dateStr = log['date'] as String?;
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
    if (date == null) continue;

    entries.add(MapEntry(date, weight));
  }

  entries.sort((a, b) => a.key.compareTo(b.key));

  final weights = entries.map((e) => e.value).toList();
  if (weights.length > 8) {
    return weights.sublist(weights.length - 8);
  }
  return weights;
});

// ── Data Classes ────────────────────────────────────────────────

/// Exercise data used within a workout day.
class ExerciseData {
  final String name;
  final String sets;
  final String reps;
  final String weight;
  final String rest;
  final String loggingType;
  final String? category;
  final List<String>? equipmentNeeded;
  final String? exerciseType; // 'compound' or 'isolation'
  final int? supersetGroup; // null = standalone, 0/1/2... = superset group index

  const ExerciseData({
    required this.name,
    this.sets = '3',
    this.reps = '10',
    this.weight = '0kg',
    this.rest = '90s',
    this.loggingType = 'weight_reps',
    this.category,
    this.equipmentNeeded,
    this.exerciseType,
    this.supersetGroup,
  });

  ExerciseData copyWith({
    String? name,
    String? sets,
    String? reps,
    String? weight,
    String? rest,
    String? loggingType,
    String? category,
    List<String>? equipmentNeeded,
    String? exerciseType,
    int? Function()? supersetGroup,
  }) {
    return ExerciseData(
      name: name ?? this.name,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
      rest: rest ?? this.rest,
      loggingType: loggingType ?? this.loggingType,
      category: category ?? this.category,
      equipmentNeeded: equipmentNeeded ?? this.equipmentNeeded,
      exerciseType: exerciseType ?? this.exerciseType,
      supersetGroup: supersetGroup != null ? supersetGroup() : this.supersetGroup,
    );
  }

  /// Whether this exercise is a compound movement (for warm-up auto-suggest).
  bool get isCompound {
    if (exerciseType?.toLowerCase() == 'compound') return true;
    final nameLower = name.toLowerCase();
    return nameLower.contains('bench') ||
        nameLower.contains('squat') ||
        nameLower.contains('deadlift') ||
        nameLower.contains('overhead press') ||
        nameLower.contains('barbell row') ||
        nameLower.contains('pull-up') ||
        nameLower.contains('dip');
  }
}

/// A single day in the workout plan.
class WorkoutDayData {
  final int dayNumber;
  final String name;
  final String subtitle;
  final String? dateLabel; // e.g. "Mon, Mar 24"
  final DateTime? date; // actual calendar date
  final bool isRest;
  final bool isDone;
  final List<ExerciseData> exercises;
  final List<ExerciseData> warmup;
  final List<ExerciseData> cooldown;

  const WorkoutDayData({
    required this.dayNumber,
    required this.name,
    this.subtitle = '',
    this.dateLabel,
    this.date,
    this.isRest = false,
    this.isDone = false,
    this.exercises = const [],
    this.warmup = const [],
    this.cooldown = const [],
  });

  int get exerciseCount => exercises.length;
  String get estimatedDuration {
    if (isRest) return '';
    final totalSets =
        exercises.fold<int>(0, (sum, e) => sum + (int.tryParse(e.sets) ?? 3));
    return '${(totalSets * 2.5).round()} min';
  }
}

// ── Swap exercise data ──────────────────────────────────────────

class SwapExerciseData {
  final String name;
  final String detail;
  final String emoji;

  const SwapExerciseData({
    required this.name,
    required this.detail,
    this.emoji = '',
  });
}

// sampleSwapExercises removed — ExerciseSwapSheet queries Hive exerciseBox
// via ExerciseRepository.instance directly.

// ── Exercise map parser (shared for exercises, warmup, cooldown) ──

List<ExerciseData> _parseExerciseMaps(List? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw.map((e) {
    final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
    final equipRaw = m['equipment_needed'];
    final equipList = equipRaw is List
        ? equipRaw.map((e) => e.toString()).toList()
        : <String>[];

    String? category = m['category'] as String?;
    if (category == null || category.isEmpty) {
      final name = (m['exercise_name'] as String? ?? '').toLowerCase();
      final exId = m['exercise_id'] as String?;
      if (exId != null && exId.isNotEmpty) {
        final libEx = ExerciseRepository.instance.getById(exId);
        category = libEx?['category'] as String?;
      }
      if (category == null || category.isEmpty) {
        final results = ExerciseRepository.instance.search(name);
        if (results.isNotEmpty) {
          category = results.first['category'] as String?;
        }
      }
    }

    return ExerciseData(
      name: m['exercise_name'] as String? ?? m['name'] as String? ?? 'Unknown',
      sets: '${m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3}',
      reps: m['reps'] as String? ?? m['prescribed_reps'] as String? ?? m['default_reps'] as String? ?? '10',
      weight: '0kg',
      rest: '${m['rest_seconds'] ?? 60}s',
      loggingType: m['logging_type'] as String? ?? 'weight_reps',
      category: category,
      equipmentNeeded: equipList,
      exerciseType: m['exercise_type'] as String?,
      supersetGroup: m['superset_group'] as int?,
    );
  }).toList();
}

// ── Current Plan ─────────────────────────────────────────────────

class CurrentPlanData {
  final int phase;
  final String phaseName;
  final int currentWeek;
  final String focus;
  final List<List<WorkoutDayData>> weeks;
  final bool hasPlan;
  final bool isGenerating; // true when plan generation is in progress

  const CurrentPlanData({
    this.phase = 1,
    this.phaseName = 'Foundation',
    this.currentWeek = 1,
    this.focus = 'Movement patterns & baseline strength',
    this.weeks = const [],
    this.hasPlan = false,
    this.isGenerating = false,
  });

  /// Get workouts for a specific week (1-indexed).
  List<WorkoutDayData> getWeek(int weekNumber) {
    final index = weekNumber - 1;
    if (index < 0 || index >= weeks.length) return [];
    return weeks[index];
  }

  /// Get today's workout (first non-rest, non-done workout in current week).
  WorkoutDayData? get todayWorkout {
    final weekDays = getWeek(currentWeek);
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // First, try to find the workout for today's actual date.
    for (final day in weekDays) {
      if (day.date != null) {
        final dayStr = formatDateKey(day.date!);
        if (dayStr == todayStr && !day.isRest && !day.isDone) return day;
      }
    }

    // Fallback: first non-rest, non-done workout in current week.
    for (final day in weekDays) {
      if (!day.isRest && !day.isDone) return day;
    }
    return null;
  }
}

class CurrentPlanNotifier extends Notifier<CurrentPlanData> {
  /// Auto-generates a workout plan from local Hive profile data.
  ///
  /// Fire-and-forget async: after the plan is written to Hive,
  /// [ref.invalidateSelf()] triggers a rebuild so the UI picks up the new data.
  /// Also ensures exerciseBox is seeded before generation.
  void _autoGeneratePlan(
      Map<String, dynamic> profile, Map<String, dynamic>? progress) {
    final goal = profile['primary_goal'] as String? ?? 'general_fitness';
    final equipment = profile['equipment_access'] as String? ?? 'basic_gym';
    final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
    final experience = profile['fitness_experience'] as String? ?? 'beginner';
    final phase = (progress?['current_phase'] as int?) ?? 1;

    // Fire-and-forget async: generation writes to Hive, then invalidateSelf
    // triggers build() to re-run with the newly written plan data.
    () async {
      try {
        // Guard: ensure exercise data is seeded before generation.
        final exerciseBox = HiveService.instance.exerciseBox;
        if (exerciseBox.isEmpty) {
          await SeedService.instance.seedIfNeeded();
          // If still empty after seeding, abort — no exercises to build a plan from.
          if (exerciseBox.isEmpty) return;
        }

        // Read saved preferred training days (user-selected day picker).
        final savedDays = HiveService.instance.configBox
            .get('preferred_training_days');
        final preferredDays = savedDays is List
            ? savedDays.cast<int>()
            : null;

        await WorkoutScheduleService.instance.generateAndSchedule(
          goal: goal,
          equipment: equipment,
          daysPerWeek: daysPerWeek,
          startDate: DateTime.now(),
          experienceLevel: experience,
          phase: phase,
          preferredDays: preferredDays,
        );

        // KEY FIX: Invalidate self AFTER generation completes so build()
        // re-runs and reads the freshly written plan from Hive.
        ref.invalidateSelf();
        // Also refresh home calendar so newly scheduled days appear immediately.
        ref.invalidate(calendarWeekProvider);
      } catch (e) {
        // Log but don't crash — plan generation failure is non-fatal.
        // User will see empty state and can retry via pull-to-refresh.
      }
    }();
  }

  @override
  CurrentPlanData build() {
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress();
    final phase = (progress?['current_phase'] as int?) ?? 1;
    // Use calendar-based week (derived from plan_start_date + today) so the
    // "Week N hasn't started yet" message is always accurate.  Falls back to
    // the Hive-stored value when no plan is scheduled yet.
    final calendarWeek = WorkoutScheduleService.instance.getCurrentWeekNumber();
    final week = calendarWeek > 0
        ? calendarWeek
        : ((progress?['current_week'] as int?) ?? 1);

    final planExists = repo.hasPlan();
    if (!planExists) {
      // No plan generated yet — try to auto-generate from local profile.
      final profile = UserRepository.instance.getProfile();
      if (profile != null && profile['primary_goal'] != null) {
        // Profile exists locally — generate plan silently (async).
        // After generation completes, ref.invalidateSelf() triggers rebuild.
        _autoGeneratePlan(profile, progress);
        return CurrentPlanData(
          phase: phase,
          phaseName: 'Generating',
          currentWeek: week,
          focus: 'Generating your personalised workout plan...',
          weeks: const [],
          hasPlan: false,
          isGenerating: true,
        );
      }
      return CurrentPlanData(
        phase: phase,
        phaseName: 'No Plan',
        currentWeek: week,
        focus: 'Complete onboarding to generate your personalised plan.',
        weeks: const [],
        hasPlan: false,
      );
    }

    // Check if schedule entries are intact (plan metadata exists but
    // schedule_* entries were lost — e.g., partial Hive/IndexedDB clear).
    final week1Days = repo.getWeek(1);
    final hasWorkoutDays = week1Days.any((d) => d['type'] == 'workout');
    if (!hasWorkoutDays) {
      // Plan metadata exists but schedule is empty — regenerate.
      final profile = UserRepository.instance.getProfile();
      if (profile != null) {
        _autoGeneratePlan(profile, progress);
        // Return generating state while async regeneration runs.
        return CurrentPlanData(
          phase: phase,
          phaseName: 'Regenerating',
          currentWeek: week,
          focus: 'Rebuilding your workout schedule...',
          weeks: const [],
          hasPlan: false,
          isGenerating: true,
        );
      }
    }

    // Read plan metadata for phase name/focus.
    final planMap = repo.getCurrentPlanMap();
    final phaseName = planMap?['name'] as String? ?? 'Foundation';
    final focus =
        planMap?['focus'] as String? ?? 'Movement patterns & baseline strength';

    // Determine the actual number of weeks in the plan.
    // Phase 1 (Foundation) is always exactly 4 weeks.
    // PRO phases (2-12) may have more weeks — scan Hive for the max.
    final int totalWeeks;
    if (phase <= 1) {
      totalWeeks = 4;
    } else {
      int scanned = 4;
      for (int w = 5; w <= 12; w++) {
        if (repo.getWeek(w).isEmpty) break;
        scanned = w;
      }
      totalWeeks = scanned;
    }

    // Build weeks from Hive schedule data.
    final weeks = <List<WorkoutDayData>>[];
    for (int w = 1; w <= totalWeeks; w++) {
      final weekDays = repo.getWeek(w);
      final dayDataList = <WorkoutDayData>[];

      for (final dayMap in weekDays) {
        final type = dayMap['type'] as String? ?? 'rest';
        final isRest = type != 'workout' && type != 'custom_template';
        final status = dayMap['status'] as String? ?? 'planned';
        final exercises = _parseExerciseMaps(dayMap['exercises'] as List?);
        final warmup = _parseExerciseMaps(dayMap['warmup'] as List?);
        final cooldown = _parseExerciseMaps(dayMap['cooldown'] as List?);

        // Parse date for label and actual DateTime.
        final dateStr = dayMap['date'] as String?;
        String? dateLabel;
        DateTime? parsedDate;
        if (dateStr != null) {
          parsedDate = DateTime.tryParse(dateStr);
          if (parsedDate != null) {
            const dayNames = [
              'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
            ];
            const monthNames = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
            ];
            dateLabel =
                '${dayNames[parsedDate.weekday - 1]}, ${monthNames[parsedDate.month - 1]} ${parsedDate.day}';
          }
        }

        dayDataList.add(WorkoutDayData(
          dayNumber:
              (w - 1) * 7 + (dayMap['day_of_week'] as int? ?? 0) + 1,
          name: (dayMap['workout_name'] as String? ?? 'Rest Day')
              .toUpperCase(),
          subtitle: isRest
              ? 'Recovery & mobility'
              : '${dayMap['workout_focus'] ?? ''} \u00b7 ${exercises.length} exercises',
          dateLabel: dateLabel,
          date: parsedDate,
          isRest: isRest,
          isDone: status == 'completed',
          exercises: exercises,
          warmup: warmup,
          cooldown: cooldown,
        ));
      }

      // If no schedule data for this week, add placeholder days.
      if (dayDataList.isEmpty) {
        for (int d = 0; d < 7; d++) {
          dayDataList.add(WorkoutDayData(
            dayNumber: (w - 1) * 7 + d + 1,
            name: 'NO PLAN',
            subtitle: 'Generate a plan first',
            isRest: true,
          ));
        }
      }

      weeks.add(dayDataList);
    }

    return CurrentPlanData(
      phase: phase,
      phaseName: phaseName,
      currentWeek: week,
      focus: focus,
      weeks: weeks,
      hasPlan: true,
    );
  }

  /// Refresh plan data (e.g. after onboarding or workout completion).
  void refresh() {
    ref.invalidateSelf();
  }

  /// Copy one week's scheduled workouts to another week in Hive workoutBox.
  ///
  /// Duplicates workout entries from [sourceWeek] to [targetWeek],
  /// preserving exercise data but resetting status to 'planned'.
  Future<void> copyWeek(int sourceWeek, int targetWeek) async {
    if (sourceWeek == targetWeek) return;
    if (sourceWeek < 1 || sourceWeek > 4) return;
    if (targetWeek < 1 || targetWeek > 4) return;

    final hive = HiveService.instance;
    final startStr = hive.configBox.get('plan_start_date') as String?;
    if (startStr == null) return;

    final planStart = DateTime.tryParse(startStr) ?? DateTime.now();
    final sourceWeekStart =
        planStart.add(Duration(days: (sourceWeek - 1) * 7));
    final targetWeekStart =
        planStart.add(Duration(days: (targetWeek - 1) * 7));

    for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
      final sourceDate = sourceWeekStart.add(Duration(days: dayOfWeek));
      final targetDate = targetWeekStart.add(Duration(days: dayOfWeek));

      final sourceDateKey =
          '${sourceDate.year}-${sourceDate.month.toString().padLeft(2, '0')}-${sourceDate.day.toString().padLeft(2, '0')}';
      final targetDateKey =
          '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

      final sourceEntry = hive.workoutBox.get('schedule_$sourceDateKey');
      if (sourceEntry == null) continue;

      final sourceMap = Map<String, dynamic>.from(sourceEntry as Map);

      // Duplicate with updated date, week, and reset status
      final newEntry = Map<String, dynamic>.from(sourceMap);
      newEntry['date'] = targetDateKey;
      newEntry['week'] = targetWeek;
      newEntry['status'] =
          sourceMap['type'] == 'rest' ? 'rest' : 'planned';
      newEntry['completed_at'] = null;
      newEntry['is_swapped'] = false;
      newEntry['original_date'] = null;

      await hive.workoutBox.put('schedule_$targetDateKey', newEntry);
    }

    // Refresh the plan so the UI reflects the copied week
    ref.invalidateSelf();
  }
}

final currentPlanProvider =
    NotifierProvider<CurrentPlanNotifier, CurrentPlanData>(
        CurrentPlanNotifier.new);

// ── Selected Week ────────────────────────────────────────────────

class SelectedWeekNotifier extends Notifier<int> {
  @override
  int build() {
    // Default to the calendar week that contains today so the chip for
    // the current date range is highlighted when the Train tab opens.
    // Falls back to the stored progress week if no plan is scheduled yet.
    final calendarWeek = WorkoutScheduleService.instance.getCurrentWeekNumber();
    if (calendarWeek > 0) return calendarWeek;
    final progress = UserRepository.instance.getProgress();
    return (progress?['current_week'] as int?) ?? 1;
  }

  void select(int week) {
    state = week;
  }
}

final selectedWeekProvider =
    NotifierProvider<SelectedWeekNotifier, int>(SelectedWeekNotifier.new);

// ── Workout Stats (PRs) ────────────────────────────────────────

/// Provider for key lift PRs — watched by StatsGrid so it refreshes
/// automatically after workout completion via ref.invalidate().
final workoutStatsProvider =
    Provider<Map<String, Map<String, double>>>((ref) {
  return WorkoutRepository.instance.loadKeyLiftPRs();
});

// ── Expanded Day ────────────────────────────────────────────────

class ExpandedDayNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void toggle(int dayIndex) {
    state = state == dayIndex ? null : dayIndex;
  }

  void collapse() {
    state = null;
  }
}

final expandedDayProvider =
    NotifierProvider<ExpandedDayNotifier, int?>(ExpandedDayNotifier.new);

// ── Active Workout State ─────────────────────────────────────────

/// Input values captured for a single set.
class SetInputValues {
  final double? weight;
  final int? reps;
  final int? durationSeconds;
  final double? distanceKm;

  const SetInputValues({this.weight, this.reps, this.durationSeconds, this.distanceKm});
}

class ActiveWorkoutData {
  final WorkoutDayData? workoutDay;
  final List<ExerciseData> exercises;
  final int elapsedSeconds;
  final Map<String, bool> checkedSets; // "exerciseIndex-setIndex" -> true
  final Map<String, SetInputValues> setInputValues; // "exerciseIndex-setIndex" -> values
  final Map<String, bool> warmUpSets; // "exerciseIndex-setIndex" -> true if warm-up
  final bool isComplete;
  final bool isSaved; // true once completeWorkout() has written to Hive
  final List<String> detectedPRs; // PR descriptions detected on save
  // Superset manual grouping (session-only override, not persisted)
  final int? supersetGroupingSourceIndex; // exercise index being grouped
  final bool isSupersetGroupMode; // true when user is picking a partner

  const ActiveWorkoutData({
    this.workoutDay,
    this.exercises = const [],
    this.elapsedSeconds = 0,
    this.checkedSets = const {},
    this.setInputValues = const {},
    this.warmUpSets = const {},
    this.isComplete = false,
    this.isSaved = false,
    this.detectedPRs = const [],
    this.supersetGroupingSourceIndex,
    this.isSupersetGroupMode = false,
  });

  ActiveWorkoutData copyWith({
    WorkoutDayData? workoutDay,
    List<ExerciseData>? exercises,
    int? elapsedSeconds,
    Map<String, bool>? checkedSets,
    Map<String, SetInputValues>? setInputValues,
    Map<String, bool>? warmUpSets,
    bool? isComplete,
    bool? isSaved,
    List<String>? detectedPRs,
    int? Function()? supersetGroupingSourceIndex,
    bool? isSupersetGroupMode,
  }) {
    return ActiveWorkoutData(
      workoutDay: workoutDay ?? this.workoutDay,
      exercises: exercises ?? this.exercises,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      checkedSets: checkedSets ?? this.checkedSets,
      setInputValues: setInputValues ?? this.setInputValues,
      warmUpSets: warmUpSets ?? this.warmUpSets,
      isComplete: isComplete ?? this.isComplete,
      isSaved: isSaved ?? this.isSaved,
      detectedPRs: detectedPRs ?? this.detectedPRs,
      supersetGroupingSourceIndex: supersetGroupingSourceIndex != null
          ? supersetGroupingSourceIndex()
          : this.supersetGroupingSourceIndex,
      isSupersetGroupMode: isSupersetGroupMode ?? this.isSupersetGroupMode,
    );
  }

  int get totalSets =>
      exercises.fold<int>(0, (sum, e) => sum + (int.tryParse(e.sets) ?? 3));

  int get completedSets => checkedSets.keys
      .where((key) => !warmUpSets.containsKey(key))
      .length;

  double get progressPercent =>
      totalSets > 0 ? completedSets / totalSets : 0.0;

  String get timerFormatted {
    final mins = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  bool isSetChecked(int exerciseIndex, int setIndex) {
    return checkedSets.containsKey('$exerciseIndex-$setIndex');
  }

  bool isSetWarmUp(int exerciseIndex, int setIndex) {
    return warmUpSets.containsKey('$exerciseIndex-$setIndex');
  }

  bool isExerciseDone(int exerciseIndex) {
    final exercise = exercises[exerciseIndex];
    final numSets = int.tryParse(exercise.sets) ?? 3;
    for (int i = 0; i < numSets; i++) {
      if (!isSetChecked(exerciseIndex, i)) return false;
    }
    return true;
  }

  /// Get all exercise indices in the same superset group as [exerciseIndex].
  List<int> getSupersetPartners(int exerciseIndex) {
    final group = exercises[exerciseIndex].supersetGroup;
    if (group == null) return [];
    final partners = <int>[];
    for (int i = 0; i < exercises.length; i++) {
      if (i != exerciseIndex && exercises[i].supersetGroup == group) {
        partners.add(i);
      }
    }
    return partners;
  }

  /// Live total volume (kg) from completed working sets (excludes warm-ups).
  double get liveVolumeKg {
    double vol = 0;
    for (final entry in checkedSets.entries) {
      if (warmUpSets.containsKey(entry.key)) continue;
      final vals = setInputValues[entry.key];
      if (vals == null) continue;
      vol += (vals.weight ?? 0) * (vals.reps ?? 0);
    }
    return vol;
  }

  /// Color for a superset group index.
  static Color supersetColor(int groupIndex) {
    const colors = [
      Color(0xFF00D4FF), // accent
      Color(0xFFa855f7), // purple
      Color(0xFFf97316), // orange
      Color(0xFF4ade80), // green
      Color(0xFF38bdf8), // blue
    ];
    return colors[groupIndex % colors.length];
  }
}

class ActiveWorkoutNotifier extends Notifier<ActiveWorkoutData> {
  Timer? _timer;
  DateTime? _workoutStartTime;

  @override
  ActiveWorkoutData build() {
    ref.onDispose(() => _timer?.cancel());
    return const ActiveWorkoutData();
  }

  void startWorkout(WorkoutDayData day) {
    _timer?.cancel();

    _workoutStartTime = DateTime.now();

    state = ActiveWorkoutData(
      workoutDay: day,
      exercises: List.from(day.exercises),
      elapsedSeconds: 0,
      checkedSets: {},
      warmUpSets: const {},
    );

    // Use wall-clock elapsed time so the timer survives phone lock / app pause.
    // The Timer only triggers rebuilds; actual duration = now − startTime.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_workoutStartTime != null) {
        final elapsed = DateTime.now().difference(_workoutStartTime!).inSeconds;
        state = state.copyWith(elapsedSeconds: elapsed);
      }
    });
  }

  /// Allow manual override of elapsed seconds (e.g. user edits duration on finish).
  void setElapsedSeconds(int seconds) {
    state = state.copyWith(elapsedSeconds: seconds);
  }

  /// Reopen a completed workout for review without re-saving.
  /// Sets isComplete = false so the workout screen shows again.
  /// isSaved remains true to prevent double-logging.
  void reopenWorkout() {
    _timer?.cancel();
    _timer = null;
    _workoutStartTime = null;
    state = state.copyWith(isComplete: false);
  }

  void toggleSet(int exerciseIndex, int setIndex) {
    final key = '$exerciseIndex-$setIndex';
    final newChecked = Map<String, bool>.from(state.checkedSets);
    if (newChecked.containsKey(key)) {
      newChecked.remove(key);
    } else {
      newChecked[key] = true;
    }
    state = state.copyWith(checkedSets: newChecked);
  }

  /// Record input values for a specific set (called from UI controllers).
  void recordSetValues(int exerciseIndex, int setIndex, SetInputValues values) {
    final key = '$exerciseIndex-$setIndex';
    final newValues = Map<String, SetInputValues>.from(state.setInputValues);
    newValues[key] = values;
    state = state.copyWith(setInputValues: newValues);
  }

  void swapExercise(int exerciseIndex, ExerciseData newExercise) {
    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[exerciseIndex] = newExercise;
    state = state.copyWith(exercises: newExercises);
  }

  void addExercise(ExerciseData exercise) {
    state = state.copyWith(
      exercises: [...state.exercises, exercise],
    );
  }

  void removeExercise(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;
    if (state.exercises.length <= 1) return; // Don't allow removing last exercise
    final newExercises = List<ExerciseData>.from(state.exercises)
      ..removeAt(exerciseIndex);
    // Clean up checked sets and warm-up flags for removed and shifted exercises
    final newChecked = <String, bool>{};
    final newWarmUps = <String, bool>{};
    final newInputValues = <String, SetInputValues>{};
    for (final entry in state.checkedSets.entries) {
      final parts = entry.key.split('-');
      final exIdx = int.tryParse(parts[0]) ?? -1;
      final setIdx = parts.length > 1 ? parts[1] : '';
      if (exIdx < exerciseIndex) {
        newChecked[entry.key] = entry.value;
      } else if (exIdx > exerciseIndex) {
        newChecked['${exIdx - 1}-$setIdx'] = entry.value;
      }
    }
    for (final entry in state.warmUpSets.entries) {
      final parts = entry.key.split('-');
      final exIdx = int.tryParse(parts[0]) ?? -1;
      final setIdx = parts.length > 1 ? parts[1] : '';
      if (exIdx < exerciseIndex) {
        newWarmUps[entry.key] = entry.value;
      } else if (exIdx > exerciseIndex) {
        newWarmUps['${exIdx - 1}-$setIdx'] = entry.value;
      }
    }
    for (final entry in state.setInputValues.entries) {
      final parts = entry.key.split('-');
      final exIdx = int.tryParse(parts[0]) ?? -1;
      final setIdx = parts.length > 1 ? parts[1] : '';
      if (exIdx < exerciseIndex) {
        newInputValues[entry.key] = entry.value;
      } else if (exIdx > exerciseIndex) {
        newInputValues['${exIdx - 1}-$setIdx'] = entry.value;
      }
    }
    state = state.copyWith(
      exercises: newExercises,
      checkedSets: newChecked,
      warmUpSets: newWarmUps,
      setInputValues: newInputValues,
    );
  }

  /// Add one set to the exercise at [exerciseIndex].
  void addSet(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;
    final ex = state.exercises[exerciseIndex];
    final current = int.tryParse(ex.sets) ?? 3;
    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[exerciseIndex] = ex.copyWith(sets: '${current + 1}');
    state = state.copyWith(exercises: newExercises);
  }

  /// Remove the last set from the exercise at [exerciseIndex] (min 1 set).
  void removeLastSet(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;
    final ex = state.exercises[exerciseIndex];
    final current = int.tryParse(ex.sets) ?? 3;
    if (current <= 1) return; // Keep at least 1 set
    final newSetCount = current - 1;
    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[exerciseIndex] = ex.copyWith(sets: '$newSetCount');

    // Remove checked/warm-up/input data for the deleted last set
    final lastSetKey = '$exerciseIndex-$current'; // 0-based: set index = current-1
    final removedKey = '$exerciseIndex-${current - 1}';
    final newChecked = Map<String, bool>.from(state.checkedSets)
      ..remove(removedKey)
      ..remove(lastSetKey);
    final newWarmUps = Map<String, bool>.from(state.warmUpSets)
      ..remove(removedKey)
      ..remove(lastSetKey);
    final newInputValues = Map<String, SetInputValues>.from(state.setInputValues)
      ..remove(removedKey)
      ..remove(lastSetKey);

    state = state.copyWith(
      exercises: newExercises,
      checkedSets: newChecked,
      warmUpSets: newWarmUps,
      setInputValues: newInputValues,
    );
  }

  /// Toggle warm-up flag for a specific set.
  void toggleWarmUp(int exerciseIndex, int setIndex) {
    final key = '$exerciseIndex-$setIndex';
    final newWarmUps = Map<String, bool>.from(state.warmUpSets);
    if (newWarmUps.containsKey(key)) {
      newWarmUps.remove(key);
    } else {
      newWarmUps[key] = true;
    }
    state = state.copyWith(warmUpSets: newWarmUps);
  }

  /// Enter superset group mode: user long-pressed on exercise [exerciseIndex].
  void startSupersetGrouping(int exerciseIndex) {
    state = state.copyWith(
      isSupersetGroupMode: true,
      supersetGroupingSourceIndex: () => exerciseIndex,
    );
  }

  /// Cancel superset group mode.
  void cancelSupersetGrouping() {
    state = state.copyWith(
      isSupersetGroupMode: false,
      supersetGroupingSourceIndex: () => null,
    );
  }

  /// Pair [targetIndex] with the source exercise in a superset.
  /// Persists the superset_group changes to Hive workoutBox schedule entry.
  void pairSuperset(int targetIndex) {
    final sourceIndex = state.supersetGroupingSourceIndex;
    if (sourceIndex == null || sourceIndex == targetIndex) {
      cancelSupersetGrouping();
      return;
    }

    // Find the next available group index
    int maxGroup = -1;
    for (final ex in state.exercises) {
      if (ex.supersetGroup != null && ex.supersetGroup! > maxGroup) {
        maxGroup = ex.supersetGroup!;
      }
    }

    // If source already has a group, add target to same group (triset)
    final sourceGroup = state.exercises[sourceIndex].supersetGroup;
    final newGroupIndex = sourceGroup ?? (maxGroup + 1);

    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[sourceIndex] = newExercises[sourceIndex].copyWith(
      supersetGroup: () => newGroupIndex,
    );
    newExercises[targetIndex] = newExercises[targetIndex].copyWith(
      supersetGroup: () => newGroupIndex,
    );

    state = state.copyWith(
      exercises: newExercises,
      isSupersetGroupMode: false,
      supersetGroupingSourceIndex: () => null,
    );

    // Persist superset_group changes to Hive schedule entry
    _persistSupersetGroups(newExercises);
  }

  /// Write superset_group values back to the Hive schedule entry for the
  /// current workout day so they survive app restarts.
  void _persistSupersetGroups(List<ExerciseData> exercises) {
    final workoutDate = state.workoutDay?.date;
    if (workoutDate == null) return;

    final hive = HiveService.instance;
    final dateKey =
        '${workoutDate.year}-${workoutDate.month.toString().padLeft(2, '0')}-${workoutDate.day.toString().padLeft(2, '0')}';
    final scheduleKey = 'schedule_$dateKey';
    final entry = hive.workoutBox.get(scheduleKey);
    if (entry == null || entry is! Map) return;

    final entryMap = Map<String, dynamic>.from(entry);
    final storedExercises = entryMap['exercises'] as List?;
    if (storedExercises == null) return;

    // Update superset_group for each exercise in the stored schedule
    for (int i = 0; i < storedExercises.length && i < exercises.length; i++) {
      final exMap = storedExercises[i];
      if (exMap is Map) {
        final mutable = Map<String, dynamic>.from(exMap);
        mutable['superset_group'] = exercises[i].supersetGroup;
        storedExercises[i] = mutable;
      }
    }

    entryMap['exercises'] = storedExercises;
    hive.workoutBox.put(scheduleKey, entryMap);
  }

  Future<void> completeWorkout() async {
    _timer?.cancel();
    _timer = null;
    _workoutStartTime = null;

    // If already saved (user reopened workout to review), just mark complete
    // again without re-writing to Hive — prevents duplicate exercise logs.
    if (state.isSaved) {
      state = state.copyWith(isComplete: true);
      return;
    }

    final repo = WorkoutRepository.instance;
    final hive = HiveService.instance;
    final now = DateTime.now();

    // PR detection: single-scan cache of exercise → best weight + best reps
    // (O(n) once, then O(1) per exercise).
    final bestWeightMap = <String, double>{};
    final bestRepsMap = <String, int>{};
    for (final raw in hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'exercise_log') continue;
      final name = (log['exercise_name'] as String? ?? '').toLowerCase();
      if (name.isEmpty) continue;
      final w = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (w > (bestWeightMap[name] ?? 0)) bestWeightMap[name] = w;
      final r = (log['reps_completed'] as int?) ?? 0;
      if (r > (bestRepsMap[name] ?? 0)) bestRepsMap[name] = r;
    }

    final prDescriptions = <String>[];
    for (int exIdx = 0; exIdx < state.exercises.length; exIdx++) {
      final exercise = state.exercises[exIdx];

      // Scan checkedSets keys for this exercise to handle dynamically added sets.
      int maxSet = int.tryParse(exercise.sets) ?? 3;
      for (final key in state.checkedSets.keys) {
        if (key.startsWith('$exIdx-')) {
          final s = int.tryParse(key.split('-').last) ?? 0;
          if (s + 1 > maxSet) maxSet = s + 1;
        }
      }

      // Weight PR (weight_reps, weighted_bodyweight)
      if (exercise.loggingType == 'weight_reps' ||
          exercise.loggingType == 'weighted_bodyweight') {
        double currentWeight = 0;
        for (int s = 0; s < maxSet; s++) {
          final key = '$exIdx-$s';
          if (state.checkedSets.containsKey(key) && !state.warmUpSets.containsKey(key)) {
            final vals = state.setInputValues[key];
            if (vals?.weight != null && vals!.weight! > currentWeight) {
              currentWeight = vals.weight!;
            }
          }
        }
        if (currentWeight <= 0) continue;

        final bestPrevious = bestWeightMap[exercise.name.toLowerCase()] ?? 0;
        if (currentWeight > bestPrevious && bestPrevious > 0) {
          prDescriptions.add(
              '${exercise.name}: ${currentWeight.toStringAsFixed(1)}kg (was ${bestPrevious.toStringAsFixed(1)}kg)');
        }
      }

      // Rep PR (bodyweight_reps — e.g. push-ups, pull-ups, dips)
      if (exercise.loggingType == 'bodyweight_reps') {
        int currentReps = 0;
        for (int s = 0; s < maxSet; s++) {
          final key = '$exIdx-$s';
          if (state.checkedSets.containsKey(key) && !state.warmUpSets.containsKey(key)) {
            final vals = state.setInputValues[key];
            if (vals?.reps != null && vals!.reps! > currentReps) {
              currentReps = vals.reps!;
            }
          }
        }
        if (currentReps <= 0) continue;

        final bestPrevious = bestRepsMap[exercise.name.toLowerCase()] ?? 0;
        if (currentReps > bestPrevious && bestPrevious > 0) {
          prDescriptions.add(
              '${exercise.name}: $currentReps reps (was $bestPrevious reps)');
        }
      }
    }

    final workoutDate = state.workoutDay?.date ?? now;

    // Save workout log via repository.
    await repo.saveWorkoutLog(
      workoutName: state.workoutDay?.name ?? 'Workout',
      setsCompleted: state.completedSets,
      durationSeconds: state.elapsedSeconds,
      completedAt: workoutDate,
    );

    // Compute date key once — used by exercise logs, date index, schedule, and streak.
    final dateStr = formatDateKey(workoutDate);
    final savedLogIds = <String>[]; // Collect IDs for date index

    // Save individual exercise logs with is_pr flag, respecting logging type
    for (int exIdx = 0; exIdx < state.exercises.length; exIdx++) {
      final exercise = state.exercises[exIdx];
      final isPr = prDescriptions
          .any((pr) => pr.startsWith(exercise.name));
      final logId =
          'exlog_${now.millisecondsSinceEpoch}_${exercise.name.hashCode}';

      // Aggregate values from per-set input data.
      // Scan checkedSets for dynamically added sets beyond template count.
      int maxSetLog = int.tryParse(exercise.sets) ?? 3;
      for (final key in state.checkedSets.keys) {
        if (key.startsWith('$exIdx-')) {
          final s = int.tryParse(key.split('-').last) ?? 0;
          if (s + 1 > maxSetLog) maxSetLog = s + 1;
        }
      }
      double totalWeight = 0;
      int totalReps = 0;
      int totalDuration = 0;
      double totalDistance = 0;
      double volumeKg = 0; // exact per-set volume for receipt reconstruction
      int completedSets = 0;

      for (int s = 0; s < maxSetLog; s++) {
        final key = '$exIdx-$s';
        if (state.checkedSets.containsKey(key)) {
          // Skip warm-up sets in volume calculations
          final isWarmUp = state.warmUpSets.containsKey(key);
          if (isWarmUp) continue;

          completedSets++;
          final vals = state.setInputValues[key];
          if (vals != null) {
            if (vals.weight != null && vals.weight! > totalWeight) {
              totalWeight = vals.weight!; // best weight across sets
            }
            totalReps += vals.reps ?? 0;
            totalDuration += vals.durationSeconds ?? 0;
            totalDistance += vals.distanceKm ?? 0;
            // Accumulate exact per-set volume
            volumeKg += (vals.weight ?? 0) * (vals.reps ?? 0);
          }
        }
      }

      // Fallback to exercise defaults if no input captured
      if (totalWeight == 0) {
        totalWeight = double.tryParse(
                exercise.weight.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0;
      }
      if (totalReps == 0) {
        totalReps = (int.tryParse(exercise.reps) ?? 10) * completedSets;
      }

      // Check if any sets for this exercise were warm-up
      final hasWarmUpSets = List.generate(maxSetLog, (s) => '$exIdx-$s')
          .any((key) => state.warmUpSets.containsKey(key));

      // Validate loggingType — treat unknown types as 'weight_reps'
      const validLoggingTypes = {
        'weight_reps',
        'bodyweight_reps',
        'weighted_bodyweight',
        'timed',
        'cardio',
        'distance',
      };
      final effectiveLoggingType = validLoggingTypes.contains(exercise.loggingType)
          ? exercise.loggingType
          : 'weight_reps';

      // Build log map based on logging type
      final logMap = <String, dynamic>{
        'id': logId,
        'type': 'exercise_log',
        'exercise_name': exercise.name,
        'date': dateStr,
        'logging_type': effectiveLoggingType,
        'is_pr': isPr,
        'has_warmup_sets': hasWarmUpSets,
        'volume_kg': volumeKg,
        'created_at': now.toIso8601String(),
      };

      switch (effectiveLoggingType) {
        case 'weight_reps':
          logMap['weight_kg'] = totalWeight;
          logMap['reps_completed'] = totalReps;
          logMap['sets_completed'] = completedSets;
          break;
        case 'bodyweight_reps':
          logMap['reps_completed'] = totalReps;
          logMap['sets_completed'] = completedSets;
          break;
        case 'weighted_bodyweight':
          logMap['weight_kg'] = totalWeight;
          logMap['reps_completed'] = totalReps;
          logMap['sets_completed'] = completedSets;
          break;
        case 'timed':
          logMap['duration_seconds'] = totalDuration;
          logMap['sets_completed'] = completedSets;
          break;
        case 'cardio':
          logMap['duration_seconds'] = totalDuration;
          logMap['distance_km'] = totalDistance;
          break;
        case 'distance':
          logMap['distance_km'] = totalDistance;
          logMap['weight_kg'] = totalWeight;
          break;
        default:
          logMap['weight_kg'] = totalWeight;
          logMap['reps_completed'] = totalReps;
          logMap['sets_completed'] = completedSets;
      }

      await hive.workoutBox.put(logId, logMap);
      savedLogIds.add(logId);
    }

    // Update date index for O(1) lookups by date (Fix 4: date index).
    // Appends new log IDs to existing index (handles multiple workouts/day).
    if (savedLogIds.isNotEmpty) {
      final indexKey = 'exercise_log_index_$dateStr';
      final existingIndex = hive.workoutBox.get(indexKey);
      final indexList = existingIndex is List
          ? List<String>.from(existingIndex)
          : <String>[];
      indexList.addAll(savedLogIds);
      await hive.workoutBox.put(indexKey, indexList);
    }

    // Mark the scheduled day as completed in the calendar.
    await repo.markWorkoutCompleted(workoutDate, durationSeconds: state.elapsedSeconds);

    // Update user progress + streak.
    final progress = UserRepository.instance.getProgress() ?? {};
    final totalDone = ((progress['total_workouts_done'] as int?) ?? 0) + 1;

    // ── Daily streak (schedule-aware — skips rest days) ──
    // Calculated on-the-fly by scanning schedule backwards.
    // Handles rest days, schedule changes, and template swaps correctly.
    final streakDays = repo.calculateCurrentStreak();

    // ── Weekly streak (kept for badge logic — not shown in UI) ───
    final currentWeekNum = WorkoutScheduleService.instance.getCurrentWeekNumber();
    final weekDays = repo.getWeek(currentWeekNum);
    final planned = weekDays.where((d) => d['type'] == 'workout').length;
    final completedCount = weekDays.where((d) => d['status'] == 'completed').length;
    int streakWeeks = (progress['current_streak_weeks'] as int?) ?? 0;
    final lastStreakWeek = (progress['last_streak_week'] as int?) ?? -1;
    if (planned > 0 &&
        completedCount >= (planned * 0.8).ceil() &&
        currentWeekNum != lastStreakWeek) {
      streakWeeks += 1;
    }

    await UserRepository.instance.updateProgress({
      'total_workouts_done': totalDone,
      'current_streak_days': streakDays,
      'last_workout_date': dateStr,
      'current_streak_weeks': streakWeeks,
      'last_streak_week': currentWeekNum,
    });

    // ── Create/update per-week streak row for Supabase streaks table ──
    final planStart = WorkoutScheduleService.instance.getPlanStartDate();
    if (planStart != null && planned > 0) {
      final weekStart = planStart.add(Duration(days: (currentWeekNum - 1) * 7));
      final weekStartStr = formatDateKey(weekStart);
      final streakId = 'streak_$weekStartStr';

      final healthBox = HiveService.instance.healthBox;
      final existing = (healthBox.get('streaks') as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
      final idx = existing.indexWhere((s) => s['local_id'] == streakId);

      final row = <String, dynamic>{
        'local_id': streakId,
        'week_start': weekStartStr,
        'workouts_planned': planned,
        'workouts_completed': completedCount,
        'is_streak_maintained': completedCount >= (planned * 0.8).ceil(),
      };

      if (idx >= 0) {
        existing[idx] = row;
      } else {
        existing.add(row);
      }
      await healthBox.put('streaks', existing);
    }

    state = state.copyWith(isComplete: true, isSaved: true, detectedPRs: prDescriptions);

    // Check badge unlocks after workout completion.
    BadgeService.instance.checkAll();

    // Fire-and-forget cloud sync of workout data + progress (non-blocking).
    SyncService.instance.syncWorkoutData();
    SyncService.instance.syncProgressNow();

    // Refresh all affected providers. Riverpod batches invalidations within
    // the same synchronous frame — these won't cause separate rebuilds.
    // Each is independent (no transitive dependencies between them).
    ref.invalidate(currentPlanProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(allExercisePRsProvider);
    // Note: weightHistoryProvider not invalidated — workout completion
    // doesn't change weight data (weight is logged separately).
  }

  void cancelWorkout() {
    _timer?.cancel();
    _timer = null;
    state = const ActiveWorkoutData();
  }
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutData>(
        ActiveWorkoutNotifier.new);

// ── Rest Timer State ─────────────────────────────────────────────

class RestTimerData {
  final bool isActive;
  final int secondsRemaining;
  final int totalSeconds;
  final String nextExerciseName;

  const RestTimerData({
    this.isActive = false,
    this.secondsRemaining = 0,
    this.totalSeconds = 90,
    this.nextExerciseName = '',
  });

  RestTimerData copyWith({
    bool? isActive,
    int? secondsRemaining,
    int? totalSeconds,
    String? nextExerciseName,
  }) {
    return RestTimerData(
      isActive: isActive ?? this.isActive,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      nextExerciseName: nextExerciseName ?? this.nextExerciseName,
    );
  }

  double get progress =>
      totalSeconds > 0 ? secondsRemaining / totalSeconds : 0.0;

  Color get timerColor {
    if (secondsRemaining > 30) return const Color(0xFF00D4FF);
    if (secondsRemaining > 10) return const Color(0xFFF59E0B);
    return const Color(0xFFef4444);
  }
}

class RestTimerNotifier extends Notifier<RestTimerData> {
  Timer? _timer;

  @override
  RestTimerData build() {
    ref.onDispose(() => _timer?.cancel());
    return const RestTimerData();
  }

  void start(int seconds, String nextExercise) {
    _timer?.cancel();
    state = RestTimerData(
      isActive: true,
      secondsRemaining: seconds,
      totalSeconds: seconds,
      nextExerciseName: nextExercise,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.secondsRemaining <= 1) {
        skip();
      } else {
        state =
            state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  void skip() {
    _timer?.cancel();
    _timer = null;
    state = const RestTimerData();
  }

  void addTime(int seconds) {
    state = state.copyWith(
      secondsRemaining: state.secondsRemaining + seconds,
      totalSeconds: state.totalSeconds + seconds,
    );
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerNotifier, RestTimerData>(RestTimerNotifier.new);

// ── Templates ────────────────────────────────────────────────────

class TemplatesNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    final box = HiveService.instance.workoutBox;
    final templates = <Map<String, dynamic>>[];

    for (final raw in box.values) {
      if (raw is! Map) continue;
      final w = Map<String, dynamic>.from(raw);
      if (w['type'] == 'template') {
        templates.add(w);
      }
    }

    return templates;
  }

  Future<void> saveTemplate(Map<String, dynamic> template) async {
    final hive = HiveService.instance;
    final id =
        template['id'] ?? 'tmpl_${DateTime.now().millisecondsSinceEpoch}';
    template['id'] = id;
    template['type'] = 'template';
    template['created_at'] = DateTime.now().toIso8601String();
    await hive.workoutBox.put(id, template);
    ref.invalidateSelf();
  }

  Future<void> updateTemplate(
      String templateId, Map<String, dynamic> template) async {
    final hive = HiveService.instance;
    final existing = hive.workoutBox.get(templateId);
    if (existing == null) return;
    final updated = Map<String, dynamic>.from(existing as Map);
    updated['name'] = template['name'];
    updated['exercises'] = template['exercises'];
    updated['exercise_count'] = template['exercise_count'];
    if (template.containsKey('assigned_days')) {
      updated['assigned_days'] = template['assigned_days'];
    }
    updated['updated_at'] = DateTime.now().toIso8601String();
    await hive.workoutBox.put(templateId, updated);
    ref.invalidateSelf();
  }

  /// Delete a saved template AND clean up its future schedule entries.
  ///
  /// Uses the same backup-restore pattern as the edit flow — any
  /// future `schedule_<date>` entry owned by this template has its
  /// displaced original restored before the template row itself is
  /// deleted. Completed workouts are never touched, so history
  /// survives intact even if the template is gone.
  ///
  /// Invalidates every consumer and fires pushSnapshot so the AI
  /// coach stops referencing the deleted template immediately.
  Future<void> deleteTemplate(String templateId) async {
    final hive = HiveService.instance;

    // Step 1: clean-sync wipes future entries for this template and
    // restores displaced originals where applicable.
    await WorkoutScheduleService.instance
        .cleanSyncTemplateSchedule(templateId);

    // Step 2: delete the template row itself.
    await hive.workoutBox.delete(templateId);

    // Step 3: refresh every consumer.
    ref.invalidateSelf();
    ref.invalidate(currentPlanProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(streakProvider);

    // Step 4: fire-and-forget snapshot push (AI coach freshness).
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final templatesProvider =
    NotifierProvider<TemplatesNotifier, List<Map<String, dynamic>>>(
        TemplatesNotifier.new);

// ── Graduation Stats ────────────────────────────────────────────

/// PR record for graduation display.
class PrRecord {
  final String exerciseName;
  final String value;
  const PrRecord({required this.exerciseName, required this.value});
}

class GraduationStatsData {
  final int totalWorkouts;
  final int streakWeeks;
  final int totalSets;
  final int personalRecords;
  final List<PrRecord> topPrs;

  const GraduationStatsData({
    this.totalWorkouts = 0,
    this.streakWeeks = 0,
    this.totalSets = 0,
    this.personalRecords = 0,
    this.topPrs = const [],
  });
}

final graduationStatsProvider = Provider<GraduationStatsData>((ref) {
  final hive = HiveService.instance;
  final progress = UserRepository.instance.getProgress() ?? {};

  final totalWorkouts = (progress['total_workouts_done'] as int?) ?? 0;
  final streakWeeks = (progress['current_streak_weeks'] as int?) ?? 0;

  // Calculate total sets and PRs from workout box
  int totalSets = 0;
  int prCount = 0;
  final prMap = <String, double>{}; // exerciseName -> best weight

  for (final raw in hive.workoutBox.values) {
    if (raw is! Map) continue;
    final log = Map<String, dynamic>.from(raw);

    if (log['type'] == 'exercise_log') {
      final sets = (log['sets_completed'] as int?) ?? 0;
      totalSets += sets;

      final isPr = (log['is_pr'] as bool?) ?? false;
      if (isPr) prCount++;

      final name = log['exercise_name'] as String? ?? '';
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (name.isNotEmpty && weight > 0) {
        final best = prMap[name] ?? 0;
        if (weight > best) prMap[name] = weight;
      }
    }

    if (log['type'] == 'workout_log') {
      final s = (log['sets_completed'] as int?) ?? 0;
      if (s > 0 && totalSets == 0) totalSets += s;
    }
  }

  // Build top PRs list sorted by weight descending
  final topPrs = prMap.entries
      .map((e) => PrRecord(
            exerciseName: e.key,
            value: '${e.value.toStringAsFixed(1)}kg',
          ))
      .toList()
    ..sort((a, b) {
      final aW = double.tryParse(a.value.replaceAll('kg', '')) ?? 0;
      final bW = double.tryParse(b.value.replaceAll('kg', '')) ?? 0;
      return bW.compareTo(aW);
    });

  return GraduationStatsData(
    totalWorkouts: totalWorkouts,
    streakWeeks: streakWeeks,
    totalSets: totalSets,
    personalRecords: prCount,
    topPrs: topPrs,
  );
});
