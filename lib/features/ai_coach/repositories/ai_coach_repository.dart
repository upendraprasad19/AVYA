import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/features/train/services/active_workout_persistence.dart';
import '../services/identity_signal_detector.dart';
import '../models/coach_memory.dart';

/// Repository for AI Coach data access.
///
/// Builds the full user_daily_snapshot context (~300 tokens) that gets
/// injected into the AI system prompt for personalised coaching.
/// Also handles coaching_notes extraction and interaction persistence.
class AiCoachRepository {
  AiCoachRepository._();
  static final AiCoachRepository _instance = AiCoachRepository._();
  static AiCoachRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;
  final IdentitySignalDetector _identityDetector = IdentitySignalDetector();
  String? _lastIdentityUserId;

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

    return {
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

      // Phase A.9 — let the coach reference the user's existing custom
      // exercises and saved templates in tool args (e.g. swap_exercise
      // toExerciseId from snapshot.custom_exercises[].id, or a future
      // schedule_template referencing snapshot.saved_templates[].id).
      // Token cost: ~200-500 bytes for typical users (0-5 customs,
      // 0-3 templates), well under the 9.5KB compaction cap.
      'custom_exercises': _readCustomExercises(),
      'saved_templates': _readSavedTemplates(),

      // APK Test #3 / Q6.3 (2026-04-26): expand snapshot so the AI coach
      // can reference what the user actually ate today and across the
      // last 7 days. Per-turn cost ~500-700 bytes; both keys drop early
      // in _compactContext so they never push past the 9.5 KB ceiling.
      'meals_today': _getMealsToday(),
      'nutrition_trend_7d': _getNutritionTrend7d(),

      // APK Test #4 / A3: anti-fabrication grounding keys.
      // Captain Manual §8 references these to refuse history-beyond-window
      // claims ("no data from last year — 8 days on roster").
      // ~60-80 bytes. Dropped last in _compactContext (very small).
      ..._computeDataWindowGrounding(),
      'nutrition_logs_count_7d': _countNutritionLogsLast7Days(),
      'sleep_logs_count_7d': _countSleepLogsLast7Days(),

      // APK Test #4 / A4: workout schedule snapshot keys.
      // Closes audit A2 (yesterday_workout) and OBS-1 gap (today's session
      // contents visible to coach without user having to repeat them).
      // week_lookahead gives the coach full context for schedule questions
      // ("what's my plan this week?", "when's my next leg day?").
      // ~150-400 bytes typical (7 entries × 4 fields each).
      'today_workout': _getTodayWorkout(),
      'yesterday_workout': _getYesterdayWorkout(),
      'week_lookahead': _getWeekLookahead(),

      // APK Test #4 / A5: full plan structure summary.
      // Closes OBS-2 (coach was asking "what exercises are in your leg day?"
      // even though the plan was generated locally and stored in Hive).
      // Deduped by session name so PPL never emits PUSH A twice.
      // ~200-600 bytes typical (3-6 unique sessions × 4-10 exercises each).
      'current_plan_summary': _getCurrentPlanSummary(),

      // APK Test #4 / A6: sleep, water, streak freezes, subscription, rank
      // progression, cadence, and ETA to next rank promotion.
      // Closes audit A1 (sleep_7d), A3 (streak_freezes), P2 (subscription).
      // Total size: ~300-500 bytes typical. All null-safe with sensible defaults.
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

      // APK Test #4 / A7: mid-workout state for real-time coaching context.
      // Written on every set log by ActiveWorkoutPersistence.writeState().
      // Cleared on workout completion or abandonment.
      // Auto-clears stale entries (>2h) on read so it's never leftover.
      // Null when user is not actively in a workout session.
      // Closes audit A4 — Captain can now answer "should I add another set?"
      // with knowledge of current exercise, set#, weight, reps, RPE history.
      // ~100-150 bytes when present; drops early in _compactContext (null = 0 bytes).
      'active_workout': ActiveWorkoutPersistence.readState(),

      // APK Test #4 / A8: induction commitment + 5-question muster answers.
      // Plan B writes these on user induction (3-message intro + I COMMIT
      // button + 5-question interview). A8 exposes them so Captain Manual §2
      // (Lt Cdr Contract recall) and §10.1 idea #1 (why-now anchor recall)
      // have data the moment Plan B ships. All null-safe for un-inducted users.
      // ~100-200 bytes when present; 0 bytes (null/false/empty) until Plan B.
      ..._getInductionAndMusterKeys(),
    };
  }

  /// Reads induction commitment + 5-question muster answers from coachBox.
  /// Returns 9 null-safe keys. All keys default to null/false/empty when
  /// the user has not yet completed Plan B's induction flow.
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

  /// Reads all custom exercises the user has created from customBox.
  ///
  /// Two storage formats coexist (Bug #4 cloud sync fix, 2026-04-18):
  /// - **Per-key entries** (`custom_exercise_<timestamp>` → Map with
  ///   `type: 'exercise'`). Written by CreateCustomExerciseSheet._save.
  /// - **Legacy list-key** (`customBox.put('custom_exercises', [...])`).
  ///   Written by SyncService._restoreCustomExercises on cross-device
  ///   restore. Each list entry is the same exercise map shape.
  ///
  /// Returns a compact projection (id, name, muscle_group, equipment) so
  /// the snapshot doesn't bloat with logging defaults / community flags.
  List<Map<String, dynamic>> _readCustomExercises() {
    final box = _hive.customBox;
    final result = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addExercise(Map<String, dynamic> v, Object fallbackKey) {
      final type = v['type'];
      // Skip anything that isn't an exercise (custom foods live here too).
      if (type != null && type != 'exercise') return;

      final name = v['name'] as String?;
      if (name == null || name.isEmpty) return;

      final id = (v['id'] ?? fallbackKey).toString();
      if (!seenIds.add(id)) return; // dedupe across per-key + legacy list

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
        // Legacy list-key path written by restore.
        for (final entry in v) {
          if (entry is Map) {
            addExercise(Map<String, dynamic>.from(entry), entry['id'] ?? key);
          }
        }
      }
    }

    return result;
  }

  /// Reads all saved workout templates from workoutBox.
  ///
  /// Templates are identified by `type: 'template'` (not by key prefix —
  /// they're keyed `tmpl_<timestamp>` per TemplatesNotifier.saveTemplate).
  /// Each template has `name`, `exercises` (List), `assigned_days` (`List<int>`).
  ///
  /// Returns a compact projection so the AI knows what templates exist
  /// (referenced by Phase D's schedule_template tool) without ballooning
  /// the snapshot with full exercise lists.
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

  /// Enriches the base AI context with historical data when the user's
  /// message contains historical queries.
  ///
  /// Detects keywords like "last month", "history", "how has my", "best",
  /// "average", "since I started" etc. Then queries relevant repositories
  /// and appends the data to the context map.
  ///
  /// All queries are local Hive reads — zero network cost.
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
          debugPrint('[AiCoachRepository.enrichContextForQuery] exerciseHistory: $e');
        }
      }

      // Nutrition trend query
      if (_containsAny(
              lower, ['protein', 'calories', 'carbs', 'macros', 'nutrition']) &&
          _isHistoricalQuery(lower)) {
        try {
          final trends = NutritionRepository.instance.getWeeklyAverages(weeks: 8);
          if (trends.isNotEmpty) {
            context['nutrition_trend'] = trends;
          }
        } catch (e) {
          debugPrint('[AiCoachRepository.enrichContextForQuery] nutritionTrend: $e');
        }
      }

      // Weight trend query
      if (_containsAny(lower, ['weight', 'scale', 'kg', 'lost', 'gained']) &&
          _isHistoricalQuery(lower)) {
        try {
          final weights = NutritionRepository.instance.getWeightHistory(days: 90);
          if (weights.isNotEmpty) {
            context['weight_trend'] = weights;
          }
        } catch (e) {
          debugPrint('[AiCoachRepository.enrichContextForQuery] weightTrend: $e');
        }
      }

      // Progress / "how am I doing" query
      if (_containsAny(lower,
          ['progress', 'how am i', 'improvement', 'transformation', 'results'])) {
        try {
          context['workout_adherence'] =
              WorkoutRepository.instance.getWorkoutAdherence(days: 90);
        } catch (e) {
          debugPrint('[AiCoachRepository.enrichContextForQuery] workoutAdherence: $e');
        }
        try {
          context['nutrition_trend'] =
              NutritionRepository.instance.getWeeklyAverages(weeks: 12);
        } catch (e) {
          debugPrint('[AiCoachRepository.enrichContextForQuery] progressNutritionTrend: $e');
        }
      }

      // 7-day summary (always add if available)
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
        debugPrint('[AiCoachRepository.enrichContextForQuery] sevenDayNutrition: $e');
      }
    } catch (e) {
      // Enrichment is best-effort — never fail the AI call
      debugPrint('[AiCoachRepository.enrichContextForQuery] $e');
    }

    return context;
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

  /// Detect exercise name from the message by scanning known exercises.
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

  /// Saves an AI interaction to coachBox.
  Future<String> saveInteraction({
    required String userMessage,
    required String aiResponse,
    required String modelUsed,
    required String mode,
  }) async {
    final id = 'coach_${DateTime.now().millisecondsSinceEpoch}';
    await _hive.coachBox.put(id, {
      'id': id,
      'user_message': userMessage,
      'ai_response': aiResponse,
      'model_used': modelUsed,
      'mode': mode,
      'is_user_message': true,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  /// Runs the identity heuristics on a single user message and patches
  /// Hive coach_memory in place. No-op if no signals detected.
  Future<void> detectAndPersistIdentitySignals(String userMessage) async {
    final signals = _identityDetector.detect(userMessage);
    if (signals.communicationStyle == null && signals.preferredName == null) {
      return;
    }

    final userId = HiveService.instance.userBox.get('user_id') as String?;
    if (userId == null || userId.isEmpty) return;

    // Reset detector streak when the active user changes — the singleton
    // detector would otherwise leak Hinglish streak state across sessions.
    if (_lastIdentityUserId != null && _lastIdentityUserId != userId) {
      _identityDetector.resetStreak();
    }
    _lastIdentityUserId = userId;

    try {
      final coachBox = HiveService.instance.coachBox;
      final existing =
          CoachMemory.readFromBox(coachBox) ?? CoachMemory(userId: userId);
      final patched = existing.merge(CoachMemory(
        userId: userId,
        communicationStyle: signals.communicationStyle,
        preferredName: signals.preferredName,
        updatedAt: DateTime.now(),
      ));
      await patched.writeToBox(coachBox);
    } catch (e) {
      // A corrupt coach_memory blob must never crash the message-send hot
      // path. Log and continue — the next successful write will heal it.
      debugPrint('[AiCoachRepository] identity persist failed: $e');
      return;
    }
  }

  /// Bug #19 — Persists the user message immediately, BEFORE the AI call.
  /// Marks the entry as `pending: true` so [ChatHistoryNotifier] can render
  /// it as a loading bubble even if the app is killed mid-call. Returns the
  /// Hive key so the caller can update it on success/failure.
  Future<String> saveUserMessagePending({
    required String userMessage,
    required String mode,
    String? mediaUrl,
    String? mediaType,
  }) async {
    // Run cheap on-device identity heuristics on every outbound user message.
    // Patches Hive coach_memory in place; no-op if no signals detected.
    await detectAndPersistIdentitySignals(userMessage);

    final id = 'coach_${DateTime.now().millisecondsSinceEpoch}';
    await _hive.coachBox.put(id, {
      'id': id,
      'user_message': userMessage,
      'ai_response': '',
      'model_used': '',
      'mode': mode,
      'is_user_message': true,
      'pending': true,
      'failed': false,
      'created_at': DateTime.now().toIso8601String(),
      'media_url': ?mediaUrl,
      'media_type': ?mediaType,
    });
    return id;
  }

  /// Bug #19 — Updates a pending interaction with the AI's reply on success.
  /// Clears the `pending` flag and writes the model used. Used by both
  /// [SendMessageNotifier.send] and [SendMessageNotifier.sendWithMedia].
  Future<void> updateInteractionWithResponse(
    String key, {
    required String aiResponse,
    required String modelUsed,
  }) async {
    final raw = _hive.coachBox.get(key);
    if (raw is! Map) return;
    final entry = Map<String, dynamic>.from(raw);
    entry['ai_response'] = aiResponse;
    entry['model_used'] = modelUsed;
    entry['pending'] = false;
    entry['failed'] = false;
    entry.remove('error_text');
    await _hive.coachBox.put(key, entry);
  }

  /// Bug #19 — Marks a pending interaction as failed with the error text.
  /// The user message stays in coachBox so it survives an app restart, and
  /// [ChatHistoryNotifier] surfaces it as an error bubble with a Retry button.
  Future<void> updateInteractionWithError(
    String key, {
    required String errorText,
  }) async {
    final raw = _hive.coachBox.get(key);
    if (raw is! Map) return;
    final entry = Map<String, dynamic>.from(raw);
    entry['ai_response'] = '';
    entry['pending'] = false;
    entry['failed'] = true;
    entry['error_text'] = errorText;
    await _hive.coachBox.put(key, entry);
  }

  /// Counts only user messages sent today (not AI responses).
  int getTodayUserMessageCount() {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    int count = 0;
    for (final raw in _hive.coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      // Only count entries that have a user_message (not pure AI entries)
      final hasUserMsg = interaction['user_message'] as String?;
      if (createdAt.startsWith(todayStr) &&
          hasUserMsg != null &&
          hasUserMsg.isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  /// Gets the latest coaching insight from coaching_notes or last AI response.
  String getLatestInsight() {
    final notes = _hive.coachBox.get('coaching_notes');
    if (notes is Map) {
      final notesList = notes['notes'] as List?;
      if (notesList != null && notesList.isNotEmpty) {
        return notesList.last.toString();
      }
    }

    // Fallback: get the last AI response
    String? lastResponse;
    String lastTime = '';
    for (final raw in _hive.coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final aiResponse = interaction['ai_response'] as String?;
      final createdAt = interaction['created_at'] as String? ?? '';
      if (aiResponse != null &&
          aiResponse.isNotEmpty &&
          createdAt.compareTo(lastTime) > 0) {
        lastResponse = aiResponse;
        lastTime = createdAt;
      }
    }

    if (lastResponse != null && lastResponse.length > 120) {
      return '${lastResponse.substring(0, 120)}...';
    }
    return lastResponse ?? '';
  }

  /// Extracts coaching notes from today's conversations and persists them.
  /// Called during daily snapshot sync (11PM IST) or on app launch.
  Future<void> extractCoachingNotes() async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final todayMessages = <String>[];
    for (final raw in _hive.coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      if (!createdAt.startsWith(todayStr)) continue;

      final userMsg = interaction['user_message'] as String?;
      final aiResponse = interaction['ai_response'] as String?;
      if (userMsg != null && userMsg.isNotEmpty) {
        todayMessages.add('User: $userMsg');
      }
      if (aiResponse != null && aiResponse.isNotEmpty) {
        todayMessages.add('Coach: $aiResponse');
      }
    }

    if (todayMessages.isEmpty) return;

    // Extract key facts from conversations (local heuristic extraction)
    final facts = <String>[];
    for (final msg in todayMessages) {
      if (msg.startsWith('User:')) {
        final text = msg.substring(5).trim().toLowerCase();
        // Extract injury mentions
        if (text.contains('hurt') || text.contains('pain') || text.contains('injury') || text.contains('sore')) {
          facts.add('Mentioned discomfort: ${msg.substring(5).trim()}');
        }
        // Extract goal mentions
        if (text.contains('goal') || text.contains('want to') || text.contains('trying to')) {
          facts.add('Goal update: ${msg.substring(5).trim()}');
        }
        // Extract diet mentions
        if (text.contains('eat') || text.contains('diet') || text.contains('food') || text.contains('protein')) {
          facts.add('Diet note: ${msg.substring(5).trim()}');
        }
      }
    }

    if (facts.isEmpty) return;

    // Append to existing coaching notes
    final existing = _hive.coachBox.get('coaching_notes');
    final existingNotes = <String>[];
    if (existing is Map) {
      final notesList = existing['notes'] as List?;
      if (notesList != null) {
        existingNotes.addAll(notesList.cast<String>());
      }
    }

    // Keep last 20 notes max
    existingNotes.addAll(facts);
    if (existingNotes.length > 20) {
      existingNotes.removeRange(0, existingNotes.length - 20);
    }

    await _hive.coachBox.put('coaching_notes', {
      'notes': existingNotes,
      'last_extracted': now.toIso8601String(),
    });
    unawaited(SyncService.instance.pushSnapshot());
  }

  /// One-time migration: convert legacy coachBox['coaching_notes'] string
  /// list into coach_memory.coach_notes. Idempotent — no-op if coach_memory
  /// already exists in Hive.
  Future<void> backfillCoachMemoryIfNeeded() async {
    final coachBox = HiveService.instance.coachBox;
    if (CoachMemory.readFromBox(coachBox) != null) return;

    final userId = HiveService.instance.userBox.get('user_id') as String?;
    if (userId == null || userId.isEmpty) return;

    final legacy = coachBox.get('coaching_notes');
    String? merged;
    if (legacy is Map) {
      final notes = legacy['notes'];
      if (notes is List && notes.isNotEmpty) {
        merged = notes.map((n) => n.toString()).join('\n');
      }
    }

    final mem = CoachMemory(
      userId: userId,
      coachNotes: merged,
      lastExtractionAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await mem.writeToBox(coachBox);
    debugPrint('[AiCoachRepository] backfilled coach_memory from legacy coaching_notes');
  }

  /// Returns contextual quick prompts based on user's current state.
  List<String> getContextualPrompts() {
    final prompts = <String>[];
    final progress = UserRepository.instance.getProgress() ?? {};
    final todayNutrition = _getTodayNutrition();
    final thisWeekWorkouts = _getThisWeekWorkouts();

    // Check if user just logged a workout today
    final workoutsToday = (thisWeekWorkouts['completed_today'] as bool?) ?? false;
    if (workoutsToday) {
      prompts.add('How did my workout go?');
      prompts.add('What should I eat for recovery?');
    } else {
      prompts.add('What\'s my workout today?');
    }

    // Check nutrition state
    final caloriesLogged = (todayNutrition['calories_logged'] as num?) ?? 0;
    if (caloriesLogged == 0) {
      prompts.add('What should I eat today?');
    } else {
      prompts.add('Am I on track with macros?');
    }

    // Phase/goal based
    final phase = (progress['current_phase'] as int?) ?? 1;
    if (phase == 1) {
      prompts.add('Tips for beginners?');
    } else {
      prompts.add('Analyse my progress');
    }

    // Always add a general prompt
    if (prompts.length < 4) {
      prompts.add('Help me stay motivated');
    }

    return prompts.take(4).toList();
  }

  // ── Private helpers ──────────────────────────────────────────

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
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekStartStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
    final weekEndStr =
        '${weekEnd.year}-${weekEnd.month.toString().padLeft(2, '0')}-${weekEnd.day.toString().padLeft(2, '0')}';
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    int completed = 0;
    int planned = 0;
    bool completedToday = false;
    final exerciseNames = <String>[];

    for (final raw in workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      if (log['type'] == 'workout_log') {
        final date = log['date'] as String? ?? '';
        if (date.compareTo(weekStartStr) >= 0 && date.compareTo(weekEndStr) <= 0) {
          completed++;
          if (date == todayStr) completedToday = true;
        }
      }
      if (log['type'] == 'exercise_log') {
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

  /// Returns step counts for the last [days] days as a list of {date, steps}.
  List<Map<String, dynamic>> _getStepHistory({int days = 7}) {
    final healthBox = _hive.healthBox;
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < days; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      final dateStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Check proper step_log format (written by HealthSyncService)
    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'step_log' && log['date'] == todayStr) {
        return (log['steps'] as num?)?.toInt() ?? 0;
      }
    }

    // Fallback to legacy key format
    final stepsDate = healthBox.get('steps_date') as String?;
    if (stepsDate == todayStr) {
      return (healthBox.get('steps_today') as num?)?.toInt() ?? 0;
    }

    return 0;
  }

  Map<String, dynamic> _getTodayNutrition() {
    final nutritionBox = _hive.nutritionBox;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

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

    // Get water intake from healthBox
    // Writer (WaterIntakeNotifier) stores an int directly; handle both int and Map.
    final healthBox = _hive.healthBox;
    final waterData = healthBox.get('water_ml_$todayStr');
    final waterMl = (waterData is int)
        ? waterData
        : (waterData is Map)
            ? ((waterData['total_ml'] as num?)?.toInt() ?? 0)
            : 0;

    // Get urine colour from healthBox
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
      // Migration 034 (2026-04-24) — surface fiber in the AI snapshot so
      // Gemini can coach on the #1 Indian-audience macro gap.
      'fiber_g': fiber.round(),
      'fiber_target_g': 30,
      'water_ml': waterMl,
      'urine_status': ?urineStatus,
    };
  }

  /// Reads today's nlog_* rows from nutritionBox, groups by meal_type,
  /// and returns a list of {slot, items, total_kcal, total_protein_g}
  /// maps. Up to 4 slots (breakfast/lunch/dinner/snacks). Slot order
  /// follows insertion order — slots without rows are omitted entirely
  /// (rather than zero-filled) so the AI sees only meals the user
  /// actually logged.
  List<Map<String, dynamic>> _getMealsToday() {
    final nutritionBox = _hive.nutritionBox;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, "0")}-'
        '${now.day.toString().padLeft(2, "0")}';

    // Preserve canonical slot order: breakfast → lunch → dinner → snacks.
    const slotOrder = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final bySlot = <String, List<Map<String, dynamic>>>{};

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != todayStr) continue;
      // Only group rows with the standard nlog_* shape (skip saved-meal
      // template rows etc. — they don't carry meal_type at log time).
      final id = log['id'] as String? ?? '';
      if (!id.startsWith('nlog_')) continue;
      final mealType = (log['meal_type'] as String?)?.toLowerCase();
      if (mealType == null || mealType.isEmpty) continue;
      // Snap the various aliases the app uses to canonical slot keys.
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
    return 'snacks'; // unknown → bucket into snacks
  }

  /// Returns the last 7 days of daily totals, newest-first.
  /// Days without any nlog_* row are zero-filled so the model sees a
  /// stable 7-element timeline (and can detect the difference between
  /// "logged 0" and "didn't log").
  ///
  /// Refactored to single-pass O(N) bucketing (was O(7N) — 7 separate
  /// iterations over nutritionBox.values).
  List<Map<String, dynamic>> _getNutritionTrend7d() {
    final nutritionBox = _hive.nutritionBox;
    final now = DateTime.now();

    // Build the set of 7 date strings we care about so we can ignore
    // anything outside the window in O(1) per record.
    final windowDates = <String>[
      for (var i = 0; i < 7; i++)
        () {
          final d = now.subtract(Duration(days: i));
          return '${d.year}-${d.month.toString().padLeft(2, "0")}-'
              '${d.day.toString().padLeft(2, "0")}';
        }(),
    ];
    final windowSet = windowDates.toSet();

    // Single pass: bucket every nlog_* record by date.
    final byDate = <String, Map<String, int>>{};
    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final id = log['id'] as String? ?? '';
      if (!id.startsWith('nlog_')) continue;
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

    // Reconstruct the 7-element newest-first list, zero-filling gaps.
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

  /// Test-only seam exposing _getMealsToday for unit tests that don't
  /// want to construct the entire snapshot.
  @visibleForTesting
  List<Map<String, dynamic>> mealsTodayForTest() => _getMealsToday();

  /// Test-only seam exposing _getNutritionTrend7d.
  @visibleForTesting
  List<Map<String, dynamic>> nutritionTrend7dForTest() =>
      _getNutritionTrend7d();

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

    for (final raw in workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'exercise_log') continue;
      final name = log['exercise_name'] as String? ?? '';
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (name.isNotEmpty && weight > 0) {
        final best = prs[name] ?? 0;
        if (weight > best) prs[name] = weight;
      }
    }

    // Return top 5 PRs
    final sorted = prs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = <String, double>{};
    for (final entry in sorted.take(5)) {
      top[entry.key] = entry.value;
    }
    return top;
  }

  /// Runs PatternDetector and returns coach notices for AI injection.
  /// Only medium+ severity insights are included to keep context compact.
  List<String> _getCoachNotices() {
    try {
      final insights = PatternDetector.instance.analyze();
      return insights
          .where((i) => i.severity != InsightSeverity.low)
          .map((i) => i.coachNotice)
          .take(5) // max 5 to not bloat context
          .toList();
    } catch (e) {
      debugPrint('[AiCoachRepository._getCoachNotices] $e');
      return [];
    }
  }

  /// Returns true if the user hasn't sent a message today yet.
  /// Used to trigger proactive first-message-of-day AI greeting.
  bool isFirstMessageToday() {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastGreeting =
        _hive.configBox.get('last_ai_greeting_date') as String?;
    return lastGreeting != todayStr;
  }

  /// Marks that the AI has greeted the user today.
  Future<void> markGreetedToday() async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _hive.configBox.put('last_ai_greeting_date', todayStr);
  }

  /// Returns the top insight for the dashboard card (highest severity).
  CoachingInsight? getTopInsight() {
    try {
      final insights = PatternDetector.instance.analyze();
      return insights.isNotEmpty ? insights.first : null;
    } catch (e) {
      debugPrint('[AiCoachRepository.getTopInsight] $e');
      return null;
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

  /// Returns the coach_memory JSON snapshot for context injection, or
  /// null when private_mode is on / no memory exists.
  Map<String, dynamic>? _getCoachMemoryForContext() {
    try {
      final mem = CoachMemory.readFromBox(_hive.coachBox);
      if (mem == null || mem.privateMode) return null;
      return mem.toJson();
    } catch (e) {
      debugPrint('[AiCoachRepository] coach_memory read failed: $e');
      return null;
    }
  }

  /// Compact rank summary for AI context. Reads denormalized
  /// current_rank_code (no network round-trip).
  Map<String, dynamic> _getCurrentRankSnapshot() {
    try {
      final current = RankService.instance.getCurrentRank();
      return {
        'code': current.entry.code,
        'name': current.entry.displayName,
        'category': current.entry.category,
        'ordinal': current.entry.ordinal,
      };
    } catch (e) {
      debugPrint('[AiCoachRepository._getCurrentRankSnapshot] $e');
      return {'code': 'SD2', 'name': 'Seaman 2nd Class', 'ordinal': 0};
    }
  }

  /// Weeks/workouts until the user's next promotion. Returns null when
  /// already at Capt (terminal).
  Map<String, dynamic>? _getWeeksUntilNextRank() {
    try {
      final next = RankService.instance.getNextRank();
      if (next == null) return null;
      return {
        'next_code': next.entry.code,
        'next_name': next.entry.displayName,
        if (next.daysUntilEligible != null)
          'days_remaining': next.daysUntilEligible,
        if (next.workoutsRemaining != null)
          'workouts_remaining': next.workoutsRemaining,
      };
    } catch (e) {
      debugPrint('[AiCoachRepository._getWeeksUntilNextRank] $e');
      return null;
    }
  }

  /// Returns the rolling conversation summary from coachBox.
  /// Written by SyncService from the nightly rolling-context Edge Function.
  String _getFitnessSummary() {
    return _hive.coachBox.get('fitness_summary') as String? ?? '';
  }

  // ── Anti-fabrication grounding helpers (APK Test #4 / A3) ────────────────
  //
  // The Captain Manual §8 references these keys to refuse
  // history-beyond-window claims ("no data from last year — 8 days on
  // roster"). Without them the Manual's grounding rules have nothing to
  // check against and the model can drift back into fabrication.
  //
  // Cost: one O(n) scan of workoutBox + nutritionBox + healthBox.
  // Typical user has < 500 entries across all three. Negligible on-device.

  /// Computes `data_window_days`, `first_workout_date`, and
  /// `workout_logs_count` from workoutBox `wlog_*` rows.
  ///
  /// Returns `data_window_days: 0` and `first_workout_date: null` when
  /// there are no workout logs (fresh user / pre-onboarding state).
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
      // Keys exist but none had a parseable 'date' field — treat as 0.
      return {
        'data_window_days': 0,
        'first_workout_date': null,
        'workout_logs_count': wlogKeys.length,
      };
    }

    final daysSince = DateTime.now().difference(earliestDate).inDays;
    return {
      'data_window_days': daysSince,
      'first_workout_date': earliestDate.toIso8601String().substring(0, 10),
      'workout_logs_count': wlogKeys.length,
    };
  }

  /// Counts `nlog_*` rows in nutritionBox whose `date` field falls within
  /// the last 7 days. Rows outside the window or with unparseable dates
  /// are silently skipped.
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

  /// Counts `sleep_log_*` rows in healthBox whose `date` field falls within
  /// the last 7 days. Rows outside the window or with unparseable dates
  /// are silently skipped.
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

  // ---------------------------------------------------------------------------
  // APK Test #4 / A4 — Workout schedule snapshot helpers
  // ---------------------------------------------------------------------------

  /// Returns today's scheduled workout as {type, status, exercises[]} or null
  /// if no `schedule_<today>` key exists in workoutBox (pure rest day / no
  /// plan seeded yet).
  ///
  /// Falls back to `workout_name` when the `type` field is absent (some legacy
  /// schedule entries were written without an explicit `type` key).
  Map<String, dynamic>? _getTodayWorkout() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final schedule = _hive.workoutBox.get('schedule_$today');
    if (schedule is! Map) return null;
    return {
      'type': (schedule['type'] ?? schedule['workout_name'] ?? 'UNKNOWN') as String,
      'status': (schedule['status'] ?? 'pending') as String,
      'exercises': (schedule['exercises'] as List?) ?? const [],
    };
  }

  /// Returns yesterday's scheduled workout as {type, status} or null if no
  /// `schedule_<yesterday>` key exists. Omits the exercises list (yesterday's
  /// session contents are less useful than the status — completed/skipped).
  Map<String, dynamic>? _getYesterdayWorkout() {
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    final schedule = _hive.workoutBox.get('schedule_$yesterday');
    if (schedule is! Map) return null;
    return {
      'type': (schedule['type'] ?? schedule['workout_name'] ?? 'UNKNOWN') as String,
      'status': (schedule['status'] ?? 'unknown') as String,
    };
  }

  /// Returns the 7-day lookahead starting today (today + next 6 days).
  ///
  /// Each entry: {day: 'Mon', date: '2026-04-28', type: 'PUSH A', status: 'pending'}.
  /// Days without a `schedule_<date>` key are returned as REST entries
  /// ({type: 'REST', status: 'rest'}) — NOT null — so the coach always sees
  /// a complete 7-day picture without gaps.
  List<Map<String, dynamic>> _getWeekLookahead() {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      final dayName = dayNames[(date.weekday - 1) % 7];
      final schedule = _hive.workoutBox.get('schedule_$dateStr');
      if (schedule is Map) {
        results.add({
          'day': dayName,
          'date': dateStr,
          'type': (schedule['type'] ?? schedule['workout_name'] ?? 'UNKNOWN') as String,
          'status': (schedule['status'] ?? 'pending') as String,
        });
      } else {
        results.add({
          'day': dayName,
          'date': dateStr,
          'type': 'REST',
          'status': 'rest',
        });
      }
    }
    return results;
  }

  /// Returns a deduplicated view of all unique sessions scheduled in the
  /// next 7 days (today + 6), with each session's exercise list.
  ///
  /// Shape:
  /// ```
  /// {
  ///   'phase': int,
  ///   'week': int,
  ///   'days_per_week': int,
  ///   'weekly_sessions': [
  ///     {
  ///       'name': 'PUSH A',
  ///       'exercises': [
  ///         {'name': 'Bench Press', 'sets': 4, 'reps': '8-10', 'weight': 60},
  ///       ],
  ///     },
  ///   ],
  /// }
  /// ```
  ///
  /// Deduplication: uses session `type` (or `workout_name` fallback) as the
  /// key. The first occurrence wins; duplicates (e.g. PUSH A on Tue + Fri)
  /// are dropped so the coach sees one canonical PUSH A exercise list.
  ///
  /// REST days (no `schedule_<date>` key) are silently skipped.
  /// Exercise fields are projected to {name, sets, reps, weight} only —
  /// logging_type / rest_seconds / warmup_protocol don't belong in the
  /// ~200-600 byte summary.
  Map<String, dynamic> _getCurrentPlanSummary() {
    final progress = (_hive.userBox.get('progress') as Map?) ?? const {};
    final profile = (_hive.userBox.get('profile') as Map?) ?? const {};

    final phase = (progress['phase'] as int?) ?? 1;
    final week = (progress['week'] as int?) ?? 1;
    final daysPerWeek = (profile['days_per_week'] as int?) ?? 4;

    // Iterate today + 6 days, dedup by session name (first occurrence wins).
    final weeklySessionsMap = <String, Map<String, dynamic>>{};
    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
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

  // ---------------------------------------------------------------------------
  // APK Test #4 / A6 — Sleep, water, freezes, subscription, rank, cadence, ETA
  // ---------------------------------------------------------------------------

  /// Rank ladder matching Captain Manual §4 (10 rungs).
  /// Used for next_rank computation and ETA math — no network round-trip.
  static const _rankLadder = [
    {'code': 'SEAMAN_2', 'display': 'Seaman 2nd Class', 'requirements': <String, int>{}},
    {'code': 'SEAMAN_1', 'display': 'Seaman 1st Class', 'requirements': {'workouts': 7, 'weeks': 1}},
    {'code': 'LEADING_SEAMAN', 'display': 'Leading Seaman', 'requirements': {'workouts': 16, 'weeks': 4}},
    {'code': 'PETTY_OFFICER', 'display': 'Petty Officer', 'requirements': {'workouts': 60, 'weeks': 12}},
    {'code': 'CHIEF_PETTY_OFFICER', 'display': 'Chief Petty Officer', 'requirements': {'workouts': 100, 'weeks': 26}},
    {'code': 'MASTER_CHIEF', 'display': 'Master Chief Petty Officer', 'requirements': {'streak_weeks_unbroken': 52}},
    {'code': 'SUB_LIEUTENANT', 'display': 'Sub Lieutenant', 'requirements': {'workouts': 100}},
    {'code': 'LIEUTENANT_COMMANDER', 'display': 'Lieutenant Commander', 'requirements': {'workouts': 200}},
    {'code': 'COMMANDER', 'display': 'Commander', 'requirements': {'workouts': 300}},
    {'code': 'CAPTAIN', 'display': 'Captain', 'requirements': {'workouts': 500}},
  ];

  /// Returns sleep logs from the last 7 days as `{date, hours}` ascending.
  ///
  /// Keys read: `sleep_log_<YYYY-MM-DD>` in healthBox, written by
  /// `BiometricNotifier.logSleep` with `sleep_hours` field.
  /// Supports `hours` field as fallback for legacy entries.
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
      // Primary field is sleep_hours (BiometricNotifier); fall back to hours
      // for entries written by cloud-restore paths.
      final h = (log['sleep_hours'] as num?) ?? (log['hours'] as num?) ?? 0;
      results.add({'date': dateStr, 'hours': h.toDouble()});
    }
    results.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return results;
  }

  /// Returns water intake for the last 7 days as `{date, ml}` ascending.
  ///
  /// Keys read: `water_ml_<YYYY-MM-DD>` in healthBox, written by
  /// `WaterIntakeNotifier` as a plain int (ml). Falls back to Map shape
  /// (`total_ml` key) for legacy/restored entries.
  List<Map<String, dynamic>> _getWater7d() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final results = <Map<String, dynamic>>[];
    for (final key in _hive.healthBox.keys) {
      if (!key.toString().startsWith('water_ml_')) continue;
      // Extract the date portion from the key name (water_ml_YYYY-MM-DD)
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

  /// Reads streak freezes available (int) from userBox progress dict.
  int _getStreakFreezesAvailable() {
    final progress = _hive.userBox.get('progress') as Map?;
    return (progress?['streak_freezes_available'] as int?) ?? 0;
  }

  /// Reads the ISO date string of the last streak-freeze refill (or null).
  String? _getStreakFreezesRefillDate() {
    final progress = _hive.userBox.get('progress') as Map?;
    return progress?['streak_freezes_last_refill'] as String?;
  }

  /// Returns subscription state from configBox.
  ///
  /// `tier`: 'pro' | 'free'
  /// `expires_at`: ISO string or null
  /// `plan`: 'monthly' | 'yearly' | null
  /// `auto_renew`: bool (default false)
  Map<String, dynamic> _getSubscriptionState() {
    final config = _hive.configBox;
    final isPro = config.get('isPro') == true;
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

  /// Returns the user's current rank, defaulting to SEAMAN_2 for fresh users.
  ///
  /// Note: this is a SEPARATE helper from `_getCurrentRankSnapshot()` which
  /// delegates to `RankService`. This helper reads directly from profile and
  /// uses the local `_rankLadder` constant for display names — no RankService
  /// dependency so it's safe in unit tests without RankService init.
  Map<String, dynamic> _getCurrentRankFromLadder() {
    final profile = _hive.userBox.get('profile') as Map?;
    final code = (profile?['current_rank_code'] as String?) ?? 'SEAMAN_2';
    final entry = _rankLadder.firstWhere(
      (r) => r['code'] == code,
      orElse: () => _rankLadder.first,
    );
    final totalWorkouts = _hive.workoutBox.keys
        .where((k) => k.toString().startsWith('wlog_'))
        .length;
    final earnedAt = profile?['current_rank_earned_at'] as String?;
    return {
      'code': entry['code'] as String,
      'display': entry['display'] as String,
      'earned_at': earnedAt,
      'total_workouts': totalWorkouts,
    };
  }

  /// Returns the next rank entry from the ladder with `remaining` and
  /// `binding_constraint`, or null when the user is already at CAPTAIN.
  Map<String, dynamic>? _getNextRankFromLadder() {
    final profile = _hive.userBox.get('profile') as Map?;
    final currentCode = (profile?['current_rank_code'] as String?) ?? 'SEAMAN_2';
    final currentIdx = _rankLadder.indexWhere((r) => r['code'] == currentCode);
    if (currentIdx == -1 || currentIdx >= _rankLadder.length - 1) return null;

    final next = _rankLadder[currentIdx + 1];
    final reqs = next['requirements'] as Map<String, int>;

    final totalWorkouts = _hive.workoutBox.keys
        .where((k) => k.toString().startsWith('wlog_'))
        .length;
    final grounding = _computeDataWindowGrounding();
    final weeksElapsed = ((grounding['data_window_days'] as int) / 7).floor();

    final remaining = <String, int>{};
    String binding = 'workouts';
    int maxRemaining = -1;

    reqs.forEach((k, required) {
      int current = 0;
      if (k == 'workouts') current = totalWorkouts;
      else if (k == 'weeks') current = weeksElapsed;
      // streak_weeks_unbroken: TODO — use real streak in a future batch
      final rem = (required - current).clamp(0, required);
      remaining[k] = rem;
      if (rem > maxRemaining) {
        maxRemaining = rem;
        binding = k;
      }
    });

    return {
      'code': next['code'] as String,
      'display': next['display'] as String,
      'requirements': Map<String, dynamic>.from(reqs),
      'current_state': {
        'workouts': totalWorkouts,
        'weeks': weeksElapsed,
      },
      'remaining': remaining,
      'binding_constraint': binding,
    };
  }

  /// Counts workout logs (`wlog_*`) in the last 28 days and returns the
  /// average workouts per week (count / 4.0).
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

  /// Returns ETA to next promotion in days at two cadences:
  /// - `at_current_cadence`: based on actual workouts/week over last 28 days.
  ///   Returns `days: 999` when current cadence is 0 (never trains).
  /// - `at_plan_cadence`: based on `profile.days_per_week` target.
  ///
  /// Returns null when user is already at CAPTAIN (terminal rank) or
  /// when `next_rank` is null.
  Map<String, dynamic>? _getEtaNextPromotion() {
    final next = _getNextRankFromLadder();
    if (next == null) return null;

    final remaining = next['remaining'] as Map<String, int>;
    final remainingWorkouts = remaining['workouts'] ?? 0;

    if (remainingWorkouts == 0) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
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
        : 999; // sentinel for zero-cadence users
    final daysAtPlan = (remainingWorkouts * 7 / planCadence).ceil();

    return {
      'at_current_cadence': {
        'days': daysAtCurrent,
        'date': DateTime.now()
            .add(Duration(days: daysAtCurrent))
            .toIso8601String()
            .substring(0, 10),
      },
      'at_plan_cadence': {
        'days': daysAtPlan,
        'date': DateTime.now()
            .add(Duration(days: daysAtPlan))
            .toIso8601String()
            .substring(0, 10),
      },
    };
  }
}
