import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';

/// Seeds specific state into Hive boxes for integration test scenarios.
///
/// Call these helpers inside `setUp` or at the top of a test body to
/// put the app into a known state before exercising the UI.
class TestDataHelper {
  TestDataHelper._();

  // ── Subscription ────────────────────────────────────────────────

  static void setFreeUser() {
    HiveService.instance.configBox.put('is_pro', false);
    HiveService.instance.configBox.delete('subscription_expires_at');
    HiveService.instance.configBox.delete('subscription_plan');
  }

  static void setProUser() {
    final expiry = DateTime.now().add(const Duration(days: 30));
    HiveService.instance.configBox.put('is_pro', true);
    HiveService.instance.configBox
        .put('subscription_expires_at', expiry.toIso8601String());
    HiveService.instance.configBox.put('subscription_plan', 'pro_monthly');
  }

  // ── AI Trial ────────────────────────────────────────────────────

  /// Sets trial start to (freeAiTrialDays + 1) days ago → trial is expired.
  static void setTrialExpired() {
    final start = DateTime.now()
        .subtract(Duration(days: AppConstants.freeAiTrialDays + 1));
    HiveService.instance.configBox
        .put('ai_trial_start', start.toIso8601String());
  }

  /// Sets trial start to [daysUsed] days ago → trial is still active.
  static void setTrialActive({int daysUsed = 5}) {
    final start = DateTime.now().subtract(Duration(days: daysUsed));
    HiveService.instance.configBox
        .put('ai_trial_start', start.toIso8601String());
  }

  // ── AI Message Count ─────────────────────────────────────────────

  /// Injects exactly [AppConstants.freeAiMessagesPerDay] user messages
  /// into coachBox for today, so the next send attempt triggers the paywall.
  static void setMessageCountAtDailyLimit() {
    final today = DateTime.now();
    final coachBox = HiveService.instance.coachBox;
    for (int i = 0; i < AppConstants.freeAiMessagesPerDay; i++) {
      coachBox.put('msg_limit_test_$i', {
        'user_message': 'Limit test message $i',
        'ai_response': 'AI response $i',
        'created_at': today.toIso8601String(),
      });
    }
  }

  // ── User Profile ─────────────────────────────────────────────────

  static void setUserProfile({
    String name = 'QA Tester',
    double weight = 75.0,
    double height = 175.0,
    double targetWeight = 70.0,
    String goal = 'build_muscle',
    String experience = 'beginner',
    String equipment = 'basic_gym',
    int bmr = 1800,
    int tdee = 2200,
  }) {
    HiveService.instance.userBox.put('profile', {
      'full_name': name,
      'current_weight_kg': weight,
      'target_weight_kg': targetWeight,
      'height_cm': height,
      'primary_goal': goal,
      'gender': 'male',
      'date_of_birth': '1995-01-01',
      'fitness_experience': experience,
      'equipment_access': equipment,
      'activity_level': 'moderate',
      'diet_preference': 'vegetarian',
      'injuries': '',
      'bmr': bmr.toDouble(),
      'tdee': tdee.toDouble(),
    });
  }

  // ── Workout Progress ─────────────────────────────────────────────

  static void setWorkoutProgress({int phase = 1, int week = 1, int done = 0}) {
    HiveService.instance.userBox.put('progress', {
      'current_phase': phase,
      'current_week': week,
      'total_workouts_done': done,
      'current_streak_weeks': 0,
      'detected_experience_level': 'beginner',
    });
  }

  // ── Nutrition ────────────────────────────────────────────────────

  /// Logs a day's nutrition summary to nutritionBox (today by default).
  static void logTodayNutrition({
    double calories = 1500,
    double protein = 100,
    double carbs = 150,
    double fat = 50,
    DateTime? date,
  }) {
    final d = date ?? DateTime.now();
    final dateKey =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    HiveService.instance.nutritionBox.put('daily_$dateKey', {
      'date': dateKey,
      'total_calories': calories,
      'total_protein': protein,
      'total_carbs': carbs,
      'total_fat': fat,
      'meals': <Map<String, dynamic>>[],
    });
  }

  /// Logs a single meal item to nutritionBox.
  static void logMealItem({
    String foodName = 'Chicken Breast',
    double calories = 250,
    double protein = 40,
    double carbs = 0,
    double fat = 5,
    String mealType = 'lunch',
    DateTime? date,
  }) {
    final d = date ?? DateTime.now();
    final dateKey =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final key = 'meal_${d.millisecondsSinceEpoch}';
    HiveService.instance.nutritionBox.put(key, {
      'date': dateKey,
      'meal_type': mealType,
      'food_name': foodName,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'quantity_g': 100.0,
    });
  }

  // ── Weight ───────────────────────────────────────────────────────

  /// Logs weight entries for the last [count] days.
  static void logWeightHistory({int count = 7, double startKg = 75.0}) {
    final healthBox = HiveService.instance.healthBox;
    for (int i = 0; i < count; i++) {
      final d = DateTime.now().subtract(Duration(days: count - 1 - i));
      final dateKey =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      // Slight downward trend
      healthBox.put('weight_$dateKey', {
        'date': dateKey,
        'weight_kg': startKg - (i * 0.2),
        'notes': '',
      });
    }
  }

  // ── AI Coaching Notes ────────────────────────────────────────────

  /// Injects one AI interaction with a coaching note into coachBox.
  static void injectCoachingNote(String note) {
    final now = DateTime.now();
    HiveService.instance.coachBox.put('coaching_note_test', {
      'user_message': 'Test message',
      'ai_response': 'Response with note: $note',
      'created_at': now.toIso8601String(),
      'coaching_note': note,
    });
  }

  // ── Streak ───────────────────────────────────────────────────────

  static void setStreak(int weeks) {
    HiveService.instance.userBox.put('progress', {
      ...?(HiveService.instance.userBox.get('progress') as Map?)
          ?.cast<String, dynamic>(),
      'current_streak_weeks': weeks,
    });
  }

  // ── Workout Log ──────────────────────────────────────────────────

  /// Logs a completed workout to workoutBox (for streak + calendar tests).
  static void logCompletedWorkout({DateTime? date, String exerciseName = 'Bench Press'}) {
    final d = date ?? DateTime.now();
    final dateKey =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final key = 'workout_${d.millisecondsSinceEpoch}';
    HiveService.instance.workoutBox.put(key, {
      'date': dateKey,
      'exercise_name': exerciseName,
      'sets_completed': 3,
      'reps_completed': 10,
      'weight_kg': 60.0,
      'logged_at': d.toIso8601String(),
      'is_pr': false,
    });
  }

  // ── Water ────────────────────────────────────────────────────────

  static void setTodayWater(int ml) {
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    HiveService.instance.healthBox.put('water_$dateKey', {
      'date': dateKey,
      'amount_ml': ml,
    });
  }

  // ── Streak Freeze ────────────────────────────────────────────────

  /// Sets streak freeze availability for testing.
  static void setStreakFreezes({
    int available = 1,
    List<String> usedDates = const [],
    String? lastRefill,
  }) {
    final progress =
        (HiveService.instance.userBox.get('progress') as Map?)?.cast<String, dynamic>() ?? {};
    HiveService.instance.userBox.put('progress', {
      ...progress,
      'streak_freezes_available': available,
      'streak_freeze_used_dates': usedDates,
      'streak_freezes_last_refill': lastRefill ?? DateTime.now().toIso8601String().substring(0, 10),
    });
  }

  /// Simulates a "streak freeze just used" flag for toast testing.
  static void setStreakFreezeJustUsed({int remaining = 0}) {
    final progress =
        (HiveService.instance.userBox.get('progress') as Map?)?.cast<String, dynamic>() ?? {};
    HiveService.instance.userBox.put('progress', {
      ...progress,
      'streak_freeze_just_used': true,
      'streak_freeze_remaining_after_use': remaining,
    });
  }

  // ── Hive scan-meal counter ───────────────────────────────────────

  static void setScanMealCountAtMonthlyLimit() {
    final now = DateTime.now();
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    HiveService.instance.configBox
        .put('scan_meal_month_$monthKey', AppConstants.freeScanMealPerMonth);
  }
}
