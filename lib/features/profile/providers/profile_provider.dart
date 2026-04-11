import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

enum UploadResult { success, cancelled, error }

class UploadOutcome {
  final UploadResult result;
  final String? url;
  final String? errorMessage;
  const UploadOutcome(this.result, {this.url, this.errorMessage});
}

// ── User Profile ─────────────────────────────────────────────────

class UserProfileNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() {
    return UserRepository.instance.getProfile() ?? {};
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    await UserRepository.instance.updateProfileFields(fields);
    state = UserRepository.instance.getProfile() ?? {};
  }

  Future<void> saveFullProfile(Map<String, dynamic> profile) async {
    await UserRepository.instance.saveProfile(profile);
    state = profile;
  }

  Future<void> recalculateTargets() async {
    final profile = state;
    final weight = (profile['current_weight_kg'] as num?)?.toDouble();
    final height = (profile['height_cm'] as num?)?.toDouble();
    final dob = profile['date_of_birth'] as String?;
    final gender = profile['gender'] as String?;
    final goal = profile['primary_goal'] as String?;

    if (weight == null ||
        height == null ||
        dob == null ||
        gender == null ||
        goal == null) {
      return;
    }

    final birthDate = DateTime.tryParse(dob);
    if (birthDate == null) return;

    final age = DateTime.now().difference(birthDate).inDays ~/ 365;
    if (age <= 0) return;

    // Prefer resolving from lifestyle + days (new system) over the old
    // stored activity_level string (which was user-selected directly).
    final lifestyle = profile['lifestyle_activity'] as String?;
    final days = (profile['days_per_week'] as num?)?.toInt() ?? 4;
    final resolvedActivity = lifestyle != null
        ? BmrCalculator.resolveActivityLevel(lifestyle, days)
        : (profile['activity_level'] as String? ?? 'moderate');

    final targetWeight = (profile['target_weight_kg'] as num?)?.toDouble();
    final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();

    final targets = BmrCalculator.calculateTargets(
      weightKg: weight,
      heightCm: height,
      age: age,
      gender: gender,
      activityLevel: resolvedActivity,
      goal: goal,
      pacePreference: (profile['pace_preference'] as String?) ?? 'balanced',
      targetWeightKg: targetWeight != null && targetWeight > 0
          ? targetWeight
          : null,
      bodyFatPercent: bodyFat,
    );

    // Persist computed targets AND the resolved activity level so downstream
    // code that reads 'activity_level' directly stays consistent.
    await updateProfile({
      ...targets.toMap(),
      'activity_level': resolvedActivity,
    });
  }

  /// Upload avatar image using ImagePicker and save to Supabase storage.
  /// Returns an [UploadOutcome] indicating success, cancellation, or error.
  Future<UploadOutcome> uploadAvatar() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null) {
        debugPrint('[ProfileProvider.uploadAvatar] picker returned null — user cancelled or permission denied');
        return const UploadOutcome(UploadResult.cancelled, errorMessage: 'No image selected. Check gallery permissions in Settings.');
      }

      // Crop to square (circle preview)
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 92,
        maxWidth: 800,
        maxHeight: 800,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: const Color(0xFF07090e),
            toolbarWidgetColor: const Color(0xFFeef2f7),
            backgroundColor: const Color(0xFF07090e),
            activeControlsWidgetColor: const Color(0xFF00D4FF),
            cropStyle: CropStyle.circle,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
        ],
      );
      if (cropped == null) {
        debugPrint('[ProfileProvider.uploadAvatar] cropper returned null — user dismissed crop screen');
        return const UploadOutcome(UploadResult.cancelled, errorMessage: 'Crop cancelled');
      }

      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return const UploadOutcome(UploadResult.error, errorMessage: 'Not signed in');

      final bytes = await File(cropped.path).readAsBytes();
      final filePath = '$userId/avatar.jpg';

      final publicUrl = await UserRepository.uploadImage(
        bucket: 'avatars',
        filePath: filePath,
        bytes: bytes,
      );

      // Save to user_profile table (background sync)
      await UserRepository.updateSupabaseProfileField(
        userId: userId,
        fields: {'avatar_url': publicUrl},
      );

      // Save to Hive
      await updateProfile({'avatar_url': publicUrl});

      // Evict cached image
      PaintingBinding.instance.imageCache.evict(NetworkImage(publicUrl));

      return UploadOutcome(UploadResult.success, url: publicUrl);
    } catch (e) {
      debugPrint('Upload error: $e');
      return UploadOutcome(UploadResult.error, errorMessage: e.toString());
    }
  }

  /// Upload banner image using ImagePicker and save to Supabase storage.
  /// Returns an [UploadOutcome] indicating success, cancellation, or error.
  Future<UploadOutcome> uploadBanner() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null) {
        debugPrint('[ProfileProvider.uploadBanner] picker returned null — user cancelled or permission denied');
        return const UploadOutcome(UploadResult.cancelled, errorMessage: 'No image selected. Check gallery permissions in Settings.');
      }

      // Crop to 3:1 banner aspect ratio
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 1),
        compressQuality: 95,
        maxWidth: 1920,
        maxHeight: 640,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Banner',
            toolbarColor: const Color(0xFF07090e),
            toolbarWidgetColor: const Color(0xFFeef2f7),
            backgroundColor: const Color(0xFF07090e),
            activeControlsWidgetColor: const Color(0xFF00D4FF),
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
            lockAspectRatio: true,
          ),
        ],
      );
      if (cropped == null) {
        debugPrint('[ProfileProvider.uploadBanner] cropper returned null — user dismissed crop screen');
        return const UploadOutcome(UploadResult.cancelled, errorMessage: 'Crop cancelled');
      }

      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return const UploadOutcome(UploadResult.error, errorMessage: 'Not signed in');

      final bytes = await File(cropped.path).readAsBytes();
      final filePath = '$userId/banner.jpg';

      final publicUrl = await UserRepository.uploadImage(
        bucket: 'banners',
        filePath: filePath,
        bytes: bytes,
      );

      // Save to user_profile table (background sync)
      await UserRepository.updateSupabaseProfileField(
        userId: userId,
        fields: {'banner_url': publicUrl},
      );

      // Save to Hive
      await updateProfile({'banner_url': publicUrl});

      // Evict cached image
      PaintingBinding.instance.imageCache.evict(NetworkImage(publicUrl));

      return UploadOutcome(UploadResult.success, url: publicUrl);
    } catch (e) {
      debugPrint('Upload error: $e');
      return UploadOutcome(UploadResult.error, errorMessage: e.toString());
    }
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, Map<String, dynamic>>(
        UserProfileNotifier.new);

// ── User Stats ───────────────────────────────────────────────────

class UserStatsData {
  final int totalWorkouts;
  final double currentWeight;
  final double bmi;
  final int currentStreak;
  final int currentPhase;
  final int currentWeek;
  final String primaryGoal;
  final bool isPro;

  const UserStatsData({
    this.totalWorkouts = 0,
    this.currentWeight = 0,
    this.bmi = 0,
    this.currentStreak = 0,
    this.currentPhase = 1,
    this.currentWeek = 1,
    this.primaryGoal = '',
    this.isPro = false,
  });
}

class UserStatsNotifier extends Notifier<UserStatsData> {
  @override
  UserStatsData build() {
    final profile = UserRepository.instance.getProfile() ?? {};
    final progress = UserRepository.instance.getProgress() ?? {};

    final weight =
        (profile['current_weight_kg'] as num?)?.toDouble() ?? 0;
    final heightCm = (profile['height_cm'] as num?)?.toDouble() ?? 0;
    final heightM = heightCm / 100;
    final bmi =
        heightM > 0 ? weight / (heightM * heightM) : 0.0;

    return UserStatsData(
      totalWorkouts:
          (progress['total_workouts_done'] as int?) ?? 0,
      currentWeight: weight,
      bmi: double.parse(bmi.toStringAsFixed(1)),
      currentStreak:
          (progress['current_streak_weeks'] as int?) ?? 0,
      currentPhase: (progress['current_phase'] as int?) ?? 1,
      currentWeek: (progress['current_week'] as int?) ?? 1,
      primaryGoal:
          (profile['primary_goal'] as String?) ?? 'Not set',
      isPro: SubscriptionService.instance.isPro(),
    );
  }
}

final userStatsProvider =
    NotifierProvider<UserStatsNotifier, UserStatsData>(
        UserStatsNotifier.new);

// ── Subscription Info ────────────────────────────────────────────

class SubscriptionInfoData {
  final bool isPro;
  final String? plan;
  final DateTime? expiresAt;

  const SubscriptionInfoData({
    this.isPro = false,
    this.plan,
    this.expiresAt,
  });
}

class SubscriptionInfoNotifier extends Notifier<SubscriptionInfoData> {
  @override
  SubscriptionInfoData build() {
    final sub = SubscriptionService.instance;
    return SubscriptionInfoData(
      isPro: sub.isPro(),
      plan: sub.currentPlan,
      expiresAt: sub.expiresAt,
    );
  }
}

final subscriptionInfoProvider =
    NotifierProvider<SubscriptionInfoNotifier, SubscriptionInfoData>(
        SubscriptionInfoNotifier.new);

// ── Biometric Data ───────────────────────────────────────────────

class BiometricData {
  final int? stepsToday;
  final double? sleepHours;
  final bool isSyncEnabled;

  const BiometricData({
    this.stepsToday,
    this.sleepHours,
    this.isSyncEnabled = false,
  });
}

class BiometricNotifier extends Notifier<BiometricData> {
  @override
  BiometricData build() {
    final configBox = HiveService.instance.configBox;
    final healthBox = HiveService.instance.healthBox;
    final syncEnabled =
        configBox.get('health_sync_enabled', defaultValue: false) as bool;

    if (!syncEnabled) {
      return const BiometricData(isSyncEnabled: false);
    }

    // Read latest steps and sleep from healthBox
    int? stepsToday;
    double? sleepHours;

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final date = entry['date'] as String?;
      if (date != todayStr) continue;
      final type = entry['type'] as String?;

      // Only match typed entries to avoid cross-contamination
      if (type == 'step_log' && entry['steps'] != null) {
        stepsToday = (entry['steps'] as num).toInt();
      }
      if (type == 'sleep_log' && entry['sleep_hours'] != null) {
        sleepHours = (entry['sleep_hours'] as num).toDouble();
      }
    }

    // Also check explicit sleep_log_ key (written by manual logging + cloud restore)
    final sleepLog = healthBox.get('sleep_log_$todayStr');
    if (sleepLog is Map) {
      final hrs = (sleepLog['sleep_hours'] as num?)?.toDouble();
      if (hrs != null) sleepHours = hrs;
    }

    // Also check the shared 'sleep_logs' list (written by AI chat handler).
    // Only applies if no manual/cloud sleep data exists for today.
    if (sleepHours == null) {
      final chatLogs = healthBox.get('sleep_logs');
      if (chatLogs is List) {
        for (final entry in chatLogs) {
          if (entry is Map && entry['date'] == todayStr) {
            final hrs = (entry['sleep_hours'] as num?)?.toDouble();
            if (hrs != null && hrs > 0) sleepHours = hrs;
          }
        }
      }
    }

    // Legacy steps_today key has NO date field — only use it if
    // stepsToday wasn't already found AND steps_date matches today.
    if (stepsToday == null) {
      final stepsDate = healthBox.get('steps_date') as String?;
      if (stepsDate == todayStr) {
        final stepsVal = healthBox.get('steps_today');
        if (stepsVal is int && stepsVal > 0) stepsToday = stepsVal;
      }
    }

    return BiometricData(
      stepsToday: stepsToday,
      sleepHours: sleepHours,
      isSyncEnabled: syncEnabled,
    );
  }

  Future<void> toggleSync(bool enabled) async {
    if (enabled) {
      // Request Health Connect / HealthKit permissions first
      final granted = await HealthSyncService.instance.requestPermissions();
      if (!granted) {
        debugPrint('[BiometricNotifier] Health permissions denied — not enabling sync');
        return; // Don't enable toggle if permissions denied
      }
      // Sync data immediately after permissions granted
      await HealthSyncService.instance.syncToHive();
    }
    await HiveService.instance.configBox
        .put('health_sync_enabled', enabled);
    // Rebuild state
    ref.invalidateSelf();
  }

  /// Manually log sleep for today.
  Future<void> logSleep({required double hours, required String quality}) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await HiveService.instance.healthBox.put('sleep_log_$todayStr', {
      'date': todayStr,
      'sleep_hours': hours,
      'duration_hrs': hours,
      'quality': quality,
      'source': 'manual',
      'created_at': now.toIso8601String(),
    });
    ref.invalidateSelf();
  }
}

final biometricProvider =
    NotifierProvider<BiometricNotifier, BiometricData>(
        BiometricNotifier.new);

// ── Progress Photos ──────────────────────────────────────────────

class ProgressPhotosData {
  final int photoCount;
  final List<String> recentPhotoUrls;

  const ProgressPhotosData({
    this.photoCount = 0,
    this.recentPhotoUrls = const [],
  });
}

class ProgressPhotosNotifier extends Notifier<ProgressPhotosData> {
  @override
  ProgressPhotosData build() {
    final configBox = HiveService.instance.configBox;
    final count =
        configBox.get('progress_photo_count', defaultValue: 0) as int;
    return ProgressPhotosData(photoCount: count);
  }
}

final progressPhotosProvider =
    NotifierProvider<ProgressPhotosNotifier, ProgressPhotosData>(
        ProgressPhotosNotifier.new);

// ── Usage Weeks (for weekly report) ──────────────────────────────

class UsageWeeksNotifier extends Notifier<int> {
  @override
  int build() {
    final configBox = HiveService.instance.configBox;
    final firstLaunchRaw = configBox.get('first_launch_date') as String?;
    if (firstLaunchRaw == null) return 0;

    final firstLaunch = DateTime.tryParse(firstLaunchRaw);
    if (firstLaunch == null) return 0;

    return DateTime.now().difference(firstLaunch).inDays ~/ 7;
  }
}

final usageWeeksProvider =
    NotifierProvider<UsageWeeksNotifier, int>(UsageWeeksNotifier.new);

// ── First Report Viewed ──────────────────────────────────────────

class FirstReportViewedNotifier extends Notifier<bool> {
  @override
  bool build() {
    return HiveService.instance.configBox
            .get('first_report_viewed', defaultValue: false) as bool;
  }

  Future<void> markViewed() async {
    await HiveService.instance.configBox.put('first_report_viewed', true);
    state = true;
  }
}

final firstReportViewedProvider =
    NotifierProvider<FirstReportViewedNotifier, bool>(
        FirstReportViewedNotifier.new);
