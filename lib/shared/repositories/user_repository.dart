import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

/// User CRUD operations via Hive userBox (offline-first).
///
/// All reads/writes go to Hive. Supabase sync is handled separately
/// by [SyncService].
class UserRepository {
  UserRepository._();
  static final UserRepository _instance = UserRepository._();
  static UserRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

  // ── Profile ─────────────────────────────────────────────────

  /// Returns the user profile map, or null if not yet created.
  Map<String, dynamic>? getProfile() {
    final raw = _hive.userBox.get('profile');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Saves/updates the user profile.
  Future<void> saveProfile(Map<String, dynamic> profile) async {
    await _hive.userBox.put('profile', profile);
  }

  /// Updates individual profile fields without overwriting others.
  Future<void> updateProfileFields(Map<String, dynamic> fields) async {
    final current = getProfile() ?? {};
    current.addAll(fields);
    await saveProfile(current);
  }

  // ── Progress ────────────────────────────────────────────────

  /// Returns the user progress map (phase, week, streak, etc.).
  Map<String, dynamic>? getProgress() {
    final raw = _hive.userBox.get('progress');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Saves/replaces the user progress map.
  Future<void> saveProgress(Map<String, dynamic> progress) async {
    await _hive.userBox.put('progress', progress);
  }

  /// Updates individual progress fields without overwriting others.
  Future<void> updateProgress(Map<String, dynamic> fields) async {
    final current = getProgress() ?? {
      'current_phase': 1,
      'current_week': 1,
      'total_workouts_done': 0,
      'current_streak_weeks': 0,
    };
    current.addAll(fields);
    await saveProgress(current);
  }

  // ── Preferences ─────────────────────────────────────────────

  /// Returns the user preferences map.
  Map<String, dynamic>? getPreferences() {
    final raw = _hive.userBox.get('preferences');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Saves/replaces the user preferences.
  Future<void> savePreferences(Map<String, dynamic> preferences) async {
    await _hive.userBox.put('preferences', preferences);
  }

  // ── Onboarding ──────────────────────────────────────────────

  /// Whether the user has completed onboarding.
  bool get isOnboarded {
    return _hive.configBox.get('onboarding_completed', defaultValue: false)
        as bool;
  }

  /// Marks onboarding as complete.
  Future<void> setOnboarded() async {
    await _hive.configBox.put('onboarding_completed', true);
  }

  // ── Detected Experience ─────────────────────────────────────

  /// Returns the AI-detected experience level, or null.
  String? get detectedExperience {
    return _hive.userBox.get('detected_experience') as String?;
  }

  /// Saves the detected experience level.
  Future<void> setDetectedExperience(String level) async {
    await _hive.userBox.put('detected_experience', level);
  }

  // ── Units ─────────────────────────────────────────────────────

  /// Whether the user prefers metric units (default: true).
  bool getUnitsMetric() {
    return (_hive.configBox.get('units_metric', defaultValue: true) as bool?) ??
        true;
  }

  /// Saves the user's unit preference.
  Future<void> setUnitsMetric(bool metric) async {
    await _hive.configBox.put('units_metric', metric);
  }

  // ── Computed Targets ─────────────────────────────────────────

  /// Ensures computed nutrition fields (daily_calories, protein_grams, etc.)
  /// exist in the profile. If missing but BMR/TDEE inputs are available,
  /// recalculates them using BmrCalculator.
  Future<void> ensureComputedTargets() async {
    final profile = getProfile();
    if (profile == null) return;

    // Already has computed targets — nothing to do.
    if (profile['daily_calories'] != null &&
        profile['protein_grams'] != null &&
        profile['carb_grams'] != null &&
        profile['fat_grams'] != null) {
      return;
    }

    // Need enough data to recalculate.
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final gender = profile['gender'] as String?;
    final goal = profile['primary_goal'] as String? ?? 'general_fitness';
    final activityLevel = profile['activity_level'] as String? ?? 'moderate';
    final dob = profile['date_of_birth'] as String?;

    if (weightKg == null ||
        weightKg <= 0 ||
        heightCm == null ||
        heightCm <= 0 ||
        gender == null) {
      return;
    }

    int age = 25; // fallback
    if (dob != null) {
      final birthDate = DateTime.tryParse(dob);
      if (birthDate != null) {
        final now = DateTime.now();
        age = now.year - birthDate.year;
        if (now.month < birthDate.month ||
            (now.month == birthDate.month && now.day < birthDate.day)) {
          age--;
        }
        if (age <= 0) age = 25;
      }
    }

    final targets = BmrCalculator.calculateTargets(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
      activityLevel: activityLevel,
      goal: goal,
    );

    await updateProfileFields(targets.toMap());
  }

  // ── Diet Plan ─────────────────────────────────────────────────

  /// Saves a generated diet plan to configBox.
  Future<void> saveDietPlan(Map<String, dynamic> planData) async {
    await _hive.configBox.put('saved_diet_plan', planData);
  }

  // ── Clear All Data (Logout) ───────────────────────────────────

  /// Clears all user-specific Hive boxes (keeps exerciseBox and foodBox).
  ///
  /// Used during sign-out to wipe local user data while preserving
  /// seeded reference data that doesn't need to be re-downloaded.
  Future<void> clearAllData() async {
    await _hive.userBox.clear();
    await _hive.workoutBox.clear();
    await _hive.nutritionBox.clear();
    await _hive.healthBox.clear();
    await _hive.coachBox.clear();
    await _hive.syncBox.clear();
    await _hive.configBox.clear();
    await _hive.customBox.clear();
    // Keep exerciseBox and foodBox (seeded data, no need to re-download)
  }
}
