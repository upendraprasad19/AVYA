import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import '../utils/profile_image_url.dart';

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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
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
            toolbarColor: AppColors.bg,
            toolbarWidgetColor: AppColors.textPrimary,
            backgroundColor: AppColors.bg,
            activeControlsWidgetColor: AppColors.accent,
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

      // Version the URL so the cache busts ONLY when the image changes (storage
      // reuses a fixed object path `<uid>/avatar.jpg` → identical publicUrl on
      // re-upload). The read path passes this through verbatim, so navigating to
      // Profile is a cache HIT, not a refetch (APK +34 / obs 4). closes-diagnose: b1f3a7.
      final versionedUrl = ProfileImageUrl.versioned(
        publicUrl,
        version: DateTime.now().millisecondsSinceEpoch,
      );

      // Save to user_profile table (background sync)
      await UserRepository.updateSupabaseProfileField(
        userId: userId,
        fields: {'avatar_url': versionedUrl},
      );

      // Save to Hive
      await updateProfile({'avatar_url': versionedUrl});

      // Evict any in-memory cache for the URL (belt-and-braces; the new ?v=
      // already guarantees a fresh disk fetch).
      PaintingBinding.instance.imageCache.evict(NetworkImage(versionedUrl));

      return UploadOutcome(UploadResult.success, url: versionedUrl);
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
            toolbarColor: AppColors.bg,
            toolbarWidgetColor: AppColors.textPrimary,
            backgroundColor: AppColors.bg,
            activeControlsWidgetColor: AppColors.accent,
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

      // Version the URL so the cache busts ONLY when the image changes (storage
      // reuses a fixed object path `<uid>/banner.jpg` → identical publicUrl on
      // re-upload). The read path passes this through verbatim, so navigating to
      // Profile is a cache HIT, not a refetch (APK +34 / obs 4). closes-diagnose: b1f3a7.
      final versionedUrl = ProfileImageUrl.versioned(
        publicUrl,
        version: DateTime.now().millisecondsSinceEpoch,
      );

      // Save to user_profile table (background sync)
      await UserRepository.updateSupabaseProfileField(
        userId: userId,
        fields: {'banner_url': versionedUrl},
      );

      // Save to Hive
      await updateProfile({'banner_url': versionedUrl});

      // Evict any in-memory cache for the URL (belt-and-braces; the new ?v=
      // already guarantees a fresh disk fetch).
      PaintingBinding.instance.imageCache.evict(NetworkImage(versionedUrl));

      return UploadOutcome(UploadResult.success, url: versionedUrl);
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

  /// Week within the phase, clamped [1,4]. During a hold this stays 4 — the
  /// phase's four weeks ARE elapsed, so it remains the honest input for the
  /// "weeks of this phase done" progress bar. It is NOT an honest LABEL for a
  /// holder; read [holdOrdinal] first for that (FOB-1 / OI-60).
  final int currentWeek;

  /// 1-based hold number when today is a live hold day, else null. Null for
  /// every user while `enable_hold_weeks` is OFF, so every consumer branching
  /// on it is inert until the flip.
  final int? holdOrdinal;
  final String primaryGoal;
  final bool isPro;

  bool get isHolding => holdOrdinal != null;

  const UserStatsData({
    this.totalWorkouts = 0,
    this.currentWeight = 0,
    this.bmi = 0,
    this.currentStreak = 0,
    this.currentPhase = 1,
    this.currentWeek = 1,
    this.holdOrdinal,
    this.primaryGoal = '',
    this.isPro = false,
  });
}

class UserStatsNotifier extends Notifier<UserStatsData> {
  @override
  UserStatsData build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final profile = UserRepository.instance.getProfile() ?? {};
    final progress = UserRepository.instance.getProgress() ?? {};
    // B-pass P1 (fob1-week-identity): this MUST be `ref.watch`, not the
    // singleton call it started as. journey_timeline and profile_content read
    // their hold state exclusively through this notifier, and neither
    // hold-taking call site (home_screen's PlanExpiredCard.onRedoComplete,
    // train/screen.dart) invalidates userStatsProvider — they invalidate
    // currentPlanProvider. The 5 tabs live under StatefulShellRoute.indexedStack,
    // so an already-mounted Profile tab is NOT rebuilt on tab-switch. With a
    // plain singleton read this notifier had NO dependency-graph link to the
    // hold write, so Profile kept showing the pre-hold "WEEK 4 OF 4" while Home
    // and Train said "HOLDING · Hn" — reintroducing the exact cross-tab
    // contradiction this batch exists to close. Watching the provider (which
    // itself watches currentPlanProvider) fixes it for EVERY current and future
    // hold-write call site, rather than patching each one with an invalidate.
    final weekId = ref.watch(weekIdentityProvider);

    // H-1 (audit-2026-05-11) — watch `subscriptionInfoProvider`
    // instead of snapshotting `SubscriptionService.isPro()` at build
    // time. Without this the userStatsProvider stays at `isPro:false`
    // after a fresh PRO upgrade until the user manually triggers a
    // rebuild — same APK Test #12 / C-2 regression class. Watch means
    // the notifier rebuilds whenever the canonical subscription
    // provider invalidates.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;

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
      // OI-41 (audit-2026-05-17 Hermes C7) — single streak source.
      // Pre-fix this read the cached `current_streak_weeks` from
      // user_progress while Home/Rank computed live via
      // `WorkoutRepository.currentStreak()`. Users saw different
      // streak numbers in different places. Now both surfaces hit the
      // canonical live walk-back. sot_registry entry pins this contract.
      currentStreak: WorkoutRepository.instance.currentStreak(),
      currentPhase: (progress['current_phase'] as int?) ?? 1,
      // FOB-1 (OI-60): one read of the honest identity feeds BOTH fields —
      // currentWeek keeps the clamped value the progress bar needs, holdOrdinal
      // carries the label identity. Reading them from two separate calls would
      // let them disagree across a midnight rollover.
      currentWeek: weekId.weekInPhase ??
          WorkoutScheduleService.instance.getCurrentWeekNumber(),
      holdOrdinal: weekId.holdOrdinal,
      primaryGoal:
          (profile['primary_goal'] as String?) ?? 'Not set',
      isPro: isPro,
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

  /// APK Test #12 / Task C-4 — true when a Razorpay payment succeeded
  /// locally but the server-side webhook hasn't yet confirmed the
  /// subscription row. Pills/badges that watch this provider can
  /// render a "verifying" hint (e.g. ⟳ glyph) instead of a regular
  /// PRO badge during this window. Cleared once the webhook fires
  /// or the 10-min grace window expires.
  final bool isVerifying;

  const SubscriptionInfoData({
    this.isPro = false,
    this.plan,
    this.expiresAt,
    this.isVerifying = false,
  });
}

class SubscriptionInfoNotifier extends Notifier<SubscriptionInfoData> {
  @override
  SubscriptionInfoData build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final sub = SubscriptionService.instance;
    // OI-44 Unit 6 — PURE read inside a provider build. `isPro()` enforces the
    // entitlement invariants, and on expiry / cross-account it calls
    // `_downgradeLocally()` → `onStateChanged` → `app.dart:47`
    // `ref.invalidate(subscriptionInfoProvider)` — i.e. THIS provider's build
    // invalidating itself. It terminated (the second pass reads isPro=false and
    // returns before mutating) and the invalidation lands a microtask later
    // rather than synchronously, so it was one wasted rebuild rather than a
    // crash — but a build method must not mutate. Enforcement now runs at boot
    // (`splash_screen`) and on account swap (`_onUserChanged`), which are the
    // only two moments the state can actually become stale or cross-account.
    final localIsPro = sub.proStateSnapshot();
    final inFlight = sub.isPaymentInFlight;

    // APK Test #12.8 — pro_pill_state_mismatch_observed probe.
    // Fires when build() returns isPro=false but a strong "should be
    // PRO" signal exists locally:
    //   (a) payment grace window is active (Razorpay just succeeded), or
    //   (b) localActivationAt within 15 min (Phase 3 fallback path).
    // Either case means: pill will render GO PRO while a subscription
    // creation is mid-flight. Catches the founder's "PRO pill stuck"
    // observation class. Fire-and-forget; never blocks the build path.
    if (!localIsPro) {
      try {
        final localAct = MigratedKey.read<dynamic>('localActivationAt');
        DateTime? activatedAt;
        if (localAct != null) {
          activatedAt = DateTime.tryParse(localAct.toString());
        }
        final activationFresh = activatedAt != null &&
            DateTime.now().difference(activatedAt).inMinutes < 15;
        if (inFlight || activationFresh) {
          unawaited(ErrorTelemetry.logEvent(
            'pro_pill_state_mismatch_observed',
            message: 'paymentInFlight=$inFlight '
                'localActivationAtFresh=$activationFresh '
                'localActivationAt=$localAct',
          ));
        }
      } catch (_) {
        // Probe must never break the provider build.
      }
    }

    return SubscriptionInfoData(
      isPro: localIsPro,
      plan: sub.currentPlan,
      expiresAt: sub.expiresAt,
      isVerifying: inFlight,
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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
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
    // Obs 5 cleanup (2026-06-05): match the health writer's IST date key
    // (HealthWriteService uses istDateStr) — was device-local y/m/d, which
    // drifts vs the written `date`/`sleep_log_<istDate>` keys at IST 00:00–05:30.
    final todayStr = istDateStr(now);

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
  ///
  /// audit-2026-05-16 task E.7 / finding F2-R2: routes through
  /// `HealthWriteService` so the Hive key uses `istDateStr` (was
  /// device-local `now.year-now.month-now.day`, which at IST 00:00–05:30
  /// produced the prev-UTC-day key and silently dropped the entry from
  /// IST readers).
  Future<void> logSleep({required double hours, required String quality}) async {
    await HealthWriteService.instance.logSleep(
      date: DateTime.now(),
      hours: hours,
      quality: quality,
      source: WriteSource.manual,
    );
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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final count =
        MigratedKey.readWithDefault<int>('progress_photo_count', 0);
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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // Bug 2026-05-20 (diagnose c2a91f) — pre-fix read configBox['first_launch_date']
    // which was never written anywhere in the codebase, so usageWeeks was
    // always 0 → Weekly Report card permanently locked at "Available after
    // Week 1". Switch to the canonical Supabase signup timestamp, already
    // used at 5 other callsites (rank_service, referral_eligibility,
    // service_record_section, rank_ladder_screen). Survives reinstalls.
    final createdAtIso = SupabaseService.instance.currentUser?.createdAt;
    if (createdAtIso == null) return 0;
    final createdAt = DateTime.tryParse(createdAtIso);
    if (createdAt == null) return 0;
    return DateTime.now().difference(createdAt).inDays ~/ 7;
  }
}

final usageWeeksProvider =
    NotifierProvider<UsageWeeksNotifier, int>(UsageWeeksNotifier.new);

// ── First Report Viewed ──────────────────────────────────────────

class FirstReportViewedNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    return MigratedKey.readWithDefault<bool>('first_report_viewed', false);
  }

  Future<void> markViewed() async {
    await MigratedKey.write('first_report_viewed', true);
    state = true;
  }
}

final firstReportViewedProvider =
    NotifierProvider<FirstReportViewedNotifier, bool>(
        FirstReportViewedNotifier.new);
