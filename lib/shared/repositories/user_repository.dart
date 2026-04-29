import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

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

    final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();
    final targets = BmrCalculator.calculateTargets(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
      activityLevel: activityLevel,
      goal: goal,
      pacePreference: profile['pace_preference'] as String? ?? 'balanced',
      targetWeightKg: (profile['target_weight_kg'] as num?)?.toDouble(),
      bodyFatPercent: bodyFat,
    );

    await updateProfileFields(targets.toMap());
  }

  // ── Diet Plan ─────────────────────────────────────────────────

  /// Saves a generated diet plan to configBox.
  Future<void> saveDietPlan(Map<String, dynamic> planData) async {
    await _hive.configBox.put('saved_diet_plan', planData);
  }

  /// Returns the saved diet plan, or null if none exists.
  Map<String, dynamic>? getSavedDietPlan() {
    final raw = _hive.configBox.get('saved_diet_plan');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
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
    await _hive.notificationsBox.clear();
    // Keep exerciseBox and foodBox (seeded data, no need to re-downloaded)
  }

  // ── Supabase Sync (background, fire-and-forget) ──────────────────

  /// Uploads an image to Supabase Storage and returns the public URL.
  ///
  /// [bucket] — Storage bucket name (e.g. 'avatars', 'banners').
  /// [filePath] — Path within the bucket (e.g. '$userId/avatar.jpg').
  /// [bytes] — Raw image bytes to upload.
  ///
  /// Throws on failure so the caller can handle errors.
  static Future<String> uploadImage({
    required String bucket,
    required String filePath,
    required Uint8List bytes,
  }) async {
    await SupabaseService.instance.client.storage
        .from(bucket)
        .uploadBinary(filePath, bytes, fileOptions: const FileOptions(upsert: true));

    final publicUrl = SupabaseService.instance.client.storage
        .from(bucket)
        .getPublicUrl(filePath);

    return publicUrl;
  }

  /// Updates specific fields in the Supabase `user_profile` table.
  ///
  /// Fire-and-forget: catches all errors and logs them via debugPrint.
  static Future<void> updateSupabaseProfileField({
    required String userId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      await SupabaseService.instance.client.from('user_profile').upsert(
        {'user_id': userId, ...fields},
        onConflict: 'user_id',
      );
    } catch (e) {
      debugPrint('[UserRepository] updateSupabaseProfileField failed: $e');
    }
  }

  /// Syncs onboarding data to Supabase: users, user_profile, and user_progress.
  ///
  /// Only sends columns that exist in the Supabase tables — the local profile
  /// map contains computed fields (daily_calories, protein_grams, etc.) that
  /// are stored in Hive but do NOT have corresponding Postgres columns.
  ///
  /// Throws on failure so the caller can detect sync gaps.
  static Future<void> syncOnboardingToSupabase({
    required String userId,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> profileData,
    required Map<String, dynamic> progressData,
  }) async {
    final supabase = SupabaseService.instance.client;

    await supabase.from('users').upsert({
      'id': userId,
      ..._sanitize(userData),
    });

    // CRITICAL — both `user_profile` and `user_progress` have `id uuid` as
    // primary key and a separate UNIQUE constraint on `user_id`. Supabase
    // Dart's `.upsert()` defaults to conflict-on-primary-key, so without
    // `onConflict: 'user_id'` the client generates a fresh `id` each call,
    // tries to INSERT, and trips the UNIQUE(user_id) constraint → 23505
    // throws. When that exception fires on user_profile the subsequent
    // user_progress upsert never executes — which is exactly how we ended
    // up with `users.onboarding_completed = true` but an all-null
    // user_profile row and zero rows in user_progress after a fresh
    // sign-up test on 2026-04-17.
    //
    // Second bug fixed in the same 2026-04-17 pass: the caller hands us a
    // profileData map that can contain empty-string values for strict-typed
    // Postgres columns (date_of_birth = "", wake_up_time = "", etc.).
    // PostgREST responds 400 "invalid input syntax for type date" and the
    // entire row is rejected. `_sanitize` drops those entries so the upsert
    // succeeds with whatever the user did provide.
    await supabase.from('user_profile').upsert({
      'user_id': userId,
      ..._sanitize(profileData),
    }, onConflict: 'user_id');

    await supabase.from('user_progress').upsert({
      'user_id': userId,
      ..._sanitize(progressData),
    }, onConflict: 'user_id');
  }

  /// Strips empty strings and non-finite numbers from a payload map.
  /// Null values are preserved (PostgREST happily stores NULL in nullable
  /// columns) but empty strings on strict-typed columns (date, time, numeric,
  /// integer, timestamptz) would otherwise reject the entire upsert.
  ///
  /// Also coerces the five integer-only target columns
  /// (daily_calories / protein_grams / carbs_grams / fat_grams /
  /// water_target_ml) via `.round()` — NutritionTargets stores them as int
  /// today, but a stale Hive row from a pre-migration-021 client could hold a
  /// double and tank the whole row.
  static const _integerOnlyColumns = <String>{
    'daily_calories',
    'protein_grams',
    'carbs_grams',
    'fat_grams',
    'water_target_ml',
    'days_per_week',
    'session_duration_minutes',
    'bmr',
    'tdee',
  };

  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is String && value.trim().isEmpty) {
        // Drop empty string — column is either nullable (fine to omit) or
        // strict-typed and would reject the whole row.
        return;
      }
      if (value is double && (value.isNaN || value.isInfinite)) {
        return;
      }
      if (_integerOnlyColumns.contains(key) && value is num) {
        out[key] = value.round();
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}
