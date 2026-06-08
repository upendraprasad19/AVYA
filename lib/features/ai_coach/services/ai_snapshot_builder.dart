// Tech-debt audit 2026-05-20 finding A10 — AiSnapshotBuilder extracted
// from AiCoachRepository.
//
// Owns the single buildAiContext() entry point and every private snapshot
// helper. All reads here are gate-protected by `docs/snapshot_contract.yaml`
// and the snapshot-contract gate (`scripts/check_snapshot_contract.dart`).
//
// Why split out: AiCoachRepository was 2127 lines mixing snapshot reads,
// chat persistence, identity-signal detection, and coaching-notes
// extraction. Test #8's "4 ai_coach_repository drift fixes" all landed
// in this file because every AI-snapshot field flows through one
// buildAiContext(). Isolating this surface keeps the writer/reader-drift
// blast radius scoped to one read-only service.
//
// Public API: AiSnapshotBuilder.instance.buildAiContext() returns the
// full user_daily_snapshot map. All other methods on this class are
// private helpers used by buildAiContext.
//
// Hive contract: every read routes through HiveService.instance (rule #4
// — Hive-first). No direct Hive.openBox calls from this file.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/features/train/services/active_workout_persistence.dart';
import '../models/coach_memory.dart';

/// Builder for the AI Coach user_daily_snapshot context map.
///
/// Single canonical writer for `docs/snapshot_contract.yaml`. The cron
/// readers (morning-alert, streak-guardian, protein-gap-alert) and the
/// trim path (`_compactContext` in `ai_service.dart`) all read the keys
/// emitted here.
class AiSnapshotBuilder {
  AiSnapshotBuilder._();
  static final AiSnapshotBuilder _instance = AiSnapshotBuilder._();
  static AiSnapshotBuilder get instance => _instance;

  final HiveService _hive = HiveService.instance;

  /// Builds the full AI context map from all Hive boxes.
  /// This is the user_daily_snapshot that gets sent with every AI message.
  Map<String, dynamic> buildAiContext() {
    final profile = UserRepository.instance.getProfile() ?? {};
    final progress = UserRepository.instance.getProgress() ?? {};
    final preferences = UserRepository.instance.getPreferences() ?? {};

    // Detect if this is the user's first-ever message to the coach
    // by checking if coachBox has any prior interactions
    final priorMessages = _hive.coachBox.values
        .where((v) => v is Map && (v['user_message'] as String?)?.isNotEmpty == true)
        .length;
    final isFirstEverMessage = priorMessages == 0;

    final snapshot = <String, dynamic>{
      'is_first_ever_message': isFirstEverMessage,
      'profile': {
        'name': profile['full_name'] ?? '',
        'age': _calculateAge(profile['date_of_birth'] as String?),
        'gender': profile['gender'] ?? '',
        'height_cm': profile['height_cm'] ?? 0,
        'current_weight_kg': profile['current_weight_kg'] ?? 0,
        'target_weight_kg': profile['target_weight_kg'] ?? 0,
        'primary_goal': profile['primary_goal'] ?? '',
        'fitness_experience': profile['fitness_experience'] ?? '',
        'equipment_access': profile['equipment_access'] ?? '',
        'activity_level': profile['activity_level'] ?? '',
        'diet_preference': profile['diet_preference'] ?? '',
        'injuries': profile['injuries'] ?? '',
        'bmr': profile['bmr'] ?? 0,
        'tdee': profile['tdee'] ?? 0,
        if (profile['city'] != null && (profile['city'] as String).isNotEmpty)
          'city': profile['city'],
      },
      'progress': {
        'current_phase': progress['current_phase'] ?? 1,
        'current_week': WorkoutScheduleService.instance.getCurrentWeekNumber(),
        'total_workouts_done': progress['total_workouts_done'] ?? 0,
        'current_streak_weeks': progress['current_streak_weeks'] ?? 0,
        'detected_experience': progress['detected_experience_level'] ??
            UserRepository.instance.detectedExperience ?? 'beginner',
      },

      // Top-level aliases for cron Edge Function readers.
      // audit-2026-05-17 OI-07-FOLLOWUP — closes-diagnose: 2026-05-17-orphan-reader-aliases-7faa3b
      'current_streak_weeks': progress['current_streak_weeks'] ?? 0,
      'current_streak_days':
          ((progress['current_streak_weeks'] as num?)?.toInt() ?? 0) * 7,
      'total_workouts_done': progress['total_workouts_done'] ?? 0,
      'current_weight_kg': profile['current_weight_kg'] ?? 0,
      'target_weight_kg': profile['target_weight_kg'] ?? 0,
      'today_workout_name': _topLevelTodayWorkoutName(),
      'recent_pr_exercise': _topLevelRecentPrField('exercise_name'),
      'recent_pr_weight': _topLevelRecentPrField('weight_kg'),
      'yesterday_calories': _topLevelYesterdayCalories(),
      'daily_calorie_target': (profile['tdee'] as num?)?.toInt() ?? 0,
      'daily_targets': {
        'protein': (profile['protein_g_target'] as num?)?.toDouble() ??
            (profile['protein_target_g'] as num?)?.toDouble() ??
            0,
      },
      'this_week_workouts': _getThisWeekWorkouts(),
      'today_nutrition': _getTodayNutrition(),
      'today_steps': _getTodaySteps(),
      'step_history_7d': _getStepHistory(days: 7),
      'latest_weight': _getLatestWeight(),
      'personal_records': _getPersonalRecords(),
      'coaching_notes': _getCoachingNotes(),
      'coach_memory': _getCoachMemoryForContext(),

      'fitness_summary': _getFitnessSummary(),
      'motivational_style': preferences['motivational_style'] ?? 'encouraging',
      'coach_notices': _getCoachNotices(),

      'custom_exercises': _readCustomExercises(),
      'saved_templates': _readSavedTemplates(),

      'meals_today': _getMealsToday(),
      'nutrition_trend_7d': _getNutritionTrend7d(),

      ..._computeDataWindowGrounding(),
      'nutrition_logs_count_7d': _countNutritionLogsLast7Days(),
      'sleep_logs_count_7d': _countSleepLogsLast7Days(),

      'today_workout': _getTodayWorkout(),
      'yesterday_workout': _getYesterdayWorkout(),
      'week_lookahead': _getWeekLookahead(),

      'current_plan_summary': _getCurrentPlanSummary(),

      'sleep_7d': _getSleep7d(),
      'water_7d': _getWater7d(),
      'streak_freezes_available': _getStreakFreezesAvailable(),
      'streak_freezes_refill_date': _getStreakFreezesRefillDate(),
      'subscription': _getSubscriptionState(),
      'current_rank': _getCurrentRankFromLadder(),
      'next_rank': _getNextRankFromLadder(),
      'eta_next_promotion': _getEtaNextPromotion(),
      'cadence': {
        'workouts_per_week_4w': _computeWorkoutsPerWeekLast4Weeks(),
        'plan_target': ((_hive.userBox.get('profile') as Map?)?['days_per_week'] as int?) ?? 4,
      },

      'active_workout': ActiveWorkoutPersistence.readState(),

      ..._getInductionAndMusterKeys(),

      'pr_timeline_summary': _getPRTimelineSummary(),
      'goal_changed_at': _getGoalChangedAt(),
      'body_measurements': _getBodyMeasurements(),
      'onboarding_completed_at': _getOnboardingCompletedAt(),
      'phase_transitions': _getPhaseTransitions(),
      'recent_meal_deletes': _getRecentMealDeletes(),
    };
    return trimSnapshotToBudget(snapshot);
  }

  /// Caps the serialized snapshot under the server's 10K-char limit
  /// (CLAUDE.md §4.4 rule 18). A power user with a long history (many PRs,
  /// custom exercises, a full year of logs) can otherwise overflow it,
  /// making `ai-proxy` reject EVERY message with "coaching context unusually
  /// large" — a totally unusable coach (found live on amar, year-sim data;
  /// diagnose a9c3e2). We iteratively shrink the LARGEST non-critical field
  /// (halve a list, halve a map, or drop a scalar blob) until the snapshot
  /// fits, always keeping the high-signal fields the coach reasons from.
  ///
  /// [budget] defaults to 8500 for the BASE snapshot, leaving headroom under
  /// the 10000-char server cap. NOTE: `enrichContextForQuery`'s historical adds
  /// are NOT guaranteed to fit that headroom (weight/adherence trends span 90
  /// days), so enrich RE-TRIMS its own output to budget 9500 before returning
  /// (diagnose a9c3e2 + Hermes L37 finding). Visible for testing.
  @visibleForTesting
  static Map<String, dynamic> trimSnapshotToBudget(
    Map<String, dynamic> s, {
    int budget = 8500,
  }) {
    // Never trimmed — the coach must always see these in full.
    const keep = <String>{
      'is_first_ever_message', 'profile', 'progress',
      'current_streak_weeks', 'current_streak_days', 'total_workouts_done',
      'current_weight_kg', 'target_weight_kg', 'daily_targets',
      'daily_calorie_target', 'today_workout', 'today_workout_name',
      'today_nutrition', 'meals_today', 'current_plan_summary',
      'subscription', 'current_rank', 'next_rank', 'motivational_style',
    };

    var size = jsonEncode(s).length;
    if (size <= budget) return s;
    final before = size;

    var guard = 0;
    while (size > budget && guard++ < 80) {
      String? biggestKey;
      var biggestLen = 0;
      s.forEach((k, v) {
        if (keep.contains(k)) return;
        final len = jsonEncode(v).length;
        if (len > biggestLen) {
          biggestLen = len;
          biggestKey = k;
        }
      });
      // Nothing left worth trimming (only small or kept fields remain).
      final bk = biggestKey;
      if (bk == null || biggestLen < 60) break;
      final v = s[bk];
      if (v is List && v.length > 1) {
        s[bk] = v.sublist(0, (v.length / 2).ceil());
      } else if (v is Map && v.length > 1) {
        final ks = v.keys.toList();
        final keepN = (ks.length / 2).ceil();
        s[bk] = {for (final k in ks.take(keepN)) k: v[k]};
      } else {
        s.remove(bk);
      }
      size = jsonEncode(s).length;
    }

    if (size < before) {
      debugPrint('[AiSnapshotBuilder] snapshot trimmed $before → $size chars '
          '(budget $budget) to fit the coach context limit.');
    }
    return s;
  }

  /// Enriches the base AI context with historical data when the user's
  /// message contains historical queries.
  ///
  /// Detects keywords like "last month", "history", "how has my", "best",
  /// "average", "since I started" etc. Then queries relevant repositories
  /// and appends the data to the context map. All queries are local Hive
  /// reads — zero network cost.
  Map<String, dynamic> enrichContextForQuery(
      String message, Map<String, dynamic> context) {
    final lower = message.toLowerCase();

    try {
      // Exercise history query (PR, progress for specific lift)
      final exerciseName = _detectExerciseName(lower);
      if (exerciseName != null && _isHistoricalQuery(lower)) {
        try {
          final history =
              WorkoutRepository.instance.getExercisePRHistory(exerciseName);
          if (history.isNotEmpty) {
            context['exercise_history'] = {
              'exercise': exerciseName,
              'records': history.take(20).toList(),
            };
          }
        } catch (e) {
          debugPrint('[AiSnapshotBuilder.enrichContextForQuery] exerciseHistory: $e');
        }
      }

      if (_containsAny(
              lower, ['protein', 'calories', 'carbs', 'macros', 'nutrition']) &&
          _isHistoricalQuery(lower)) {
        try {
          final trends = NutritionRepository.instance.getWeeklyAverages(weeks: 8);
          if (trends.isNotEmpty) {
            context['nutrition_trend'] = trends;
          }
        } catch (e) {
          debugPrint('[AiSnapshotBuilder.enrichContextForQuery] nutritionTrend: $e');
        }
      }

      if (_containsAny(lower, ['weight', 'scale', 'kg', 'lost', 'gained']) &&
          _isHistoricalQuery(lower)) {
        try {
          final weights = NutritionRepository.instance.getWeightHistory(days: 90);
          if (weights.isNotEmpty) {
            context['weight_trend'] = weights;
          }
        } catch (e) {
          debugPrint('[AiSnapshotBuilder.enrichContextForQuery] weightTrend: $e');
        }
      }

      if (_containsAny(lower,
          ['progress', 'how am i', 'improvement', 'transformation', 'results'])) {
        try {
          context['workout_adherence'] =
              WorkoutRepository.instance.getWorkoutAdherence(days: 90);
        } catch (e) {
          debugPrint('[AiSnapshotBuilder.enrichContextForQuery] workoutAdherence: $e');
        }
        try {
          context['nutrition_trend'] =
              NutritionRepository.instance.getWeeklyAverages(weeks: 12);
        } catch (e) {
          debugPrint('[AiSnapshotBuilder.enrichContextForQuery] progressNutritionTrend: $e');
        }
      }

      try {
        final dailyMacros = NutritionRepository.instance.getDailyMacros(days: 7);
        if (dailyMacros.isNotEmpty) {
          final avgCal = dailyMacros
              .map((d) => (d['calories'] as num?)?.toDouble() ?? 0)
              .reduce((a, b) => a + b) / dailyMacros.length;
          final avgPro = dailyMacros
              .map((d) => (d['protein'] as num?)?.toDouble() ?? 0)
              .reduce((a, b) => a + b) / dailyMacros.length;
          context['seven_day_nutrition'] = {
            'avg_calories': avgCal.round(),
            'avg_protein': avgPro.round(),
            'days_logged': dailyMacros.length,
          };
        }
      } catch (e) {
        debugPrint('[AiSnapshotBuilder.enrichContextForQuery] sevenDayNutrition: $e');
      }
    } catch (e) {
      debugPrint('[AiSnapshotBuilder.enrichContextForQuery] $e');
    }

    // Re-trim AFTER enrichment (Hermes L37 / diagnose a9c3e2 follow-up). The
    // historical adds above are NOT bounded to the base trim's 1500-char
    // headroom — a power user's weight_trend (90d) / workout_adherence (90d) /
    // nutrition_trend (12w) can each exceed it and re-breach the server's
    // 10000-char cap, re-bricking the coach for exactly the heavy user a9c3e2
    // set out to fix. The base high-signal fields are in `keep`, so the trim
    // shrinks the (less-critical) historical adds first. Budget 9500 keeps a
    // 500-char margin under the server cap.
    return trimSnapshotToBudget(context, budget: 9500);
  }

  bool _isHistoricalQuery(String text) {
    return _containsAny(text, [
      'last month',
      'last week',
      'past',
      'history',
      'trend',
      'how has',
      'how was',
      'over time',
      'january',
      'february',
      'march',
      'april',
      'since i started',
      'last 30',
      'last 90',
      'best',
      'worst',
      'average',
      'compared',
    ]);
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  String? _detectExerciseName(String text) {
    const knownExercises = [
      'bench press', 'squat', 'deadlift', 'overhead press',
      'barbell row', 'pull up', 'push up', 'lat pulldown',
      'leg press', 'shoulder press', 'bicep curl', 'tricep',
      'plank', 'lunge', 'dips', 'chest fly',
    ];
    for (final ex in knownExercises) {
      if (text.contains(ex)) return ex;
    }
    return null;
  }

  /// Test-only seam exposing _getMealsToday for unit tests that don't
  /// want to construct the entire snapshot.
  @visibleForTesting
  List<Map<String, dynamic>> mealsTodayForTest() => _getMealsToday();

  /// Test-only seam exposing _getNutritionTrend7d.
  @visibleForTesting
  List<Map<String, dynamic>> nutritionTrend7dForTest() =>
      _getNutritionTrend7d();

  // ── Private helpers ──────────────────────────────────────────

  Map<String, dynamic> _getInductionAndMusterKeys() {
    final coach = _hive.coachBox;

    final committedAt = coach.get('committed_at') as String?;
    int? daysSinceCommitment;
    if (committedAt != null) {
      final dt = DateTime.tryParse(committedAt);
      if (dt != null) daysSinceCommitment = DateTime.now().difference(dt).inDays;
    }

    return {
      'committed_at': committedAt,
      'committed_to_lt_cdr': (coach.get('committed_to_lt_cdr') as bool?) ?? false,
      'days_since_commitment': daysSinceCommitment,
      'why_now': coach.get('why_now') as String?,
      'definition_of_winning': coach.get('definition_of_winning') as String?,
      'known_injuries':
          (coach.get('known_injuries') as List?) ?? const <String>[],
      'typical_wake_time': coach.get('typical_wake_time') as String?,
      'preferred_workout_time': coach.get('preferred_workout_time') as String?,
      'body_part_priorities':
          (coach.get('body_part_priorities') as List?) ?? const <String>[],
    };
  }

  List<Map<String, dynamic>> _readCustomExercises() {
    final box = _hive.customBox;
    final result = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addExercise(Map<String, dynamic> v, Object fallbackKey) {
      final type = v['type'];
      if (type != null && type != 'exercise') return;

      final name = v['name'] as String?;
      if (name == null || name.isEmpty) return;

      final id = (v['id'] ?? fallbackKey).toString();
      if (!seenIds.add(id)) return;

      final equipment = v['equipment_needed'] ?? v['equipment'];
      final muscle = v['category'] ??
          v['muscle_group'] ??
          v['target_focus'] ??
          (v['primary_muscles'] is List &&
                  (v['primary_muscles'] as List).isNotEmpty
              ? (v['primary_muscles'] as List).first
              : null);

      result.add({
        'id': id,
        'name': name,
        'muscle_group': muscle,
        'equipment': equipment,
      });
    }

    for (final key in box.keys) {
      final v = box.get(key);
      if (v is Map) {
        addExercise(Map<String, dynamic>.from(v), key);
      } else if (v is List && key.toString() == 'custom_exercises') {
        for (final entry in v) {
          if (entry is Map) {
            addExercise(Map<String, dynamic>.from(entry), entry['id'] ?? key);
          }
        }
      }
    }

    return result;
  }

  List<Map<String, dynamic>> _readSavedTemplates() {
    final box = _hive.workoutBox;
    final result = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final v = box.get(key);
      if (v is! Map) continue;
      if (v['type'] != 'template') continue;

      final name = v['name'] as String?;
      if (name == null || name.isEmpty) continue;

      final id = (v['id'] ?? key).toString();
      final exercises = v['exercises'] as List? ?? const [];
      final assignedDays = v['assigned_days'] as List? ?? const [];
      final daysCount = assignedDays.isNotEmpty
          ? assignedDays.length
          : (v['days_count'] as int? ?? 1);
      final exerciseCount = (v['exercise_count'] as int?) ?? exercises.length;

      result.add({
        'id': id,
        'name': name,
        'days_count': daysCount,
        'exercise_count': exerciseCount,
      });
    }

    return result;
  }

  int _calculateAge(String? dateOfBirth) {
    if (dateOfBirth == null) return 0;
    final dob = DateTime.tryParse(dateOfBirth);
    if (dob == null) return 0;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Map<String, dynamic> _getThisWeekWorkouts() {
    final workoutBox = _hive.workoutBox;
    final now = istNow();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekStartStr = istDateStr(weekStart);
    final weekEndStr = istDateStr(weekEnd);
    final todayStr = istDateStr(now);

    int completed = 0;
    int planned = 0;
    bool completedToday = false;
    final exerciseNames = <String>[];

    // Drift fix · APK Test #8 / Theme D — WorkoutWriteService.logExercise writes
    // entries keyed exlog_* WITHOUT a 'type' field. Read Hive entry key directly
    // so all exlog_* rows are captured regardless of which writer produced them.
    final entries = workoutBox.toMap();
    for (final entry in entries.entries) {
      final keyStr = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      if (log['type'] == 'workout_log') {
        final date = log['date'] as String? ?? '';
        if (date.compareTo(weekStartStr) >= 0 && date.compareTo(weekEndStr) <= 0) {
          completed++;
          if (date == todayStr) completedToday = true;
        }
      }
      if (keyStr.startsWith('exlog_')) {
        final date = log['date'] as String? ?? '';
        if (date == todayStr) {
          exerciseNames.add(log['exercise_name'] as String? ?? '');
        }
      }
      if (log['type'] == 'workout') {
        final date = log['date'] as String? ?? '';
        if (date.compareTo(weekStartStr) >= 0 && date.compareTo(weekEndStr) <= 0) {
          planned++;
        }
      }
    }

    return {
      'completed_this_week': completed,
      'planned_this_week': planned > 0 ? planned : 4,
      'completed_today': completedToday,
      'today_exercises': exerciseNames.take(5).toList(),
    };
  }

  List<Map<String, dynamic>> _getStepHistory({int days = 7}) {
    final healthBox = _hive.healthBox;
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < days; i++) {
      final d = istNow().subtract(Duration(days: i));
      final dateStr = istDateStr(d);
      final raw = healthBox.get('step_$dateStr');
      if (raw is Map) {
        final log = Map<String, dynamic>.from(raw);
        if (log['type'] == 'step_log') {
          result.add({
            'date': dateStr,
            'steps': (log['steps'] as num?)?.toInt() ?? 0,
          });
        }
      }
    }

    return result;
  }

  int _getTodaySteps() {
    final healthBox = _hive.healthBox;
    final todayStr = istDateStr(DateTime.now());

    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'step_log' && log['date'] == todayStr) {
        return (log['steps'] as num?)?.toInt() ?? 0;
      }
    }

    final stepsDate = healthBox.get('steps_date') as String?;
    if (stepsDate == todayStr) {
      return (healthBox.get('steps_today') as num?)?.toInt() ?? 0;
    }

    return 0;
  }

  Map<String, dynamic> _getTodayNutrition() {
    final nutritionBox = _hive.nutritionBox;
    final todayStr = istTodayStr();

    double calories = 0, protein = 0, carbs = 0, fat = 0, fiber = 0;

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String? ?? '';
      if (date == todayStr) {
        calories += (log['total_calories'] as num?)?.toDouble() ?? 0;
        protein += (log['total_protein'] as num?)?.toDouble() ?? 0;
        carbs += (log['total_carbs'] as num?)?.toDouble() ?? 0;
        fat += (log['total_fat'] as num?)?.toDouble() ?? 0;
        fiber += (log['total_fiber'] as num?)?.toDouble() ?? 0;
      }
    }

    final healthBox = _hive.healthBox;
    final waterData = healthBox.get('water_ml_$todayStr');
    final waterMl = (waterData is int)
        ? waterData
        : (waterData is Map)
            ? ((waterData['total_ml'] as num?)?.toInt() ?? 0)
            : 0;

    final urineData = healthBox.get('urine_color_$todayStr');
    String? urineStatus;
    if (urineData is Map) {
      urineStatus = urineData['label'] as String?;
    }

    return {
      'calories_logged': calories.round(),
      'protein_g': protein.round(),
      'carbs_g': carbs.round(),
      'fat_g': fat.round(),
      'fiber_g': fiber.round(),
      'fiber_target_g': 30,
      'water_ml': waterMl,
      'urine_status': ?urineStatus,
    };
  }

  /// Reads today's nlog_* rows from nutritionBox, groups by meal_type,
  /// and returns a list of {slot, items, total_kcal, total_protein_g}
  /// maps. Up to 4 slots (breakfast/lunch/dinner/snacks).
  List<Map<String, dynamic>> _getMealsToday() {
    final nutritionBox = _hive.nutritionBox;
    final todayStr = istDateStr(DateTime.now());

    const slotOrder = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final bySlot = <String, List<Map<String, dynamic>>>{};

    final entries = nutritionBox.toMap();
    for (final entry in entries.entries) {
      final keyStr = entry.key.toString();
      if (!keyStr.startsWith('nlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != todayStr) continue;
      final mealType = (log['meal_type'] as String?)?.toLowerCase();
      if (mealType == null || mealType.isEmpty) continue;
      final slot = _canonicalSlot(mealType);

      bySlot.putIfAbsent(slot, () => []).add({
        'name': log['food_name'] ?? 'Unknown',
        'kcal': (log['total_calories'] as num?)?.toInt() ?? 0,
        'protein_g': (log['total_protein'] as num?)?.toInt() ?? 0,
        'carbs_g': (log['total_carbs'] as num?)?.toInt() ?? 0,
        'fat_g': (log['total_fat'] as num?)?.toInt() ?? 0,
      });
    }

    final result = <Map<String, dynamic>>[];
    for (final slot in slotOrder) {
      final rows = bySlot[slot];
      if (rows == null || rows.isEmpty) continue;
      var totalK = 0;
      var totalP = 0;
      for (final r in rows) {
        totalK += (r['kcal'] as int);
        totalP += (r['protein_g'] as int);
      }
      result.add({
        'slot': slot,
        'items': rows,
        'total_kcal': totalK,
        'total_protein_g': totalP,
      });
    }
    return result;
  }

  String _canonicalSlot(String raw) {
    final s = raw.toLowerCase();
    if (s == 'snack' || s == 'snacks' || s == 'mid_morning' ||
        s == 'evening' || s == 'mid-morning' || s == 'evening_snack') {
      return 'snacks';
    }
    if (s == 'breakfast') return 'breakfast';
    if (s == 'lunch') return 'lunch';
    if (s == 'dinner') return 'dinner';
    return 'snacks';
  }

  List<Map<String, dynamic>> _getNutritionTrend7d() {
    final nutritionBox = _hive.nutritionBox;
    final now = nowWall();

    final windowDates = <String>[
      for (var i = 0; i < 7; i++) istDateStr(now.subtract(Duration(days: i))),
    ];
    final windowSet = windowDates.toSet();

    final byDate = <String, Map<String, int>>{};
    final entries = nutritionBox.toMap();
    for (final entry in entries.entries) {
      final keyStr = entry.key.toString();
      if (!keyStr.startsWith('nlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final dateStr = log['date'] as String?;
      if (dateStr == null || !windowSet.contains(dateStr)) continue;

      final bucket = byDate.putIfAbsent(
        dateStr,
        () => {'calories': 0, 'protein_g': 0, 'carbs_g': 0, 'fat_g': 0, 'fiber_g': 0},
      );
      bucket['calories'] = bucket['calories']! + ((log['total_calories'] as num?)?.toInt() ?? 0);
      bucket['protein_g'] = bucket['protein_g']! + ((log['total_protein'] as num?)?.toInt() ?? 0);
      bucket['carbs_g'] = bucket['carbs_g']! + ((log['total_carbs'] as num?)?.toInt() ?? 0);
      bucket['fat_g'] = bucket['fat_g']! + ((log['total_fat'] as num?)?.toInt() ?? 0);
      bucket['fiber_g'] = bucket['fiber_g']! + ((log['total_fiber'] as num?)?.toInt() ?? 0);
    }

    return [
      for (final dateStr in windowDates)
        {
          'date': dateStr,
          'calories': byDate[dateStr]?['calories'] ?? 0,
          'protein_g': byDate[dateStr]?['protein_g'] ?? 0,
          'carbs_g': byDate[dateStr]?['carbs_g'] ?? 0,
          'fat_g': byDate[dateStr]?['fat_g'] ?? 0,
          'fiber_g': byDate[dateStr]?['fiber_g'] ?? 0,
        },
    ];
  }

  Map<String, dynamic> _getLatestWeight() {
    final healthBox = _hive.healthBox;
    String? latestDate;
    double? latestWeight;
    double? previousWeight;

    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'weight_log') continue;
      final date = log['date'] as String? ?? '';
      final weight = (log['weight_kg'] as num?)?.toDouble();
      if (weight == null) continue;

      if (latestDate == null || date.compareTo(latestDate) > 0) {
        previousWeight = latestWeight;
        latestWeight = weight;
        latestDate = date;
      }
    }

    return {
      'current_kg': latestWeight ?? 0,
      'previous_kg': previousWeight ?? 0,
      'date': latestDate ?? '',
    };
  }

  Map<String, dynamic> _getPersonalRecords() {
    final workoutBox = _hive.workoutBox;
    final prs = <String, double>{};

    final entries = workoutBox.toMap();
    for (final entry in entries.entries) {
      final keyStr = entry.key.toString();
      if (!keyStr.startsWith('exlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final name = log['exercise_name'] as String? ?? '';
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (name.isNotEmpty && weight > 0) {
        final best = prs[name] ?? 0;
        if (weight > best) prs[name] = weight;
      }
    }

    final sorted = prs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = <String, double>{};
    for (final entry in sorted.take(5)) {
      top[entry.key] = entry.value;
    }
    return top;
  }

  List<String> _getCoachNotices() {
    try {
      final insights = PatternDetector.instance.analyze();
      return insights
          .where((i) => i.severity != InsightSeverity.low)
          .map((i) => i.coachNotice)
          .take(5)
          .toList();
    } catch (e) {
      debugPrint('[AiSnapshotBuilder._getCoachNotices] $e');
      return [];
    }
  }

  List<String> _getCoachingNotes() {
    final notes = _hive.coachBox.get('coaching_notes');
    if (notes is Map) {
      final notesList = notes['notes'] as List?;
      if (notesList != null) {
        return notesList.cast<String>().toList();
      }
    }
    return [];
  }

  Map<String, dynamic>? _getCoachMemoryForContext() {
    try {
      final mem = CoachMemory.readFromBox(_hive.coachBox);
      if (mem == null || mem.privateMode) return null;
      return mem.toJson();
    } catch (e) {
      debugPrint('[AiSnapshotBuilder] coach_memory read failed: $e');
      return null;
    }
  }

  String _getFitnessSummary() {
    return _hive.coachBox.get('fitness_summary') as String? ?? '';
  }

  // ── Anti-fabrication grounding helpers (APK Test #4 / A3) ────────────────

  Map<String, dynamic> _computeDataWindowGrounding() {
    final box = _hive.workoutBox;
    final wlogKeys =
        box.keys.where((k) => k.toString().startsWith('wlog_')).toList();

    if (wlogKeys.isEmpty) {
      return {
        'data_window_days': 0,
        'first_workout_date': null,
        'workout_logs_count': 0,
      };
    }

    DateTime? earliestDate;
    for (final key in wlogKeys) {
      final log = box.get(key);
      if (log is! Map) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      if (earliestDate == null || date.isBefore(earliestDate)) {
        earliestDate = date;
      }
    }

    if (earliestDate == null) {
      return {
        'data_window_days': 0,
        'first_workout_date': null,
        'workout_logs_count': wlogKeys.length,
      };
    }

    final daysSince = DateTime.now().difference(earliestDate).inDays;
    return {
      'data_window_days': daysSince,
      'first_workout_date': istDateStr(earliestDate),
      'workout_logs_count': wlogKeys.length,
    };
  }

  int _countNutritionLogsLast7Days() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    int count = 0;
    for (final key in _hive.nutritionBox.keys) {
      if (!key.toString().startsWith('nlog_')) continue;
      final log = _hive.nutritionBox.get(key);
      if (log is! Map) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;
      count++;
    }
    return count;
  }

  int _countSleepLogsLast7Days() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    int count = 0;
    for (final key in _hive.healthBox.keys) {
      if (!key.toString().startsWith('sleep_log_')) continue;
      final log = _hive.healthBox.get(key);
      if (log is! Map) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;
      count++;
    }
    return count;
  }

  // ── Workout schedule snapshot helpers ────────────────────────────────────

  Map<String, dynamic>? _getTodayWorkout() {
    final today = istDateStr(DateTime.now());
    return _buildWorkoutSnapshotForDate(today);
  }

  String? _topLevelTodayWorkoutName() {
    final tw = _getTodayWorkout();
    if (tw == null) return null;
    final name = tw['workout_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    return tw['type'] as String?;
  }

  dynamic _topLevelRecentPrField(String field) {
    final summary = _getPRTimelineSummary();
    final recent = summary['recent_prs'];
    if (recent is! List || recent.isEmpty) return null;
    final first = recent.first;
    if (first is! Map) return null;
    if (field == 'exercise_name') {
      return first['exercise_name'] ?? first['exercise'] ?? first['name'];
    }
    if (field == 'weight_kg') {
      return first['weight_kg'] ?? first['weight'] ?? first['bestValue'];
    }
    return first[field];
  }

  int _topLevelYesterdayCalories() {
    final yesterdayStr =
        istDateStr(DateTime.now().subtract(const Duration(days: 1)));
    double total = 0;
    for (final raw in _hive.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] == yesterdayStr) {
        total += (log['total_calories'] as num?)?.toDouble() ?? 0;
      }
    }
    return total.round();
  }

  Map<String, dynamic>? _getYesterdayWorkout() {
    final yesterday =
        istDateStr(DateTime.now().subtract(const Duration(days: 1)));
    return _buildWorkoutSnapshotForDate(yesterday);
  }

  Map<String, dynamic>? _buildWorkoutSnapshotForDate(String dateStr) {
    final schedule = _hive.workoutBox.get('schedule_$dateStr');
    if (schedule is! Map) return null;

    final logIndex = _hive.workoutBox.get('exercise_log_index_$dateStr');
    final logged = <Map<String, dynamic>>[];
    if (logIndex is List) {
      for (final key in logIndex) {
        final raw = _hive.workoutBox.get(key);
        if (raw is! Map) continue;
        final log = Map<String, dynamic>.from(raw);
        final sets = (log['sets'] as List?) ?? const [];
        final totalReps = sets.fold<int>(
          0,
          (a, s) =>
              a + (((s is Map ? s['reps'] : null) as num?)?.toInt() ?? 0),
        );
        final loggingType = log['logging_type'] as String?;
        final isWeighted = loggingType == 'weight_reps' ||
            loggingType == 'weighted_bodyweight';
        final double? topWeight = isWeighted
            ? sets
                .map((s) =>
                    (((s is Map ? s['weight_kg'] : null) as num?) ?? 0)
                        .toDouble())
                .fold<double>(0, (a, b) => b > a ? b : a)
            : null;
        logged.add({
          'name': log['exercise_name'] ?? 'Unknown',
          'sets': sets.length,
          'reps_total': totalReps,
          'top_set_weight_kg': ?topWeight,
          'logging_type': loggingType,
          'is_pr': log['is_pr'] ?? false,
        });
      }
    }

    return {
      'type':
          (schedule['type'] ?? schedule['workout_name'] ?? 'UNKNOWN') as String,
      'status': (schedule['status'] ?? 'pending') as String,
      'exercises': logged,
    };
  }

  List<Map<String, dynamic>> _getWeekLookahead() {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final dateStr = istDateStr(date);
      final dayLabel = dayNames[(istDateOf(date).weekday - 1) % 7];
      final schedule = _hive.workoutBox.get('schedule_$dateStr');
      if (schedule is Map) {
        results.add({
          'day': dayLabel,
          'date': dateStr,
          'type': (schedule['type'] ?? schedule['workout_name'] ?? 'UNKNOWN') as String,
          'status': (schedule['status'] ?? 'pending') as String,
        });
      } else {
        results.add({
          'day': dayLabel,
          'date': dateStr,
          'type': 'REST',
          'status': 'rest',
        });
      }
    }
    return results;
  }

  Map<String, dynamic> _getCurrentPlanSummary() {
    final progress = (_hive.userBox.get('progress') as Map?) ?? const {};
    final profile = (_hive.userBox.get('profile') as Map?) ?? const {};

    final phase = (progress['current_phase'] as int?) ?? 1;
    final week = (progress['current_week'] as int?) ?? 1;
    final daysPerWeek = (profile['days_per_week'] as int?) ?? 4;

    final weeklySessionsMap = <String, Map<String, dynamic>>{};
    for (int i = 0; i < 7; i++) {
      final dateStr = istDateStr(DateTime.now().add(Duration(days: i)));
      final schedule = _hive.workoutBox.get('schedule_$dateStr');
      if (schedule is! Map) continue;

      final type = (schedule['type'] ?? schedule['workout_name']) as String?;
      if (type == null || type == 'REST') continue;
      if (weeklySessionsMap.containsKey(type)) continue;

      final exercises = ((schedule['exercises'] as List?) ?? const [])
          .whereType<Map>()
          .map((ex) => <String, dynamic>{
                'name': ex['name'],
                'sets': ex['sets'],
                'reps': ex['reps'],
                'weight': ex['weight'],
              })
          .toList();

      weeklySessionsMap[type] = {
        'name': type,
        'exercises': exercises,
      };
    }

    return {
      'phase': phase,
      'week': week,
      'days_per_week': daysPerWeek,
      'weekly_sessions': weeklySessionsMap.values.toList(),
    };
  }

  // ── Sleep, water, freezes, subscription, rank, cadence, ETA ──────────────

  List<Map<String, dynamic>> _getSleep7d() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final results = <Map<String, dynamic>>[];
    for (final key in _hive.healthBox.keys) {
      if (!key.toString().startsWith('sleep_log_')) continue;
      final log = _hive.healthBox.get(key);
      if (log is! Map) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;
      final h = (log['sleep_hours'] as num?) ?? (log['hours'] as num?) ?? 0;
      results.add({'date': dateStr, 'hours': h.toDouble()});
    }
    results.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return results;
  }

  List<Map<String, dynamic>> _getWater7d() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final results = <Map<String, dynamic>>[];
    for (final key in _hive.healthBox.keys) {
      if (!key.toString().startsWith('water_ml_')) continue;
      final datePart = key.toString().substring('water_ml_'.length);
      final date = DateTime.tryParse(datePart);
      if (date == null || date.isBefore(cutoff)) continue;
      final raw = _hive.healthBox.get(key);
      final ml = (raw is int)
          ? raw
          : (raw is Map)
              ? ((raw['total_ml'] as num?)?.toInt() ?? 0)
              : 0;
      results.add({'date': datePart, 'ml': ml});
    }
    results.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return results;
  }

  int _getStreakFreezesAvailable() {
    final progress = _hive.userBox.get('progress') as Map?;
    return (progress?['streak_freezes_available'] as int?) ?? 0;
  }

  String? _getStreakFreezesRefillDate() {
    final progress = _hive.userBox.get('progress') as Map?;
    return progress?['streak_freezes_last_refill'] as String?;
  }

  Map<String, dynamic> _getSubscriptionState() {
    final isPro = SubscriptionService.instance.isPro();
    final config = _hive.configBox;
    final expiresAtRaw = config.get('expiresAt');
    String? expiresAtIso;
    if (expiresAtRaw is String) {
      expiresAtIso = expiresAtRaw;
    } else if (expiresAtRaw is DateTime) {
      expiresAtIso = expiresAtRaw.toIso8601String();
    }
    return {
      'tier': isPro ? 'pro' : 'free',
      'expires_at': expiresAtIso,
      'plan': config.get('plan') as String?,
      'auto_renew': (config.get('auto_renew') as bool?) ?? false,
    };
  }

  Map<String, dynamic> _getCurrentRankFromLadder() {
    final profile = _hive.userBox.get('profile') as Map?;
    final code = (profile?['current_rank_code'] as String?) ?? 'SD2';
    final entry = rankByCode(code) ?? kRankLadder.first;
    final totalWorkouts = _hive.workoutBox.keys
        .where((k) => k.toString().startsWith('wlog_'))
        .length;
    final earnedAt = profile?['current_rank_earned_at'] as String?;
    return {
      'code': entry.code,
      'display': entry.displayName,
      'earned_at': earnedAt,
      'total_workouts': totalWorkouts,
    };
  }

  Map<String, dynamic>? _getNextRankFromLadder() {
    final profile = _hive.userBox.get('profile') as Map?;
    final currentCode = (profile?['current_rank_code'] as String?) ?? 'SD2';
    final currentIdx = kRankLadder.indexWhere((r) => r.code == currentCode);
    if (currentIdx == -1 || currentIdx >= kRankLadder.length - 1) return null;

    final next = kRankLadder[currentIdx + 1];
    final gate = kRankGates[next.code];

    final totalWorkouts = _hive.workoutBox.keys
        .where((k) => k.toString().startsWith('wlog_'))
        .length;
    final grounding = _computeDataWindowGrounding();
    final weeksElapsed = ((grounding['data_window_days'] as int) / 7).floor();

    final reqs = <String, int>{};
    if ((gate?.totalWorkoutsAtLeast ?? 0) > 0) {
      reqs['workouts'] = gate!.totalWorkoutsAtLeast!;
    }
    if ((gate?.streakAtLeast ?? 0) > 0) {
      reqs['streak_days'] = gate!.streakAtLeast!;
    }
    if ((gate?.minWeeksSinceSignup ?? next.minWeeks) > 0) {
      reqs['weeks'] = gate?.minWeeksSinceSignup ?? next.minWeeks;
    }
    if ((gate?.deploymentsCompleteAtLeast ?? 0) > 0) {
      reqs['deployments'] = gate!.deploymentsCompleteAtLeast!;
    }

    final remaining = <String, int>{};
    String binding = 'workouts';
    int maxRemaining = -1;

    reqs.forEach((k, required) {
      int current = 0;
      if (k == 'workouts') {
        current = totalWorkouts;
      } else if (k == 'weeks') {
        current = weeksElapsed;
      }
      final rem = (required - current).clamp(0, required);
      remaining[k] = rem;
      if (rem > maxRemaining) {
        maxRemaining = rem;
        binding = k;
      }
    });

    return {
      'code': next.code,
      'display': next.displayName,
      'requirements': Map<String, dynamic>.from(reqs),
      'current_state': {
        'workouts': totalWorkouts,
        'weeks': weeksElapsed,
      },
      'remaining': remaining,
      'binding_constraint': binding,
    };
  }

  double _computeWorkoutsPerWeekLast4Weeks() {
    final cutoff = DateTime.now().subtract(const Duration(days: 28));
    int count = 0;
    for (final key in _hive.workoutBox.keys) {
      if (!key.toString().startsWith('wlog_')) continue;
      final log = _hive.workoutBox.get(key);
      if (log is! Map) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;
      count++;
    }
    return count / 4.0;
  }

  // ── Closeout snapshot-key helpers ─────────────────────────────────────────

  Map<String, dynamic> _getPRTimelineSummary() {
    final box = _hive.workoutBox;
    final byExercise = <String, Map<String, dynamic>>{};
    int totalPrs = 0;

    for (final key in box.keys) {
      if (!key.toString().startsWith('exlog_')) continue;
      final log = box.get(key);
      if (log is! Map) continue;
      if (log['is_pr'] != true) continue;
      totalPrs++;
      final name = log['exercise_name'] as String?;
      final dateStr = log['date'] as String?;
      if (name == null || dateStr == null) continue;
      final existing = byExercise[name];
      if (existing == null ||
          (existing['set_date'] as String).compareTo(dateStr) < 0) {
        byExercise[name] = {
          'exercise': name,
          'weight': (log['weight_kg'] as num?)?.toDouble() ?? 0,
          // Drift-fix batch 2026-05-24 / F1 workout (P1):
          // reps_completed is SUM across sets per WriteService contract.
          // Use prSetRepsForExlog to find reps at the PR weight (heaviest
          // set), with legacy fallthrough. See AiCoachRepository helper.
          'reps':
              AiCoachRepository.prSetRepsForExlog(Map<String, dynamic>.from(log)) ??
                  0,
          'set_date': dateStr,
        };
      }
    }

    final recent = byExercise.values.toList()
      ..sort((a, b) =>
          (b['set_date'] as String).compareTo(a['set_date'] as String));

    return {
      'total_prs': totalPrs,
      'recent_prs': recent.take(5).toList(),
    };
  }

  String? _getGoalChangedAt() {
    final profile = _hive.userBox.get('profile') as Map?;
    return profile?['goal_changed_at'] as String? ??
        profile?['primary_goal_updated_at'] as String?;
  }

  Map<String, dynamic> _getBodyMeasurements() {
    final results = <String, dynamic>{};
    final latestByType = <String, DateTime>{};

    for (final key in _hive.healthBox.keys) {
      final k = key.toString();
      if (!k.startsWith('measurement_')) continue;
      final raw = _hive.healthBox.get(key);
      if (raw is! Map) continue;
      final dateStr = raw['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      for (final field in ['chest', 'waist', 'hips', 'arms']) {
        final v = (raw[field] as num?)?.toDouble();
        if (v == null) continue;
        final prev = latestByType[field];
        if (prev == null || date.isAfter(prev)) {
          latestByType[field] = date;
          results[field] = v;
        }
      }
    }

    return results;
  }

  String? _getOnboardingCompletedAt() {
    final profile = _hive.userBox.get('profile') as Map?;
    return profile?['onboarding_completed_at'] as String?;
  }

  List<Map<String, dynamic>> _getPhaseTransitions() {
    final progress = _hive.userBox.get('progress') as Map?;
    final history = progress?['phase_history'] as List?;
    if (history == null || history.isEmpty) return const [];
    return history
        .whereType<Map>()
        .take(3)
        .map((m) => {
              'from_phase': m['from_phase'],
              'to_phase': m['to_phase'],
              'transitioned_at': m['transitioned_at'],
            })
        .toList();
  }

  List<Map<String, dynamic>> _getRecentMealDeletes() {
    final raw = _hive.nutritionBox.get('recent_deletes');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .take(5)
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Map<String, dynamic>? _getEtaNextPromotion() {
    final next = _getNextRankFromLadder();
    if (next == null) return null;

    final remaining = next['remaining'] as Map<String, int>;
    final remainingWorkouts = remaining['workouts'] ?? 0;

    if (remainingWorkouts == 0) {
      final today = istDateStr(DateTime.now());
      return {
        'at_current_cadence': {'days': 0, 'date': today},
        'at_plan_cadence': {'days': 0, 'date': today},
      };
    }

    final currentCadence = _computeWorkoutsPerWeekLast4Weeks();
    final profile = _hive.userBox.get('profile') as Map?;
    final planCadence = (profile?['days_per_week'] as int?) ?? 4;

    final daysAtCurrent = currentCadence > 0
        ? (remainingWorkouts * 7 / currentCadence).ceil()
        : 999;
    final daysAtPlan = (remainingWorkouts * 7 / planCadence).ceil();

    return {
      'at_current_cadence': {
        'days': daysAtCurrent,
        'date': istDateStr(DateTime.now().add(Duration(days: daysAtCurrent))),
      },
      'at_plan_cadence': {
        'days': daysAtPlan,
        'date': istDateStr(DateTime.now().add(Duration(days: daysAtPlan))),
      },
    };
  }
}
