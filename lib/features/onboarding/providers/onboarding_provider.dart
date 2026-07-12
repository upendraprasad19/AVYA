import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/utils/name_format.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/stat_snapshot_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/referral_code_stash_provider.dart';
import 'dart:async';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';
import 'package:icanbefitter/core/services/water_target_service.dart';

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
  OnboardingState build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    return const OnboardingState();
  }

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

      // Unit 4 (d-bf): honor body-fat in the SAVED calc (Katch when provided,
      // Mifflin when null). Parsed here (was below, AFTER the calc). The flag is
      // the kill-switch; the SAME expression runs in plan_screen._computeTargets
      // so the preview == the saved daily_calories. NULLABLE parse (NOT the
      // 0-flooring _parseDouble) — a skip-user must SAVE null, not 0.0: the calc
      // treats both as Mifflin, but the saved value feeds body_stats.dart which
      // renders 0.0 as a fabricated "0%" (only null → "—"). Same class as the
      // 18.0 default this unit removes — never persist a made-up body-fat.
      final bodyFatPercent = _parseDoubleOrNull(a['body_fat_percent']);
      final bodyFatDisabled =
          HiveService.instance.configBox.get('disable_bodyfat_calc') == true;

      final targets = BmrCalculator.calculateTargets(
        weightKg: currentWeightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
        activityLevel: activityLevel,
        goal: primaryGoal,
        pacePreference: (a['pace_preference'] as String?) ?? 'balanced',
        targetWeightKg: targetWeightKg > 0 ? targetWeightKg : null,
        bodyFatPercent:
            BmrCalculator.bodyFatForCalc(bodyFatPercent, disabled: bodyFatDisabled),
      );

      // Fields set via setAnswer in plan_screen._onReportForDuty that were
      // previously NOT copied into the profile map. Without these, a fresh
      // account shipped with `injuries == null` / `diet_preference == null`
      // / `body_fat_percent == null` / `start_date == null` / `city == null`
      // in Hive → the home-screen profile-completeness nudge flagged
      // "Injuries" (and other Tier-2 fields) as missing for every new user.
      // Fixed 2026-04-24: carry the answers through to the saved profile.
      final injuries = (a['injuries'] as List<dynamic>?)?.cast<String>() ??
          <String>['none'];
      final dietPreference =
          (a['diet_preference'] as String?) ?? 'veg';
      // `bodyFatPercent` is parsed earlier now (Unit 4 d-bf — fed into the calc).
      // String field (`this_monday` / `next_monday` / etc.) distinct
      // from the local DateTime-typed `startDate` used below for
      // `generateAndSchedule`.
      final startDateKey = (a['start_date'] as String?) ?? 'this_monday';
      final city = a['city'] as String?;

      // F17 · Water target — single source of truth via WaterTargetService.
      // Computed before the profile map so it can be inserted inline.
      // Applies floor (2500 ml), ceiling (4000 ml), training-day and
      // lifestyle bonuses so the onboarding seed matches the formula used
      // at runtime by all 4 UI sites.
      final waterTargetMl = WaterTargetService.computeFromProfile({
        'current_weight_kg': currentWeightKg,
        'lifestyle_activity': lifestyleActivity,
        'days_per_week': daysPerWeek,
      });

      final profile = {
        // OBS-13 — title-case at the writer (textCapitalization.words is a mobile
        // keyboard hint only; web saves a lowercase-typed name verbatim).
        'full_name': titleCaseName(fullName),
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
        'injuries': injuries,
        'diet_preference': dietPreference,
        'body_fat_percent': bodyFatPercent,
        'start_date': startDateKey,
        if (city != null && city.isNotEmpty) 'city': city,
        'bmr': targets.bmr,
        'tdee': targets.tdee,
        'daily_calories': targets.dailyCalories,
        'protein_grams': targets.proteinGrams,
        // `carb_grams` (legacy) kept for backwards compat with older Hive
        // readers; `carbs_grams` (plural) matches the Supabase column and
        // the F17 sync mapping. Both point at the same value.
        'carb_grams': targets.carbGrams,
        'carbs_grams': targets.carbGrams,
        'fat_grams': targets.fatGrams,
        'water_target_ml': waterTargetMl,
        // onboarding_completed_at — stamp the Hive profile too (Unit D, diagnose
        // c4d8a2). Previously ONLY the cloud profileData write (below) + the
        // restoring-screen self-heal set this; the Hive profile never carried it,
        // so local readers (prediction card, rank anchor) saw null AND
        // _syncUserProfile had nothing to keep the cloud column in step. UTC
        // (Unit B): it feeds the user_profile.onboarding_completed_at timestamptz.
        'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Use saveProfile (not updateProfileFields) to guarantee a clean
      // slate. updateProfileFields merges onto existing data, which would
      // carry over avatar_url / banner_url from a previously logged-in account.
      await _userRepo.saveProfile(profile);

      // APK Test #6 obs #5 — seed weight_logs with onboarding weight so
      // the home screen's WeightHistoryNotifier shows the user's starting
      // weight as the first point on the sparkline immediately. Without
      // this seed, the chart was blank until the user manually logged a
      // weight from Home → Quick Actions.
      //
      // Hive key shape `wlog_<isoTimestamp>` mirrors the convention used
      // by WeightLogRepository.logWeight (lib/shared/repositories/health_repository.dart).
      if (currentWeightKg > 0) {
        try {
          // audit-2026-05-16 task E.7 — routes through HealthWriteService.
          // The service writes the canonical `weight_<istDate>` key with
          // IST anchoring built-in. Idempotency: skip if any weight_log
          // already exists for today's IST date (defensive — a re-run of
          // completeOnboarding shouldn't double-seed).
          final now = DateTime.now();
          final dateStr = now
              .toUtc()
              .add(const Duration(hours: 5, minutes: 30))
              .toIso8601String()
              .substring(0, 10);
          final existing = _hive.healthBox.values.whereType<Map>().any((row) {
            return row['type'] == 'weight_log' && row['date'] == dateStr;
          });
          if (!existing) {
            await HealthWriteService.instance.logWeight(
              date: now,
              weightKg: currentWeightKg,
              source: WriteSource.onboarding,
            );
          }
        } catch (e) {
          // Defensive — Hive write failure must not block onboarding completion.
          debugPrint('[OnboardingNotifier] weight_log seed failed: $e');
        }
      }

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
        injuries: injuries, // U4: thread collected injuries (normalized in generateV4)
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

      // Note: the AI coach has no trial (removed 2026-06-07 / F1) — it's a
      // flat 10/day forever, server-enforced. No trial-start key is written
      // here. The dead 'ai_chat_started_at' local key was removed too.

      // Sync onboarding flag + profile to Supabase.
      //
      // Set a persistent `pending_onboarding_sync` flag in userBox BEFORE
      // the first attempt (migrated from configBox in Test #11.1). Any
      // bootstrap on the next app launch can read this and replay the
      // sync if it didn't land (fixes the "user_profile stays all-NULL"
      // bug observed 2026-04-17 on icanbefitter@gmail.com).
      //
      // We clear the flag only after a confirmed successful upsert. The
      // 10 s inline retry stays — it catches the common "JWT warm-up"
      // miss right after sign-up — but the flag is the real safety net.
      // ── Hive-first navigation (diagnose a1f9c4) ─────────────────
      // Every LOCAL write above (profile, plan, progress, onboarded-stamp) is
      // durable. The cloud sync + schedule push + referral redeem + verify are
      // network I/O — they MUST NOT block REPORT FOR DUTY (rule 1): a slow /
      // cold / stalled backend (e.g. the fresh-signup sync flood on the free
      // tier) stranded the spinner forever, because the awaited cloud calls
      // below never resolved AND never threw (the 10s retry only fires on a
      // THROW, not a HANG). Capture the referral stash NOW (synchronously,
      // while `ref` is valid), then run the whole cloud chain in the BACKGROUND
      // preserving its order (the user_profile/users upsert must land before
      // the referral EF reads the users row). The `pending_onboarding_sync`
      // flag + bootstrap replay backstop a missed sync. Kill-switch:
      // `disable_onboarding_async_sync` restores the old blocking path.
      await MigratedKey.write('pending_onboarding_sync', true);
      final referralCode = ref.read(referralCodeStashProvider).trim();
      if (referralCode.isNotEmpty) {
        // Clear NOW so it can't be replayed; the code is captured above.
        ref.read(referralCodeStashProvider.notifier).clear();
      }
      final cloudCatchUp = _syncOnboardingAndPostActions(profile, referralCode);
      if (HiveService.instance.configBox
              .get('disable_onboarding_async_sync') ==
          true) {
        await cloudCatchUp; // kill-switch: restore old blocking behaviour
      } else {
        unawaited(cloudCatchUp.catchError((Object e, StackTrace s) {
          debugPrint('[Onboarding] background cloud catch-up error: $e');
        }));
      }

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
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('onboarding_complete_failed',
          message: clipped));
      state = state.copyWith(
        isCompleting: false,
        error: 'Something went wrong: ${e.runtimeType}. Please try again.',
      );
      return null;
    }
  }

  /// Cloud catch-up after onboarding's LOCAL writes are durable. Fire-and-forget
  /// (Hive-first — diagnose a1f9c4) so REPORT FOR DUTY navigation never blocks on
  /// a slow / stalled backend. ORDER MATTERS: the user_profile/users upsert
  /// (`_syncOnboardingToSupabase`) must land before the referral EF reads the
  /// public.users row, so those stay sequential. Uses singletons only (no `ref`
  /// after the screen may dispose); the referral code is captured + the stash
  /// cleared by the caller before navigation.
  Future<void> _syncOnboardingAndPostActions(
      Map<String, dynamic> profile, String referralCode) async {
    try {
      await _syncOnboardingToSupabase(profile);
      await MigratedKey.delete('pending_onboarding_sync');
    } catch (syncErr) {
      // Visible in debug console for testing; not shown to the user.
      debugPrint('[Onboarding] Supabase sync failed: $syncErr — scheduling retry');
      // Telemetry — surface silent upsert failures to `client_errors`.
      unawaited(SyncService.instance.reportSyncFailure(
        opType: 'onboarding_sync',
        error: syncErr,
      ));
      // Retry once after 10s — JWT may need refresh after sign-up flow.
      unawaited(Future.delayed(const Duration(seconds: 10), () async {
        try {
          await SupabaseService.instance.client.auth.refreshSession();
          await _syncOnboardingToSupabase(profile);
          await MigratedKey.delete('pending_onboarding_sync');
          debugPrint('[Onboarding] Retry succeeded');
        } catch (e) {
          debugPrint('[Onboarding] Retry also failed: $e — '
              'pending_onboarding_sync flag left set; bootstrap will replay on next launch');
          unawaited(SyncService.instance.reportSyncFailure(
            opType: 'onboarding_sync_retry',
            error: e,
            retryCount: 1,
          ));
        }
      }));
    }

    // Schedule rows + AI snapshot + baseline stat snapshot + prediction — all
    // fire-and-forget (each has its own error handling). These also gate
    // `scheduled_workouts` cloud rows + the first AI-context snapshot.
    unawaited(SyncService.instance.syncWorkoutData());
    // H1b Part B1 (B-fix-2) — onboarding's first AI-context snapshot is eager
    // (the non-coalesced *Now()) so it is guaranteed attempted, not deferred to
    // a coalescer trailing pass that could be lost in the signup-storm load.
    unawaited(SyncService.instance.pushSnapshotNow());
    unawaited(StatSnapshotService.instance.snapshotOnboarding());
    _generatePrediction(profile);

    // ── Referral code redemption ───────────────────────────────
    // AFTER the users row upsert above (the EF reads public.users). Non-fatal —
    // a failed redeem must never block the user from reaching home.
    if (referralCode.isNotEmpty) {
      try {
        // callFunction refreshes the JWT first (§2.31 — a raw invoke on an aged
        // web token 401s silently; check_authed_invoke_fresh_token.dart gate).
        final response = await SupabaseService.instance
            .callFunction('redeem-referral', body: {'code': referralCode});
        if (response.status == 200) {
          debugPrint('[referral] redeemed $referralCode at onboarding');
          // Refresh subscription cache so any PRO grant reflects immediately.
          try {
            await SubscriptionService.instance.verifyFromServer();
          } catch (_) {
            // Non-fatal — user will get correct status on next launch.
          }
        } else {
          debugPrint('[referral] redeem failed at onboarding: ${response.data}');
        }
      } catch (e) {
        debugPrint('[referral] redeem exception at onboarding: $e');
      }
    }
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// Like [_parseDouble] but returns null (not 0.0) for absent/blank input.
  /// Used for OPTIONAL numeric fields (e.g. body_fat_percent) where 0.0 is a
  /// fabricated value that would persist + display as "0%". Unit 4 (d-bf).
  double? _parseDoubleOrNull(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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

      const rulesBlock = '''
CRITICAL OUTPUT RULES:
- Reply in plain English sentences or bullet points only.
- DO NOT use any structured format.
- DO NOT prefix lines with labels like "outcome:", "weight_kg:", "summary:", "prediction:", or any colon-separated keys.
- DO NOT return JSON. DO NOT wrap in code fences.
- Just write 2-4 bullet points of prose. Direct address ("you").
- 80 words maximum.''';

      final predictionPrompt = '''Predict realistic fitness outcomes at 3, 6, and 12 months.

Profile: ${profile['gender']}, age $age, ${profile['height_cm']}cm, ${profile['current_weight_kg']}kg → ${profile['target_weight_kg']}kg goal
Goal: ${profile['primary_goal']}, Experience: ${profile['fitness_experience']}
Training: ${profile['days_per_week']} days/week, ${profile['equipment_access']}
BMR: ${(profile['bmr'] as num?)?.toStringAsFixed(0)}, TDEE: ${(profile['tdee'] as num?)?.toStringAsFixed(0)}
$rulesBlock

Format (use • not JSON):
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
        await MigratedKey.write('prediction_text', reply);
        await MigratedKey.write(
            'prediction_date', DateTime.now().toIso8601String());
        await MigratedKey.write(
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
        // UTC (Unit B, diagnose c4d8a2): users.last_active_at is a timestamptz;
        // a naive local ISO was stored ~5.5h ahead, skewing the re-engagement /
        // founder-metrics cron windows that filter on this column.
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      },
      profileData: {
        // Q1 decision tree: RestoringScreen checks this column to determine
        // whether onboarding was completed. Must be written atomically with
        // the rest of the profile so the row is always in a consistent state.
        'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
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
        'lifestyle_activity': profile['lifestyle_activity'],
        'pace_preference': profile['pace_preference'],
        'diet_preference': profile['diet_preference'],
        // Pass the List<String> directly; supabase_flutter serialises it
        // to a Postgres text[] literal. Prior `.toString()` produced the
        // string "[none]" which was overwriting the local List on
        // cross-device restore and breaking the completeness check.
        // Fix lands with migration 033 (injuries column text → text[]).
        'injuries': profile['injuries'],
        'city': profile['city'],
        'bmr': profile['bmr'],
        'tdee': profile['tdee'],
        'body_fat_percent': profile['body_fat_percent'],
        'body_fat_assessed_at': profile['body_fat_assessed_at'],
        'session_duration_minutes': profile['session_duration_minutes'],
        'physique_focus': profile['physique_focus'],
        'avatar_url': profile['avatar_url'],
        'banner_url': profile['banner_url'],
        'wake_up_time': profile['wake_up_time'],
        // F17 · Computed nutrition targets (migration 021).
        'daily_calories': profile['daily_calories'],
        'protein_grams': profile['protein_grams'],
        'carbs_grams': profile['carbs_grams'],
        'fat_grams': profile['fat_grams'],
        'water_target_ml': profile['water_target_ml'],
      },
      progressData: {
        'current_phase': 1,
        'current_week': 1,
        'total_workouts_done': 0,
        'current_streak_weeks': 0,
        'phase_started_at': DateTime.now().toIso8601String(),
        'plan_generated_at': DateTime.now().toIso8601String(),
        // F21 · Seed detected_experience_level from the onboarding answer.
        // Later AI detection may overwrite if it diverges; for now, having
        // any value is better than having none (it was previously null
        // until first AI detection ran, leaving user_progress incomplete).
        'detected_experience_level': profile['fitness_experience'],
      },
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
        OnboardingNotifier.new);
