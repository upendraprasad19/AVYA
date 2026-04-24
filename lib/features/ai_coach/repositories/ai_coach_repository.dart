import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
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

    return {
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

  /// Returns the rolling conversation summary from coachBox.
  /// Written by SyncService from the nightly rolling-context Edge Function.
  String _getFitnessSummary() {
    return _hive.coachBox.get('fitness_summary') as String? ?? '';
  }
}
