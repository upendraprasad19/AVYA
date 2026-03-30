import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';

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
      },
      'progress': {
        'current_phase': progress['current_phase'] ?? 1,
        'current_week': progress['current_week'] ?? 1,
        'total_workouts_done': progress['total_workouts_done'] ?? 0,
        'current_streak_weeks': progress['current_streak_weeks'] ?? 0,
        'detected_experience': progress['detected_experience_level'] ??
            UserRepository.instance.detectedExperience ?? 'beginner',
      },
      'this_week_workouts': _getThisWeekWorkouts(),
      'today_nutrition': _getTodayNutrition(),
      'latest_weight': _getLatestWeight(),
      'personal_records': _getPersonalRecords(),
      'coaching_notes': _getCoachingNotes(),
      'motivational_style': preferences['motivational_style'] ?? 'encouraging',
      'coach_notices': _getCoachNotices(),
    };
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
        } catch (_) {}
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
        } catch (_) {}
      }

      // Weight trend query
      if (_containsAny(lower, ['weight', 'scale', 'kg', 'lost', 'gained']) &&
          _isHistoricalQuery(lower)) {
        try {
          final weights = NutritionRepository.instance.getWeightHistory(days: 90);
          if (weights.isNotEmpty) {
            context['weight_trend'] = weights;
          }
        } catch (_) {}
      }

      // Progress / "how am I doing" query
      if (_containsAny(lower,
          ['progress', 'how am i', 'improvement', 'transformation', 'results'])) {
        try {
          context['workout_adherence'] =
              WorkoutRepository.instance.getWorkoutAdherence(days: 90);
        } catch (_) {}
        try {
          context['nutrition_trend'] =
              NutritionRepository.instance.getWeeklyAverages(weeks: 12);
        } catch (_) {}
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
      } catch (_) {}
    } catch (_) {
      // Enrichment is best-effort — never fail the AI call
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
    final weekStartStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
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
        if (date.compareTo(weekStartStr) >= 0) {
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
      if (log['type'] == 'scheduled') {
        final date = log['date'] as String? ?? '';
        if (date.compareTo(weekStartStr) >= 0) {
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

  Map<String, dynamic> _getTodayNutrition() {
    final nutritionBox = _hive.nutritionBox;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    double calories = 0, protein = 0, carbs = 0, fat = 0;

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String? ?? '';
      if (date == todayStr) {
        calories += (log['total_calories'] as num?)?.toDouble() ?? 0;
        protein += (log['total_protein'] as num?)?.toDouble() ?? 0;
        carbs += (log['total_carbs'] as num?)?.toDouble() ?? 0;
        fat += (log['total_fat'] as num?)?.toDouble() ?? 0;
      }
    }

    // Get water intake from healthBox
    final healthBox = _hive.healthBox;
    final waterData = healthBox.get('water_$todayStr');
    final waterMl = (waterData is Map)
        ? ((waterData['total_ml'] as num?)?.toInt() ?? 0)
        : 0;

    return {
      'calories_logged': calories.round(),
      'protein_g': protein.round(),
      'carbs_g': carbs.round(),
      'fat_g': fat.round(),
      'water_ml': waterMl,
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
    } catch (_) {
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
    } catch (_) {
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
}
