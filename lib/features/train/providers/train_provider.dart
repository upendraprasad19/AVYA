import 'dart:async';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import '../repositories/workout_repository.dart';

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
    if (!logName.contains(nameLower) && !nameLower.contains(logName)) continue;
    if (logName.isEmpty) continue;

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
    if (!logName.contains(nameLower) && !nameLower.contains(logName)) continue;
    if (logName.isEmpty) continue;

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

  const WorkoutDayData({
    required this.dayNumber,
    required this.name,
    this.subtitle = '',
    this.dateLabel,
    this.date,
    this.isRest = false,
    this.isDone = false,
    this.exercises = const [],
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

// ── Current Plan ─────────────────────────────────────────────────

class CurrentPlanData {
  final int phase;
  final String phaseName;
  final int currentWeek;
  final String focus;
  final List<List<WorkoutDayData>> weeks;
  final bool hasPlan;

  const CurrentPlanData({
    this.phase = 1,
    this.phaseName = 'Foundation',
    this.currentWeek = 1,
    this.focus = 'Movement patterns & baseline strength',
    this.weeks = const [],
    this.hasPlan = false,
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
        final dayStr =
            '${day.date!.year}-${day.date!.month.toString().padLeft(2, '0')}-${day.date!.day.toString().padLeft(2, '0')}';
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
  /// Called synchronously when plan is missing or schedule entries are corrupt.
  /// Uses PlanGenerator.generate() (synchronous) and writes to Hive directly.
  void _autoGeneratePlan(
      Map<String, dynamic> profile, Map<String, dynamic>? progress) {
    final goal = profile['primary_goal'] as String? ?? 'general_fitness';
    final equipment = profile['equipment_access'] as String? ?? 'basic_gym';
    final daysPerWeek = (profile['days_per_week'] as int?) ?? 4;
    final experience = profile['fitness_experience'] as String? ?? 'beginner';
    final phase = (progress?['current_phase'] as int?) ?? 1;

    // Fire-and-forget: schedule generation is async (Hive writes) but
    // we don't await it here. The build() method will fall through to
    // read whatever data is available — no recursive build() call.
    WorkoutScheduleService.instance.generateAndSchedule(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      startDate: DateTime.now(),
      experienceLevel: experience,
      phase: phase,
    );
  }

  @override
  CurrentPlanData build() {
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress();
    final phase = (progress?['current_phase'] as int?) ?? 1;
    final week = (progress?['current_week'] as int?) ?? 1;

    final planExists = repo.hasPlan();
    if (!planExists) {
      // No plan generated yet — try to auto-generate from local profile.
      final profile = UserRepository.instance.getProfile();
      if (profile != null && profile['primary_goal'] != null) {
        // Profile exists locally — generate plan silently (async, fire-and-forget).
        _autoGeneratePlan(profile, progress);
        // Plan generation is async — fall through and show empty state for now.
        // The provider will be invalidated once generation completes on next access.
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
      }
    }

    // Read plan metadata for phase name/focus.
    final planMap = repo.getCurrentPlanMap();
    final phaseName = planMap?['name'] as String? ?? 'Foundation';
    final focus =
        planMap?['focus'] as String? ?? 'Movement patterns & baseline strength';

    // Determine the actual number of weeks in the plan.
    // Default to 4, but scan Hive for the maximum week present.
    int totalWeeks = 4;
    for (int w = 5; w <= 12; w++) {
      final weekDaysCheck = repo.getWeek(w);
      if (weekDaysCheck.isEmpty) break;
      totalWeeks = w;
    }

    // Build weeks from Hive schedule data.
    final weeks = <List<WorkoutDayData>>[];
    for (int w = 1; w <= totalWeeks; w++) {
      final weekDays = repo.getWeek(w);
      final dayDataList = <WorkoutDayData>[];

      for (final dayMap in weekDays) {
        final type = dayMap['type'] as String? ?? 'rest';
        final isRest = type != 'workout';
        final status = dayMap['status'] as String? ?? 'planned';
        final exerciseMaps = dayMap['exercises'] as List? ?? [];

        final exercises = exerciseMaps
            .map((e) {
              final m =
                  e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
              final equipRaw = m['equipment_needed'];
              final equipList = equipRaw is List
                  ? equipRaw.map((e) => e.toString()).toList()
                  : <String>[];
              return ExerciseData(
                name: m['exercise_name'] as String? ?? 'Unknown',
                sets: '${m['sets'] ?? 3}',
                reps: m['reps'] as String? ?? '${m['reps'] ?? 10}',
                weight: '0kg',
                rest: '${m['rest_seconds'] ?? 60}s',
                loggingType: m['logging_type'] as String? ?? 'weight_reps',
                category: m['category'] as String?,
                equipmentNeeded: equipList,
                exerciseType: m['exercise_type'] as String?,
                supersetGroup: m['superset_group'] as int?,
              );
            })
            .toList();

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

    final planStart = DateTime.parse(startStr);
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
    final progress = UserRepository.instance.getProgress();
    return (progress?['current_week'] as int?) ?? 1;
  }

  void select(int week) {
    state = week;
  }
}

final selectedWeekProvider =
    NotifierProvider<SelectedWeekNotifier, int>(SelectedWeekNotifier.new);

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
      detectedPRs: detectedPRs ?? this.detectedPRs,
      supersetGroupingSourceIndex: supersetGroupingSourceIndex != null
          ? supersetGroupingSourceIndex()
          : this.supersetGroupingSourceIndex,
      isSupersetGroupMode: isSupersetGroupMode ?? this.isSupersetGroupMode,
    );
  }

  int get totalSets =>
      exercises.fold<int>(0, (sum, e) => sum + (int.tryParse(e.sets) ?? 3));

  int get completedSets => checkedSets.length;

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

  @override
  ActiveWorkoutData build() {
    ref.onDispose(() => _timer?.cancel());
    return const ActiveWorkoutData();
  }

  void startWorkout(WorkoutDayData day) {
    _timer?.cancel();

    // Auto-mark first set of compound exercises as warm-up
    final warmUps = <String, bool>{};
    for (int i = 0; i < day.exercises.length; i++) {
      if (day.exercises[i].isCompound) {
        warmUps['$i-0'] = true; // first set is warm-up
      }
    }

    state = ActiveWorkoutData(
      workoutDay: day,
      exercises: List.from(day.exercises),
      elapsedSeconds: 0,
      checkedSets: {},
      warmUpSets: warmUps,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
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

    final repo = WorkoutRepository.instance;
    final hive = HiveService.instance;
    final now = DateTime.now();

    // PR detection: compare each exercise's weight to best previous log
    final prDescriptions = <String>[];
    for (final exercise in state.exercises) {
      if (exercise.loggingType != 'weight_reps' &&
          exercise.loggingType != 'weighted_bodyweight') {
        continue;
      }
      final currentWeight =
          double.tryParse(exercise.weight.replaceAll(RegExp(r'[^0-9.]'), '')) ??
              0;
      if (currentWeight <= 0) continue;

      // Find best previous weight for this exercise
      double bestPrevious = 0;
      for (final raw in hive.workoutBox.values) {
        if (raw is! Map) continue;
        final log = Map<String, dynamic>.from(raw);
        final name =
            (log['exercise_name'] as String? ?? '').toLowerCase();
        if (name == exercise.name.toLowerCase()) {
          final w = (log['weight_kg'] as num?)?.toDouble() ?? 0;
          if (w > bestPrevious) bestPrevious = w;
        }
      }

      if (currentWeight > bestPrevious && bestPrevious > 0) {
        prDescriptions.add(
            '${exercise.name}: ${currentWeight.toStringAsFixed(1)}kg (was ${bestPrevious.toStringAsFixed(1)}kg)');
      }
    }

    // Save workout log via repository.
    await repo.saveWorkoutLog(
      workoutName: state.workoutDay?.name ?? 'Workout',
      setsCompleted: state.completedSets,
      durationSeconds: state.elapsedSeconds,
      completedAt: now,
    );

    // Save individual exercise logs with is_pr flag, respecting logging type
    for (int exIdx = 0; exIdx < state.exercises.length; exIdx++) {
      final exercise = state.exercises[exIdx];
      final isPr = prDescriptions
          .any((pr) => pr.startsWith(exercise.name));
      final logId =
          'exlog_${now.millisecondsSinceEpoch}_${exercise.name.hashCode}';
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Aggregate values from per-set input data
      final numSets = int.tryParse(exercise.sets) ?? 3;
      double totalWeight = 0;
      int totalReps = 0;
      int totalDuration = 0;
      double totalDistance = 0;
      int completedSets = 0;

      for (int s = 0; s < numSets; s++) {
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
      final hasWarmUpSets = List.generate(numSets, (s) => '$exIdx-$s')
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
    }

    // Mark the scheduled day as completed in the calendar.
    final workoutDate = state.workoutDay?.date ?? now;
    await repo.markWorkoutCompleted(workoutDate);

    // Update user progress.
    final progress = UserRepository.instance.getProgress() ?? {};
    final totalDone = ((progress['total_workouts_done'] as int?) ?? 0) + 1;
    await UserRepository.instance.updateProgress({
      'total_workouts_done': totalDone,
    });

    state = state.copyWith(isComplete: true, detectedPRs: prDescriptions);

    // Refresh the plan provider so the UI reflects the completed workout.
    ref.invalidate(currentPlanProvider);
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
