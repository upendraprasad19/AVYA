import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

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
    final activity = profile['activity_level'] as String?;
    final goal = profile['primary_goal'] as String?;

    if (weight == null ||
        height == null ||
        dob == null ||
        gender == null ||
        activity == null ||
        goal == null) {
      return;
    }

    final birthDate = DateTime.tryParse(dob);
    if (birthDate == null) return;

    final age = DateTime.now().difference(birthDate).inDays ~/ 365;
    if (age <= 0) return;

    final targets = BmrCalculator.calculateTargets(
      weightKg: weight,
      heightCm: height,
      age: age,
      gender: gender,
      activityLevel: activity,
      goal: goal,
    );

    await updateProfile(targets.toMap());
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

      if (entry['steps'] != null) {
        stepsToday = (entry['steps'] as num).toInt();
      }
      if (entry['sleep_hours'] != null) {
        sleepHours = (entry['sleep_hours'] as num).toDouble();
      }
    }

    return BiometricData(
      stepsToday: stepsToday,
      sleepHours: sleepHours,
      isSyncEnabled: syncEnabled,
    );
  }

  Future<void> toggleSync(bool enabled) async {
    await HiveService.instance.configBox
        .put('health_sync_enabled', enabled);
    // Rebuild state
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
