import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';

// ── Onboarding Step Definitions ──────────────────────────────────

class OnboardingStep {
  final String key;
  final String question;
  final OnboardingInputType inputType;
  final List<String>? options;

  const OnboardingStep({
    required this.key,
    required this.question,
    required this.inputType,
    this.options,
  });
}

enum OnboardingInputType {
  text,
  datePicker,
  chips,
  number,
  selector,
}

const List<OnboardingStep> onboardingSteps = [
  OnboardingStep(
    key: 'full_name',
    question: "Hey there! I'm your AI fitness coach. What's your name?",
    inputType: OnboardingInputType.text,
  ),
  OnboardingStep(
    key: 'date_of_birth',
    question: "Nice to meet you! When's your birthday?",
    inputType: OnboardingInputType.datePicker,
  ),
  OnboardingStep(
    key: 'gender',
    question:
        "What's your gender? This helps me calculate your nutrition targets accurately.",
    inputType: OnboardingInputType.chips,
    options: ['male', 'female', 'other'],
  ),
  OnboardingStep(
    key: 'height_cm',
    question: "How tall are you? (in cm)",
    inputType: OnboardingInputType.number,
  ),
  OnboardingStep(
    key: 'current_weight_kg',
    question: "What's your current weight? (in kg)",
    inputType: OnboardingInputType.number,
  ),
  OnboardingStep(
    key: 'target_weight_kg',
    question: "What's your target weight? (in kg)",
    inputType: OnboardingInputType.number,
  ),
  OnboardingStep(
    key: 'primary_goal',
    question: "What's your primary fitness goal?",
    inputType: OnboardingInputType.chips,
    options: ['build_muscle', 'lose_fat', 'general_fitness', 'strength'],
  ),
  // Bug #24 — pace picker immediately after primary_goal so "what + how fast"
  // are grouped as one decision. Default 'balanced' if user skips forward.
  OnboardingStep(
    key: 'pace_preference',
    question:
        "How fast do you want to get there? Slow is easiest to stick with. Balanced is the evidence-based standard. Aggressive pushes near the upper safe limit.",
    inputType: OnboardingInputType.chips,
    options: ['slow', 'balanced', 'aggressive'],
  ),
  OnboardingStep(
    key: 'fitness_experience',
    question: "How would you describe your fitness experience?",
    inputType: OnboardingInputType.chips,
    options: ['beginner', 'intermediate', 'advanced'],
  ),
  OnboardingStep(
    key: 'days_per_week',
    question: "How many days per week can you train?",
    inputType: OnboardingInputType.selector,
    options: ['3', '4', '5', '6'],
  ),
  OnboardingStep(
    key: 'lifestyle_activity',
    question:
        'Outside the gym, how active is your daily life? This helps me calculate your calories accurately.',
    inputType: OnboardingInputType.chips,
    options: ['desk_job', 'lightly_active', 'very_active_job'],
  ),
  OnboardingStep(
    key: 'equipment_access',
    question: "What equipment do you have access to?",
    inputType: OnboardingInputType.chips,
    options: ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'],
  ),
  OnboardingStep(
    key: 'start_date',
    question: "When do you want to start your first workout?",
    inputType: OnboardingInputType.chips,
    options: ['start_today', 'this_monday', 'next_monday'],
  ),
];

// ── Onboarding State ─────────────────────────────────────────────

class OnboardingState {
  final int currentStep;
  final Map<String, dynamic> answers;
  final bool isCompleting;
  final String? error;
  final NutritionTargets? lastComputedTargets;

  const OnboardingState({
    this.currentStep = 0,
    this.answers = const {},
    this.isCompleting = false,
    this.error,
    this.lastComputedTargets,
  });

  int get totalSteps => onboardingSteps.length;

  double get progress =>
      totalSteps > 0 ? (currentStep + 1) / totalSteps : 0;

  OnboardingStep get currentStepData => onboardingSteps[currentStep];

  bool get isFirstStep => currentStep == 0;
  bool get isLastStep => currentStep == totalSteps - 1;

  bool get currentStepAnswered {
    final key = currentStepData.key;
    final value = answers[key];
    if (value == null) return false;
    if (value is String && value.trim().isEmpty) return false;
    return true;
  }

  OnboardingState copyWith({
    int? currentStep,
    Map<String, dynamic>? answers,
    bool? isCompleting,
    String? error,
    NutritionTargets? lastComputedTargets,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      answers: answers ?? this.answers,
      isCompleting: isCompleting ?? this.isCompleting,
      error: error,
      lastComputedTargets: lastComputedTargets ?? this.lastComputedTargets,
    );
  }
}

// ── Onboarding Notifier ──────────────────────────────────────────

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  UserRepository get _userRepo => UserRepository.instance;
  HiveService get _hive => HiveService.instance;

  void setAnswer(String key, dynamic value) {
    final updated = Map<String, dynamic>.from(state.answers);
    updated[key] = value;
    state = state.copyWith(answers: updated);
  }

  void nextStep() {
    // Validate numeric biometric fields before advancing.
    final key = state.currentStepData.key;
    final raw = state.answers[key];
    final num? value = raw is num ? raw : (raw is String ? num.tryParse(raw) : null);

    if (key == 'height_cm' && value != null) {
      if (value < 100 || value > 250) {
        state = state.copyWith(
          error: 'Height must be between 100 and 250 cm. Please re-enter.',
        );
        return;
      }
    } else if (key == 'current_weight_kg' && value != null) {
      if (value < 20 || value > 300) {
        state = state.copyWith(
          error: 'Current weight must be between 20 and 300 kg. Please re-enter.',
        );
        return;
      }
    } else if (key == 'target_weight_kg' && value != null) {
      if (value < 20 || value > 300) {
        state = state.copyWith(
          error: 'Target weight must be between 20 and 300 kg. Please re-enter.',
        );
        return;
      }
    }

    if (state.currentStep < state.totalSteps - 1) {
      state = state.copyWith(currentStep: state.currentStep + 1, error: null);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  void goToStep(int step) {
    if (step >= 0 && step < state.totalSteps) {
      state = state.copyWith(currentStep: step);
    }
  }

  /// Resolves the start date from the user's selection.
  DateTime resolveStartDate() {
    final choice = state.answers['start_date'] as String? ?? 'this_monday';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (choice) {
      case 'start_today':
        return today;
      case 'next_monday':
        final daysUntilNextMonday = (8 - now.weekday) % 7;
        return today.add(Duration(days: daysUntilNextMonday == 0 ? 7 : daysUntilNextMonday));
      case 'this_monday':
      default:
        // Return THIS week's Monday (today or most recent Monday).
        // This ensures the plan covers the current week so the calendar
        // shows workout/rest status for this week immediately.
        final daysSinceMonday = now.weekday - 1; // Mon=0, Tue=1, ..., Sun=6
        return today.subtract(Duration(days: daysSinceMonday));
    }
  }

  /// Saves profile, generates plan, schedules workouts to calendar dates.
  ///
  /// Returns the generated [Phase] for the animation screen to display,
  /// or null on failure.
  Future<Phase?> completeOnboarding() async {
    state = state.copyWith(isCompleting: true, error: null);

    try {
      final a = state.answers;

      final fullName = a['full_name'] as String? ?? '';
      final dobString = a['date_of_birth'] as String? ?? '';
      final gender = a['gender'] as String? ?? 'male';
      final heightCm = _parseDouble(a['height_cm']);
      final currentWeightKg = _parseDouble(a['current_weight_kg']);
      final targetWeightKg = _parseDouble(a['target_weight_kg']);
      final primaryGoal = a['primary_goal'] as String? ?? 'general_fitness';
      final fitnessExperience =
          a['fitness_experience'] as String? ?? 'beginner';
      final daysPerWeek = _parseInt(a['days_per_week'], fallback: 4);
      final equipmentAccess =
          a['equipment_access'] as String? ?? 'bodyweight';

      final dob = DateTime.tryParse(dobString);
      int age = 25;
      if (dob != null) {
        final now = DateTime.now();
        age = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          age--;
        }
      }

      final lifestyleActivity =
          a['lifestyle_activity'] as String? ?? 'desk_job';
      final activityLevel =
          BmrCalculator.resolveActivityLevel(lifestyleActivity, daysPerWeek);

      final targets = BmrCalculator.calculateTargets(
        weightKg: currentWeightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
        activityLevel: activityLevel,
        goal: primaryGoal,
        pacePreference: (a['pace_preference'] as String?) ?? 'balanced',
        targetWeightKg: targetWeightKg > 0 ? targetWeightKg : null,
      );

      final profile = {
        'full_name': fullName,
        'date_of_birth': dobString,
        'gender': gender,
        'height_cm': heightCm,
        'current_weight_kg': currentWeightKg,
        'target_weight_kg': targetWeightKg,
        'primary_goal': primaryGoal,
        'pace_preference': (a['pace_preference'] as String?) ?? 'balanced', // Bug #24
        'fitness_experience': fitnessExperience,
        'days_per_week': daysPerWeek,
        'equipment_access': equipmentAccess,
        'lifestyle_activity': lifestyleActivity,
        'activity_level': activityLevel,
        'bmr': targets.bmr,
        'tdee': targets.tdee,
        'daily_calories': targets.dailyCalories,
        'protein_grams': targets.proteinGrams,
        'carb_grams': targets.carbGrams,
        'fat_grams': targets.fatGrams,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Use saveProfile (not updateProfileFields) to guarantee a clean
      // slate. updateProfileFields merges onto existing data, which would
      // carry over avatar_url / banner_url from a previously logged-in account.
      await _userRepo.saveProfile(profile);

      // Ensure exercise data is seeded before plan generation.
      // Without exercises, PlanGenerator produces 0-exercise (all-rest) workouts.
      final exerciseBox = _hive.exerciseBox;
      if (exerciseBox.isEmpty) {
        await SeedService.instance.seedIfNeeded();
      }

      // Generate plan AND schedule to calendar dates via WorkoutScheduleService
      final startDate = resolveStartDate();
      final phase = await WorkoutScheduleService.instance.generateAndSchedule(
        goal: primaryGoal,
        equipment: equipmentAccess,
        daysPerWeek: daysPerWeek,
        startDate: startDate,
        experienceLevel: fitnessExperience,
        phase: 1,
      );

      // Guard: if the plan generated with zero workout days, the exercise
      // library either failed to seed or no exercises matched the filters.
      if (phase.workouts.isEmpty) {
        throw Exception(
          'No exercises found for your equipment. Please try a different equipment option.',
        );
      }

      await _userRepo.saveProgress({
        'current_phase': 1,
        'current_week': 1,
        'total_workouts_done': 0,
        'current_streak_weeks': 0,
        'phase_started_at': startDate.toIso8601String(),
        'plan_generated_at': DateTime.now().toIso8601String(),
      });

      await _userRepo.setOnboarded();

      // Note: ai_trial_start is set lazily by ai_coach_provider on first
      // chat message, and server sets users.ai_chat_started_at on first
      // Edge Function call. No need to write a local key here.
      // The dead 'ai_chat_started_at' local key was removed — nothing reads it.

      // Sync onboarding flag + profile to Supabase.
      // Awaited so failures are caught and logged — non-fatal: Hive is already
      // saved and SyncService will retry on next launch if offline.
      try {
        await _syncOnboardingToSupabase(profile);
      } catch (syncErr) {
        // Visible in debug console for testing; not shown to the user.
        debugPrint('[Onboarding] Supabase sync failed: $syncErr — scheduling retry');
        // Retry once after 10s — JWT may need refresh after sign-up flow.
        Future.delayed(const Duration(seconds: 10), () async {
          try {
            await SupabaseService.instance.client.auth.refreshSession();
            await _syncOnboardingToSupabase(profile);
            debugPrint('[Onboarding] Retry succeeded');
          } catch (e) {
            debugPrint('[Onboarding] Retry also failed: $e — will sync on next daily sync');
          }
        });
      }

      // Fire-and-forget: generate AI prediction card in background.
      // Non-blocking — user proceeds to home screen immediately.
      _generatePrediction(profile);

      state = state.copyWith(isCompleting: false, lastComputedTargets: targets);
      return phase;
    } on FormatException catch (e) {
      state = state.copyWith(
        isCompleting: false,
        error: 'Invalid data format: ${e.message}. Please check your inputs.',
      );
      return null;
    } on RangeError catch (_) {
      state = state.copyWith(
        isCompleting: false,
        error: 'A value was out of range. Please check your height, weight, and age.',
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isCompleting: false,
        error: 'Something went wrong: ${e.runtimeType}. Please try again.',
      );
      return null;
    }
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Generates an AI fitness prediction card and saves it to Hive configBox.
  ///
  /// Called fire-and-forget after onboarding — does NOT block the user.
  /// Uses ai-proxy Edge Function (free tier) since this runs for all users.
  /// On failure, the prediction card simply shows an empty state.
  void _generatePrediction(Map<String, dynamic> profile) async {
    try {
      final dob = profile['date_of_birth'] as String? ?? '';
      int age = 25;
      final dobDate = DateTime.tryParse(dob);
      if (dobDate != null) {
        final now = DateTime.now();
        age = now.year - dobDate.year;
        if (now.month < dobDate.month ||
            (now.month == dobDate.month && now.day < dobDate.day)) {
          age--;
        }
      }

      final predictionPrompt = '''Predict realistic fitness outcomes at 3, 6, and 12 months.

Profile: ${profile['gender']}, age $age, ${profile['height_cm']}cm, ${profile['current_weight_kg']}kg → ${profile['target_weight_kg']}kg goal
Goal: ${profile['primary_goal']}, Experience: ${profile['fitness_experience']}
Training: ${profile['days_per_week']} days/week, ${profile['equipment_access']}
BMR: ${profile['bmr']?.toStringAsFixed(0)}, TDEE: ${profile['tdee']?.toStringAsFixed(0)}

Reply in bullet points ONLY — no paragraphs. Max 80 words. Format:
• Weight: 74kg → 71kg (3mo) → 69kg (6mo) → 67kg (12mo)
• Body fat: ~22% → ~18%
• Bench: 40kg → 60kg, Squat: 50kg → 80kg
• One motivational line''';

      final context = {
        'system_prompt':
            'You are a sports science expert making evidence-based fitness predictions. Be specific with numbers but realistic.',
      };

      // Use predict() — bypasses daily limit check and interaction logging.
      // Predictions are a FREE feature, separate from the AI Coach quota.
      final response = await AiService.instance.predict(predictionPrompt, context);
      final reply = response.reply;

      if (reply.isNotEmpty) {
        final configBox = HiveService.instance.configBox;
        await configBox.put('prediction_text', reply);
        await configBox.put('prediction_date', DateTime.now().toIso8601String());
        await configBox.put(
            'prediction_generated_at', DateTime.now().toIso8601String());
        debugPrint('[Onboarding] Prediction card generated successfully');
      }
    } catch (e) {
      // Non-fatal — prediction card will show empty state.
      debugPrint('[Onboarding] Prediction generation failed: $e');
    }
  }

  /// Syncs onboarding completion flag + profile to Supabase via UserRepository.
  ///
  /// Only sends columns that exist in the Supabase tables — the local profile
  /// map contains computed fields (daily_calories, protein_grams, etc.) that
  /// are stored in Hive but do NOT have corresponding Postgres columns.
  ///
  /// Throws on failure so the caller can detect sync gaps.
  Future<void> _syncOnboardingToSupabase(Map<String, dynamic> profile) async {
    final supabase = SupabaseService.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await UserRepository.syncOnboardingToSupabase(
      userId: userId,
      userData: {
        'email': supabase.auth.currentUser?.email,
        'full_name': profile['full_name'],
        'onboarding_completed': true,
        'last_active_at': DateTime.now().toIso8601String(),
      },
      profileData: {
        'date_of_birth': profile['date_of_birth'],
        'gender': profile['gender'],
        'height_cm': profile['height_cm'],
        'current_weight_kg': profile['current_weight_kg'],
        'target_weight_kg': profile['target_weight_kg'],
        'primary_goal': profile['primary_goal'],
        'fitness_experience': profile['fitness_experience'],
        'days_per_week': profile['days_per_week'],
        'equipment_access': profile['equipment_access'],
        'activity_level': profile['activity_level'],
        'bmr': profile['bmr'],
        'tdee': profile['tdee'],
      },
      progressData: {
        'current_phase': 1,
        'current_week': 1,
        'total_workouts_done': 0,
        'current_streak_weeks': 0,
        'phase_started_at': DateTime.now().toIso8601String(),
        'plan_generated_at': DateTime.now().toIso8601String(),
      },
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
        OnboardingNotifier.new);
