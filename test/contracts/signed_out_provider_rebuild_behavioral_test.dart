@Timeout(Duration(minutes: 5))
library;

// a2d9f4 - BEHAVIOURAL. Crashlytics (build 50, 2026-11-22): `Bad state:
// HiveUserSession not opened - cannot wrap user-scoped box "healthBox"` thrown
// from BiometricNotifier.build while a tester signed out of one account and into
// another. A provider that watches `authUserIdTokenProvider` is REBUILT the
// moment the session closes, and a build() that reads a raw user-scoped box
// (`HiveService.instance.healthBox` is `GuardedBox.rawBox`, and a repository
// read goes through the same getters) throws in three states:
//   A  Hive torn down while the auth user is still set (the empty stub's
//      rawBox throws),
//   B  both gone (guarded_box.dart's loud StateError),
//   C  the auth user and the Hive owner disagree (an account swap: the empty
//      stub again).
// A probe over every provider that watches the token found 32 that threw (the
// first fix covered 10; the class sweep found the rest). Each now returns its empty
// value on the `'<anon>'` token (the pattern body_measurements_provider.dart
// already used) and rebuilds with the real data once the token flips back.
//
// Real Hive, the real token provider, the real notifiers. Only the auth-state
// stream and the live auth uid (the seam guarded_box shares) are stood in for.
//
// Diagnose: docs/diagnoses/2026-11-24-signed-out-provider-rebuild-a2d9f4.md

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/water_target_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_serving_view_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_supplements_active_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_serving_label.dart';
import 'package:icanbefitter/features/onboarding/providers/onboarding_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/providers/notifications_inbox_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/providers/promotion_history_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';
import 'package:icanbefitter/features/profile/providers/weekly_report_data_provider.dart';
import 'package:icanbefitter/features/train/providers/day_swap_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

/// One provider under test: how to read it, what its signed-out value is, and
/// (where a one-line seed makes it cheap) a real value to prove it comes back.
class _Case {
  _Case(
    this.name,
    this.provider, {
    this.isEmpty,
    this.seed,
    this.isSeeded,
    this.listen,
    this.read,
  });
  final String name;
  // Typed loosely on purpose: ProviderListenable is not exported by Riverpod 3,
  // and the container accepts the concrete provider at run time.
  final dynamic provider;

  /// The value served while the token is '<anon>'; null = "any value, only
  /// the absence of an error is pinned" (downstream providers and controls).
  final bool Function(dynamic value)? isEmpty;
  final Future<void> Function()? seed;

  /// The value signed in (with [seed] written, when there is one).
  final bool Function(dynamic value)? isSeeded;

  /// Typed listen / read for a provider whose state type is nullable: the
  /// dynamic `container.listen` call trips a Riverpod quirk on those.
  final void Function(ProviderContainer c, void Function(Object e) onError)?
      listen;
  final Object? Function(ProviderContainer c)? read;
}

String get _today => istDateStr(DateTime.now());

Future<void> _profile(Map<String, dynamic> p) =>
    HiveService.instance.userBox.put('profile', p);

Map<String, dynamic> _dietPlan(String mealName) => {
      'id': 'diet_plan_1',
      'created_at': '2026-11-14T08:00:00.000',
      'food_type': 'non_veg',
      'meals': [
        {
          'name': mealName,
          'items': [
            {
              'food_id': 'F0019',
              'name': 'Chicken Breast (grilled)',
              'serving_desc': '1 piece',
              'serving_g': 120.0,
              'calories': 198,
              'protein': 37,
              'carbs': 0,
              'fat': 4,
              'category': 'protein',
            },
          ],
        },
      ],
    };

const _otherUser = 'aaaaaaaa-1111-2222-3333-444444444444';

/// Mentions of `authUserIdTokenProvider` per file under lib/ (import and
/// comment lines excluded; any spelling counts: `ref.watch(...)`, a multi-line
/// watch, `.select`, `ref.read`, `ref.listen`). The completeness tripwire in main().
const _kTokenWatchSites = <String, int>{
  'lib/core/services/service_providers.dart': 1,
  'lib/features/admin/providers/admin_dashboard_provider.dart': 1,
  'lib/features/ai_coach/providers/ai_coach_provider.dart': 7,
  'lib/features/ai_coach/providers/pending_tool_intents_provider.dart': 1,
  'lib/features/auth/providers/auth_invalidation_provider.dart': 1,
  'lib/features/home/providers/home_provider.dart': 18,
  'lib/features/home/widgets/insight_card.dart': 1,
  'lib/features/nutrition/providers/diet_plan_provider.dart': 1,
  'lib/features/nutrition/providers/diet_serving_view_provider.dart': 1,
  'lib/features/nutrition/providers/diet_supplements_active_provider.dart': 1,
  'lib/features/nutrition/providers/nutrition_provider.dart': 11,
  'lib/features/nutrition/screens/diet_plan_screen.dart': 4,
  'lib/features/onboarding/providers/onboarding_provider.dart': 1,
  'lib/features/profile/providers/body_measurements_provider.dart': 3,
  'lib/features/profile/providers/measurement_flag_provider.dart': 1,
  'lib/features/profile/providers/measurement_prompt_provider.dart': 1,
  'lib/features/profile/providers/notifications_inbox_provider.dart': 1,
  'lib/features/profile/providers/profile_completeness_provider.dart': 1,
  'lib/features/profile/providers/profile_provider.dart': 6,
  'lib/features/profile/providers/promotion_history_provider.dart': 1,
  'lib/features/profile/providers/referral_eligibility_provider.dart': 1,
  'lib/features/profile/providers/referral_summary_provider.dart': 6,
  'lib/features/profile/providers/weekly_report_data_provider.dart': 1,
  'lib/features/profile/widgets/measurements_card.dart': 1,
  'lib/features/profile/widgets/measurements_card_frame.dart': 1,
  'lib/features/train/providers/day_swap_provider.dart': 2,
  'lib/features/train/providers/preview_plan_provider.dart': 1,
  'lib/features/train/providers/train_provider.dart': 6,
  'lib/features/train/providers/video_render_provider.dart': 1,
  'lib/features/train/widgets/swap_confirm_sheet.dart': 1,
  'lib/shared/mixins/hive_tab_scaffold.dart': 1,
};

List<_Case> _cases() => <_Case>[
  // ── the first ten (the Crashlytics crash is biometricProvider) ──────────
  _Case(
    'biometricProvider (the Crashlytics crash)',
    biometricProvider,
    isEmpty: (v) =>
        v is BiometricData && v.stepsToday == null && !v.isSyncEnabled,
    seed: () async {
      await HiveService.instance.configBox.put('health_sync_enabled', true);
      await HiveService.instance.healthBox.put('steps_log_x', {
        'date': _today,
        'type': 'step_log',
        'steps': 4321,
      });
    },
    isSeeded: (v) =>
        v is BiometricData && v.isSyncEnabled && v.stepsToday == 4321,
  ),
  _Case(
    'todayWeightLoggedProvider',
    todayWeightLoggedProvider,
    isEmpty: (v) => v == false,
    seed: () => HiveService.instance.healthBox
        .put('weight_$_today', {'date': _today, 'weight_kg': 70.0}),
    isSeeded: (v) => v == true,
  ),
  _Case(
    'waterIntakeProvider',
    waterIntakeProvider,
    isEmpty: (v) => v == 0,
    seed: () => HiveService.instance.healthBox.put('water_ml_$_today', 500),
    isSeeded: (v) => v == 500,
  ),
  _Case(
    'urineColorProvider',
    urineColorProvider,
    isEmpty: (v) => v == -1,
    seed: () => HiveService.instance.healthBox
        .put('urine_color_$_today', {'index': 3}),
    isSeeded: (v) => v == 3,
  ),
  _Case(
    'dailyNutritionProvider',
    dailyNutritionProvider,
    isEmpty: (v) =>
        v is DailyNutritionData &&
        v.calories == 0 &&
        v.meals.values.every((m) => m.isEmpty),
    seed: () => HiveService.instance.nutritionBox.put('nlog_seed', {
      'date': _today,
      'meal_type': 'lunch',
      'total_calories': 500.0,
      'total_protein': 30.0,
    }),
    isSeeded: (v) => v is DailyNutritionData && v.meals['lunch']!.isNotEmpty,
  ),
  _Case(
    'weeklyNutritionProvider',
    weeklyNutritionProvider,
    isEmpty: (v) => v is WeeklyNutritionData && v.avgCalories == 0,
    seed: () => HiveService.instance.nutritionBox.put('nlog_seed', {
      'date': _today,
      'meal_type': 'lunch',
      'total_calories': 600.0,
      'total_protein': 40.0,
    }),
    isSeeded: (v) => v is WeeklyNutritionData && v.avgCalories > 0,
  ),
  _Case(
    'savedMealsProvider',
    savedMealsProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    seed: () => HiveService.instance.nutritionBox
        .put('meal_seed', {'is_template': true, 'name': 'Seed meal'}),
    isSeeded: (v) => v is List && v.length == 1,
  ),
  _Case(
    'chatHistoryProvider',
    chatHistoryProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    seed: () => HiveService.instance.coachBox.put('coach_seed', {
      'user_message': 'hello coach',
      'ai_response': 'hello',
      'created_at': DateTime.now().toIso8601String(),
    }),
    isSeeded: (v) => v is List && v.isNotEmpty,
  ),
  _Case(
    'messageLimitProvider',
    messageLimitProvider,
    isEmpty: (v) => v == 0,
    seed: () => HiveService.instance.userBox.put('msg_count_$_today', 3),
    isSeeded: (v) => v == 3,
  ),
  _Case(
    'templatesProvider',
    templatesProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    seed: () => HiveService.instance.workoutBox
        .put('tmpl_seed', {'type': 'template', 'name': 'Seed template'}),
    isSeeded: (v) => v is List && v.length == 1,
  ),

  // ── the twenty the B-pass found (read through a repository or a
  //    `hive.<box>` alias, so the first grep missed them) ───────────────────
  _Case(
    'userProfileProvider',
    userProfileProvider,
    isEmpty: (v) => v is Map && v.isEmpty,
    seed: () => _profile({'name': 'Tester', 'primary_goal': 'build_muscle'}),
    isSeeded: (v) => v is Map && v['name'] == 'Tester',
  ),
  _Case(
    'userStatsProvider',
    userStatsProvider,
    isEmpty: (v) =>
        v is UserStatsData &&
        v.totalWorkouts == 0 &&
        v.currentWeight == 0 &&
        v.bmi == 0 &&
        v.currentStreak == 0 &&
        v.currentPhase == 1 &&
        v.currentWeek == 1 &&
        v.holdOrdinal == null &&
        v.primaryGoal == '' &&
        v.isPro == false,
    seed: () => _profile({'name': 'Tester', 'primary_goal': 'build_muscle'}),
    isSeeded: (v) => v is UserStatsData && v.primaryGoal != '',
  ),
  _Case(
    'calendarWeekProvider',
    calendarWeekProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    isSeeded: (v) => v is List && v.length == 7,
  ),
  _Case(
    'streakProvider',
    streakProvider,
    isEmpty: (v) => v == 0,
    seed: () => HiveService.instance.workoutBox.put('schedule_$_today', {
      'date': _today,
      'status': 'completed',
      'completed': true,
    }),
    isSeeded: (v) => v is int && v >= 1,
  ),
  _Case(
    'streakFreezeProvider',
    streakFreezeProvider,
    isEmpty: (v) => v == 0,
    isSeeded: (v) => v is int && v >= 1,
  ),
  _Case(
    'nutritionSummaryProvider',
    nutritionSummaryProvider,
    isEmpty: (v) =>
        v is NutritionSummaryData &&
        v.calories == 0 &&
        v.protein == 0 &&
        v.carbs == 0 &&
        v.fat == 0 &&
        v.calorieTarget == 2000 &&
        v.proteinTarget == 120 &&
        v.carbTarget == 250 &&
        v.fatTarget == 65,
    seed: () => _profile({
      'daily_calories': 2100,
      'protein_grams': 150,
      'carb_grams': 200,
      'fat_grams': 60,
    }),
    isSeeded: (v) => v is NutritionSummaryData && v.calorieTarget == 2100,
  ),
  _Case(
    'weightHistoryProvider',
    weightHistoryProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    seed: () => HiveService.instance.healthBox.put('weight_$_today', {
      'date': _today,
      'type': 'weight_log',
      'weight_kg': 70.0,
    }),
    isSeeded: (v) => v is List && v.length == 1,
  ),
  _Case(
    'recentFoodLogsProvider',
    recentFoodLogsProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    seed: () => HiveService.instance.nutritionBox.put('nlog_recent', {
      'date': _today,
      'meal_type': 'lunch',
      'items': [
        {'name': 'Dal', 'calories': 200.0},
      ],
      'total_calories': 200.0,
    }),
    isSeeded: (v) => v is List && v.isNotEmpty,
  ),
  _Case(
    'todayStepsProvider',
    todayStepsProvider,
    isEmpty: (v) => v == 0,
    seed: () => HiveService.instance.healthBox.put('steps_today_x', {
      'date': _today,
      'type': 'step_log',
      'steps': 1234,
    }),
    isSeeded: (v) => v == 1234,
  ),
  _Case(
    'allExercisePRsProvider',
    allExercisePRsProvider,
    isEmpty: (v) => v is List && v.isEmpty,
    seed: () => HiveService.instance.workoutBox.put('exlog_${_today}_aaaa0001', {
      'exercise_name': 'Bench Press',
      'weight_kg': 80.0,
      'reps_completed': 5,
      'set_number': 1,
      'date': _today,
      'logging_type': 'weight_reps',
    }),
    isSeeded: (v) => v is List && v.isNotEmpty,
  ),
  _Case(
    'macroTargetsProvider',
    macroTargetsProvider,
    isEmpty: (v) =>
        v is Map &&
        v.length == 6 &&
        v['bmr'] == 0 &&
        v['tdee'] == 0 &&
        v['calories'] == 2400 &&
        v['protein'] == 184 &&
        v['carbs'] == 280 &&
        v['fat'] == 80 &&
        !v.containsKey('strategy_index'),
    seed: () => _profile({
      'daily_calories': 2100,
      'protein_grams': 150,
      'carb_grams': 200,
      'fat_grams': 60,
    }),
    isSeeded: (v) => v is Map && v['calories'] == 2100,
  ),
  _Case(
    'waterTargetProvider',
    waterTargetProvider,
    isEmpty: (v) => v == WaterTargetService.floorMl,
    seed: () => HiveService.instance.userBox
        .put('water_target_override_ml', WaterTargetService.floorMl + 500),
    isSeeded: (v) => v == WaterTargetService.floorMl + 500,
  ),
  _Case(
    'weeklyReportDataProvider',
    weeklyReportDataProvider,
    isEmpty: (v) =>
        v is WeeklyReportSeries &&
        v.weight.length == 7 &&
        v.weight.every((x) => x == 0) &&
        v.calories.every((x) => x == 0) &&
        v.protein.every((x) => x == 0) &&
        v.workouts.every((x) => x == 0),
    seed: () => HiveService.instance.healthBox.put('weight_$_today', {
      'date': _today,
      'type': 'weight_log',
      'weight_kg': 70.0,
    }),
    isSeeded: (v) => v is WeeklyReportSeries && v.weight.any((x) => x == 70),
  ),
  _Case(
    'coachInsightProvider',
    coachInsightProvider,
    isEmpty: (v) => v == '',
    isSeeded: (v) => v is String && v.isNotEmpty,
  ),
  _Case(
    'currentPlanProvider',
    currentPlanProvider,
    isEmpty: (v) => v is CurrentPlanData && !v.hasPlan && v.phase == 1,
    seed: () => HiveService.instance.userBox
        .put('progress', {'current_phase': 2, 'current_week': 1}),
    isSeeded: (v) => v is CurrentPlanData && v.phase == 2,
  ),
  _Case(
    'workoutStatsProvider',
    workoutStatsProvider,
    isEmpty: (v) => v is Map && v.isEmpty,
    seed: () => HiveService.instance.workoutBox.put('exlog_${_today}_aaaa0002', {
      'exercise_name': 'Bench Press',
      'weight_kg': 80.0,
    }),
    isSeeded: (v) => v is Map && (v['bench'] as Map?)?['current'] == 80.0,
  ),
  _Case(
    'graduationStatsProvider',
    graduationStatsProvider,
    isEmpty: (v) =>
        v is GraduationStatsData &&
        v.totalWorkouts == 0 &&
        v.streakWeeks == 0 &&
        v.totalSets == 0 &&
        v.personalRecords == 0 &&
        v.topPrs.isEmpty,
    seed: () => HiveService.instance.userBox
        .put('progress', {'total_workouts_done': 7, 'current_streak_weeks': 3}),
    isSeeded: (v) =>
        v is GraduationStatsData && v.totalWorkouts == 7 && v.streakWeeks == 3,
  ),

  _Case(
    'dietServingViewProvider',
    dietServingViewProvider,
    isEmpty: (v) => v == DietServingView.portions,
    seed: () => _profile({'diet_serving_view': 'grams'}),
    isSeeded: (v) => v == DietServingView.grams,
  ),
  _Case(
    'dietSupplementsInputsProvider',
    dietSupplementsInputsProvider,
    isEmpty: (v) =>
        (v as SupplementInputs).switchValue == null &&
        v.dob == null,
    seed: () =>
        _profile({'diet_supplements': true, 'date_of_birth': '1990-01-01'}),
    isSeeded: (v) => (v as SupplementInputs).switchValue == true,
  ),
  _Case(
    'dietPlanProvider',
    dietPlanProvider,
    isEmpty: (v) => v is Map && v.isEmpty,
    // The user's own plan is in userBox; a DIFFERENT legacy plan sits in the
    // shared configBox (MigratedKey.read falls back to it whenever the user
    // box cannot answer, which is exactly the signed-out window: without the
    // guard the provider would serve that other plan's hints).
    seed: () async {
      await UserRepository.instance.saveDietPlan(_dietPlan('Lunch'));
      await HiveService.instance.configBox
          .put('saved_diet_plan', _dietPlan('Dinner'));
    },
    isSeeded: (v) => v is Map && v.containsKey('lunch'),
  ),

  // `Provider.family` is NOT an AsyncValue: a throw in these builds is an
  // uncaught provider error like any other. A fixed Monday stands in for the
  // screen's week.
  _Case(
    'daySwapWeekProvider',
    daySwapWeekProvider('2026-11-23'),
    isEmpty: (v) => v is List && v.isEmpty,
    isSeeded: (v) => v is List && v.length == 7,
  ),
  _Case(
    'daySwapAllowanceProvider',
    daySwapAllowanceProvider('2026-11-23'),
    isEmpty: (v) => v is DayAllowance && v.used == 0 && v.limit == 1,
    seed: () => HiveService.instance.userBox.put('day_swap_allowance', {
      '2026-11-23': {'used': 1, 'limit': 3, 'pro': false},
    }),
    isSeeded: (v) => v is DayAllowance && v.used == 1,
  ),

  // ── downstream: they only watch one of the above, so they stop throwing
  //    once it serves its empty value (any value is fine, no error is not) ───
  _Case('userGreetingProvider', userGreetingProvider),
  _Case('userFirstNameProvider', userFirstNameProvider),
  _Case('userInitialProvider', userInitialProvider),
  _Case('profileCompletenessProvider', profileCompletenessProvider),

  // ── measured NOT throwing before this change (controls) ──────────────────
  _Case('onboardingProvider', onboardingProvider),
  _Case('streakFreezeMaxProvider', streakFreezeMaxProvider),
  _Case('subscriptionExpiryBannerProvider', subscriptionExpiryBannerProvider),
  _Case('dailyQuoteProvider', dailyQuoteProvider),
  _Case('waterUnitProvider', waterUnitProvider),
  _Case('aiTextLogRemainingProvider', aiTextLogRemainingProvider),
  _Case('scanMealRemainingProvider', scanMealRemainingProvider),
  _Case('cartAuditorRemainingProvider', cartAuditorRemainingProvider),
  _Case('subscriptionInfoProvider', subscriptionInfoProvider),
  _Case('usageWeeksProvider', usageWeeksProvider),
  _Case('firstReportViewedProvider', firstReportViewedProvider),
  _Case('measurementPromptProvider', measurementPromptProvider),
  _Case('promotionHistoryProvider', promotionHistoryProvider),
  _Case('bodyMeasurementsProvider', bodyMeasurementsProvider),
  _Case('measurementsEnabledProvider', measurementsEnabledProvider),
  _Case('referrerSummaryProvider', referrerSummaryProvider),
  _Case('referralEligibilityProvider', referralEligibilityProvider),
  _Case('notificationsInboxProvider', notificationsInboxProvider),
  _Case('predictionProvider', predictionProvider),
  _Case('pendingLogActionsProvider', pendingLogActionsProvider),
  _Case('pendingToolIntentsProvider', pendingToolIntentsProvider),
  _Case('selectedWeekProvider', selectedWeekProvider),
  _Case('activeWorkoutProvider', activeWorkoutProvider),
  // Providers that do NOT watch the token themselves (they watch a guarded
  // provider, or read a box straight): the token-site count cannot see them.
  _Case('contextualPromptsProvider', contextualPromptsProvider),
  _Case('holdStatusProvider', holdStatusProvider),
  _Case('weekIdentityProvider', weekIdentityProvider),
  _Case(
    'streakWarningEligibilityProvider',
    streakWarningEligibilityProvider,
    isEmpty: (v) =>
        v is StreakWarningEligibility &&
        !v.shouldShow &&
        v.medianWorkoutHour == 19 &&
        !v.isWorkoutDayToday &&
        !v.isTodayCompleted,
    seed: () => HiveService.instance.workoutBox.put('schedule_$_today', {
      'date': _today,
      'type': 'workout',
      'status': 'planned',
    }),
    isSeeded: (v) => v is StreakWarningEligibility && v.isWorkoutDayToday,
  ),
  // State types are nullable: typed closures (see _Case.listen).
  _Case(
    'todayWorkoutProvider',
    null,
    isEmpty: (v) => v == null,
    seed: () => HiveService.instance.workoutBox.put('schedule_$_today', {
      'date': _today,
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Push',
    }),
    isSeeded: (v) => v is Map && v['workout_name'] == 'Push',
    listen: (c, onError) => c.listen(todayWorkoutProvider, (_, _) {},
        onError: (e, _) => onError(e)),
    read: (c) => c.read(todayWorkoutProvider),
  ),
  _Case(
    'aiInsightProvider',
    null,
    listen: (c, onError) =>
        c.listen(aiInsightProvider, (_, _) {}, onError: (e, _) => onError(e)),
    read: (c) => c.read(aiInsightProvider),
  ),
  _Case(
    'referralCreditNoticeProvider',
    null,
    listen: (c, onError) => c.listen(referralCreditNoticeProvider, (_, _) {},
        onError: (e, _) => onError(e)),
    read: (c) => c.read(referralCreditNoticeProvider),
  ),
  _Case(
    'workoutDraftProvider',
    null,
    listen: (c, onError) => c.listen(workoutDraftProvider, (_, _) {},
        onError: (e, _) => onError(e)),
    read: (c) => c.read(workoutDraftProvider),
  ),
];

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('the test seam gives a signed-in session a real token (not <anon>)', () {
    final c = makeContainer();
    expect(c.read(authUserIdTokenProvider), kTestUserId);
  });

  /// COMPLETENESS TRIPWIRE. The case list above is hand-written, so a provider
  /// added later that watches the token would silently join no case. The count
  /// of mentions of `authUserIdTokenProvider` per file (any spelling, comment
  /// and import lines excluded) is pinned: adding or removing one fails here
  /// until this file's case list (and the number) is updated on purpose. The
  /// number alone is not enough: when it moves, ASK whether the new mention
  /// is a provider whose build() reads a box, and give it a case. Residue,
  /// stated: a provider that reads a raw box and never mentions the token
  /// (it then never rebuilds at sign-out on its own) is not seen here.
  test('every token-watching site in lib/ is accounted for', () {
    final re = RegExp(r'\bauthUserIdTokenProvider\b');
    final counts = <String, int>{};
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      var n = 0;
      for (final line in e.readAsLinesSync()) {
        final t = line.trimLeft();
        if (t.startsWith('import ') || t.startsWith('//')) continue;
        n += re.allMatches(line).length;
      }
      if (n > 0) counts[e.path] = n;
    }
    expect(counts, _kTokenWatchSites,
        reason: 'a mention of authUserIdTokenProvider was added or removed: '
            'if it is a provider whose build() reads a box, add it to '
            '_cases() (guarded + seeded, or a control); then update '
            '_kTokenWatchSites');
  });

  for (final k in _cases()) {
    for (final window in const [
      'A: Hive closed, auth user still set',
      'B: Hive closed and auth user gone',
      'C: auth user and Hive owner disagree (account swap)',
    ]) {
      test('${k.name} - sign-out window $window', () async {
        if (k.seed != null) await k.seed!();
        final c = makeContainer();
        final errors = <Object>[];
        // A listener is what makes Riverpod rebuild the provider (the screens
        // that watch it); onError is where the unguarded build() threw.
        if (k.listen != null) {
          k.listen!(c, errors.add);
        } else {
          c.listen(k.provider, (_, _) {}, onError: (e, _) => errors.add(e));
        }
        Object? readIt() => k.read != null ? k.read!(c) : c.read(k.provider);

        // Signed in: the real value (or, with no seed, no error).
        final signedIn = readIt();
        if (k.isSeeded != null) {
          expect(k.isSeeded!(signedIn), isTrue,
              reason: 'signed in, the provider must read the real data');
        }

        // Sign-out, in the app's own order (auth_provider.dart signOut): Hive
        // teardown FIRST, the auth user LAST.
        switch (window[0]) {
          case 'A':
            debugAuthUidResolverForTests = () => kTestUserId;
            await HiveUserSession.closeAll();
          case 'B':
            debugAuthUidResolverForTests = () => null;
            await HiveUserSession.closeAll();
          default: // C: another account's Hive session is open
            debugAuthUidResolverForTests = () => kTestUserId;
            await HiveUserSession.closeAll();
            await HiveUserSession.openForUser(_otherUser);
        }
        // `closeAll` awaits each box close BEFORE it clears the owner, so a
        // rebuild inside that gap reads a closed box (HiveError 'Box not found')
        // with the owner still set: a separate defect in hive_user_session.dart
        // (see the diagnose's "Not fixed here" and its OI), not what this test
        // pins. Errors are collected from the moment the session is gone.
        errors.clear();
        await Future<void>.delayed(Duration.zero);

        expect(errors, isEmpty,
            reason: 'build() must not throw while the session is closed or '
                'belongs to another account (this is the Crashlytics crash)');
        final signedOut = readIt();
        if (k.isEmpty != null) {
          expect(k.isEmpty!(signedOut), isTrue,
              reason: 'signed out, the provider serves its empty value');
        }

        // Sign back in as the same user: Layer B must re-run build() with data.
        await HiveUserSession.closeAll();
        debugAuthUidResolverForTests = () => HiveUserSession.currentOwnerFullId;
        await HiveUserSession.openForUser(kTestUserId);
        await Future<void>.delayed(Duration.zero);

        expect(errors, isEmpty);
        final again = readIt();
        if (k.isSeeded != null) {
          expect(k.isSeeded!(again), isTrue,
              reason: 'once the token flips back the real data returns');
        }
      });
    }
  }
}
