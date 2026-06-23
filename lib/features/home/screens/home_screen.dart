import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/mixins/hive_tab_scaffold.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/shared/widgets/weight_trend_chart.dart';
import 'package:icanbefitter/shared/widgets/pwa_install/pwa_install_banner.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/sync_banner.dart';
import '../widgets/completeness_nudge.dart';
import '../providers/home_provider.dart';
import '../../train/providers/train_provider.dart';
import '../widgets/weekly_calendar.dart';
import '../widgets/day_detail_sheet.dart';
import '../widgets/quick_action_button.dart';
import '../widgets/profile_nudge_card.dart';
import '../widgets/quote_card.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/today_workout_card.dart';
import '../widgets/streak_explainer_sheet.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/widgets/plan_expired_card.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_sheet.dart';
import '../widgets/pr_snapshot.dart';
import '../widgets/recent_food_logs.dart';
import '../widgets/swap_sheet.dart';
import '../widgets/water_quick_sheet.dart';
import '../widgets/weight_log_sheet.dart';
import 'package:icanbefitter/shared/widgets/streak_warning_banner.dart';
import 'package:icanbefitter/shared/widgets/subscription_expiry_banner.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/profile/screens/promotion_celebration_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with HiveTabScaffoldMixin<HomeScreen>, WidgetsBindingObserver {
  String? _error;
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Obs 4 (2026-06-05): when a background restore + heals complete, refresh
    // the home cards from the now-updated Hive (offline-first background-restore
    // — the user reached home before the cloud restore finished).
    SyncService.instance.restoreCompletedTick.addListener(_onRestoreTick);
  }

  void _onRestoreTick() {
    if (mounted) invalidateOnRetry(ref);
  }

  @override
  void dispose() {
    SyncService.instance.restoreCompletedTick.removeListener(_onRestoreTick);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Theme B (diagnose 2026-05-22 9aa2c1) — pending promotion may have
    // been stamped while the app was paused (e.g. background sync ran
    // RankService.evaluateAndPromote). Check on resume so the celebration
    // surfaces the next time the user returns to the app.
    if (state == AppLifecycleState.resumed) {
      _maybeShowPendingPromotion();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitialized) {
      // Refresh name/greeting when user returns to home tab (e.g. after
      // editing profile). These providers are cheap Hive reads.
      ref.invalidate(userFirstNameProvider);
      ref.invalidate(userInitialProvider);
      ref.invalidate(userGreetingProvider);
      // Test #10 obs 1 — refresh time-of-day too so hour rollover
      // (e.g. 11:55 → 12:05) updates the eyebrow on the next visit.
      ref.invalidate(userTimeOfDayProvider);
    }
    _hasInitialized = true;
  }

  // initState owned by HiveTabScaffoldMixin (microtask + isLoading flip).
  // First-mount-only side effects (streak-freeze toast, health-sync await)
  // live in initTab() below.
  @override
  Future<void> initTab() async {
    // Check if a streak freeze was just consumed and notify the user.
    _checkStreakFreezeUsed();
    // Theme B — check pending promotion celebration on first mount.
    _maybeShowPendingPromotion();
    // Wait for background health sync to finish, then refresh step/weight
    // providers. This replaces the old fixed 5-second delay which was a
    // race condition — health sync could take longer than 5s or finish
    // much sooner. The future completes as soon as Health Connect data
    // has been written to Hive (or immediately if sync is disabled).
    // Fire-and-forget — don't await; mixin flips isLoading regardless.
    unawaited(SyncService.instance.healthSyncDone.then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.invalidate(todayStepsProvider);
          ref.invalidate(weightHistoryProvider);
          ref.invalidate(todayWeightLoggedProvider);
        }
      });
    }));
  }

  @override
  void invalidateOnRetry(WidgetRef ref) {
    ref.invalidate(userFirstNameProvider);
    ref.invalidate(userInitialProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(streakFreezeProvider); // Phase 2 — freeze denominator reactive
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(todayWorkoutProvider);
    // Train-tab plan providers too, so a bg-restore heal reaches the Train
    // screen (review P2 2026-06-06).
    ref.invalidate(currentPlanProvider);
    ref.invalidate(selectedWeekProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(weightHistoryProvider);
    ref.invalidate(aiInsightProvider);
    ref.invalidate(recentFoodLogsProvider);
    ref.invalidate(dailyQuoteProvider);
    ref.invalidate(todayStepsProvider);
  }

  // Bug #14 — Prediction polling moved to ProfileScreen alongside the
  // Future Prediction card. Home no longer renders the prediction.

  /// Theme B (diagnose 2026-05-22 9aa2c1) — pending promotion celebration.
  ///
  /// RankService.evaluateAndPromote stamps userBox['pending_promotion_rank_code']
  /// (a top-level Hive key, NOT inside the progress map) whenever a real
  /// rank change is detected and persisted to cloud. This handler reads
  /// + clears the slot and pushes the pre-existing
  /// PromotionCelebrationScreen as a full-screen modal route. Survives
  /// hot restart because the slot is durable Hive. Idempotent — only one
  /// modal per stamp because clearPendingPromotionRankCode fires
  /// immediately after read.
  void _maybeShowPendingPromotion() {
    if (!mounted) return;
    final rankCode = UserRepository.instance.getPendingPromotionRankCode();
    if (rankCode == null) return;
    // Clear the slot BEFORE pushing the modal — guards against re-fire
    // if the user backgrounds the app mid-celebration (didChangeApp
    // LifecycleState fires again on resume).
    unawaited(UserRepository.instance.clearPendingPromotionRankCode());
    unawaited(ErrorTelemetry.logEvent('rank_promotion_celebration_shown',
        message: 'rank_code=$rankCode'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            PromotionCelebrationScreen(newRankCode: rankCode),
      ));
    });
  }

  void _checkStreakFreezeUsed() {
    final progress = UserRepository.instance.getProgress();
    if (progress == null) return;
    final justUsed = progress['streak_freeze_just_used'] as bool? ?? false;
    if (!justUsed) return;
    final remaining = (progress['streak_freeze_remaining_after_use'] as int?) ?? 0;
    // Clear the flag
    UserRepository.instance.updateProgress({'streak_freeze_just_used': false});
    // Show toast
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Streak Freeze used! $remaining remaining this week.',
          style: AppTypography.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.info,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    });
  }

  void _retry() {
    // Wraps mixin's retry() to also clear local _error state. Retained as a
    // named method so existing onRetry: _retry call sites don't change.
    setState(() => _error = null);
    retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        padBottom: 0,
        child: SafeArea(
          child: Column(
            children: [
              const SyncBanner(),
              const CompletenessNudge(),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: _buildBody(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading || isSessionTearingDown) {
      return const ScreenLoadingSkeleton(cardCount: 5);
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: ErrorState(
          title: 'Failed to load dashboard',
          subtitle: _error,
          onRetry: _retry,
        ),
      );
    }

    try {
      return _buildContent();
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('home_build_content_failed',
          message: clipped));
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: ErrorState(
          title: 'Something went wrong',
          subtitle: 'Tap to retry',
          onRetry: _retry,
        ),
      );
    }
  }

  Widget _buildContent() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Test #10 obs 1 — Home header compacted to 2 rows + 1 hairline.
        // Row 1 keeps the dense `DAILY · DATE · WK · PHASE` eyebrow with
        // anchor glyph. Row 2 collapses the old standalone greeting + the
        // standalone streak pill into a single horizontal row: avatar |
        // (`GOOD EVENING,` mono eyebrow over `AVYAANSH 👋` Fraunces name,
        // stack height = 44dp avatar) | streak pill inline-right.
        Builder(builder: (_) {
          final initial = ref.watch(userInitialProvider);
          final firstName = ref.watch(userFirstNameProvider);
          final timeOfDay = ref.watch(userTimeOfDayProvider);
          final streak = ref.watch(streakProvider);
          final freezes = ref.watch(streakFreezeProvider);
          final profile = ref.watch(userProfileProvider);
          final avatarUrl = profile['avatar_url'] as String?;
          final now = DateTime.now();
          const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
          const monthShort = [
            'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
            'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
          ];
          final weekInPhase =
              WorkoutScheduleService.instance.getCurrentWeekNumber();
          final progress = UserRepository.instance.getProgress() ?? {};
          final currentPhase = (progress['current_phase'] as int?) ?? 1;
          final eyebrow =
              'DAILY · ${weekdays[now.weekday - 1]} ${now.day} '
              '${monthShort[now.month - 1]} · WK $weekInPhase '
              '· PHASE $currentPhase';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ROW 1 — full-width eyebrow with all meta (unchanged)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AnchorGlyph(size: 12),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        eyebrow,
                        style: AppTypography.monoXs.copyWith(
                          color: AppColors.accent,
                          letterSpacing: 3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // ROW 2 — avatar + (greeting/name stack) + streak pill inline
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    WardAvatar(
                      initial: initial,
                      size: 44,
                      image: (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? NetworkImage(avatarUrl)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$timeOfDay,',
                              style: AppTypography.mono.copyWith(
                                fontSize: 10,
                                color: AppColors.accent,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // Obs 2 sweep (2026-06-02) — a long first name + the
                            // streak pill on the right could clip the greeting
                            // ("Upendra 👋" fits, longer names didn't). Shrink-
                            // to-fit instead of truncating, same as the Train /
                            // Nutrition titles.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: firstName),
                                    const TextSpan(
                                      text: ' \u{1F44B}',
                                      style: TextStyle(
                                        fontFamily: 'DM Sans',
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                style: AppTypography.h1.copyWith(
                                  fontSize: 22,
                                  height: 1.1,
                                  letterSpacing: -0.4,
                                ),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => StreakExplainerSheet.show(
                        context,
                        freezesAvailable: freezes,
                        isPro: SubscriptionService.instance.isPro(),
                      ),
                      child: WardStatusStrip(
                        streakDays: streak,
                        freezesAvailable: freezes,
                        freezesMax: ref.watch(streakFreezeMaxProvider),
                      ),
                    ),
                  ],
                ),
              ),
              // Single gold rule closes the header
              Container(
                height: 1,
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                color: AppColors.accent.withValues(alpha: 0.33),
              ),
            ],
          );
        }),
        _buildStreakWarning(ref),
        _buildExpiryBanner(ref),
        // Unit 3 obs 6 — web-only "Add to Home Screen" prompt (kIsWeb-gated
        // inside the widget; SizedBox.shrink on Android/iOS + when not
        // installable). Below the safety banners, above the calendar.
        const PwaInstallBanner(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: WeeklyCalendar(
            onDayTap: (date, schedule) {
              DayDetailSheet.show(
                context,
                date: date,
                schedule: schedule,
              );
            },
            onDayLongPress: (date, schedule) {
              SwapSheet.show(
                context,
                sourceDate: date,
                onSwapComplete: () {
                  // F11 · Invalidate all views that read schedule state so
                  // the swap shows up immediately on Home, Calendar, Plan.
                  ref.invalidate(todayWorkoutProvider);
                  ref.invalidate(currentPlanProvider);
                  ref.invalidate(calendarWeekProvider);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _buildSectionLabel('TODAY'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: _buildTodayRow(context, ref),
        ),
        const SizedBox(height: 10),
        _buildQuickActions(context),
        const SizedBox(height: 10),
        const ProfileNudgeCard(),  // V4: profile completeness nudge
        const SizedBox(height: 10),
        _buildAiCoachEyebrow(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: _buildAiInsight(ref),
        ),
        const SizedBox(height: 10),
        // Bug #14 — Future Prediction card moved to ProfileScreen.
        _buildSectionLabel('WEIGHT TREND'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: _buildWeightSparkline(ref),
        ),
        const SizedBox(height: 10),
        _buildSectionLabel('PERSONAL RECORDS'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: const PrSnapshot(),
        ),
        const SizedBox(height: 10),
        _buildRecentLogsHeader(context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: _buildRecentFoodLogs(ref),
        ),
        const SizedBox(height: 10),
        // Daily quote moved to bottom
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: _buildQuote(ref),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // -- Streak Warning -------------------------------------------------

  Widget _buildStreakWarning(WidgetRef ref) {
    // Bug #12 — Smart streak warning. Eligibility (workout-day check,
    // completion check, personalised time-of-day threshold) is computed
    // by streakWarningEligibilityProvider so the rules stay testable and
    // the home screen only renders the UI.
    final eligibility = ref.watch(streakWarningEligibilityProvider);
    if (!eligibility.shouldShow) {
      return const SizedBox.shrink();
    }

    final streak = ref.watch(streakProvider);
    final calendarWeek = ref.watch(calendarWeekProvider);
    final workoutsPlanned = calendarWeek
        .where((day) => day.status != CalendarDayStatus.rest && day.status != CalendarDayStatus.none)
        .length;
    final workoutsCompleted = calendarWeek
        .where((day) => day.status == CalendarDayStatus.completed)
        .length;
    final workoutsRemaining =
        (workoutsPlanned - workoutsCompleted).clamp(0, workoutsPlanned).toInt();

    return StreakWarningBanner(
      streakDays: streak,
      workoutsRemaining: workoutsRemaining,
      freezesAvailable: ref.watch(streakFreezeProvider),
      onTrainNow: () => context.go('/train'),
    );
  }

  // -- PRO expiry banner (diagnose 2026-06-06) -----------------------

  Widget _buildExpiryBanner(WidgetRef ref) {
    final state = ref.watch(subscriptionExpiryBannerProvider);
    if (!state.show) return const SizedBox.shrink();
    return SubscriptionExpiryBanner(
      severity: state.severity,
      daysLeft: state.daysLeft,
      onRenew: () => showPaywallSheet(context, feature: 'PRO'),
      onDismiss: () => ref
          .read(subscriptionExpiryBannerProvider.notifier)
          .dismissForToday(),
    );
  }


  // -- Quick Actions --------------------------------------------------

  Widget _buildQuickActions(BuildContext context) {
    final schedule = ref.watch(todayWorkoutProvider);
    final nutrition = ref.watch(nutritionSummaryProvider);
    final waterMl = ref.watch(waterIntakeProvider);
    final weightLogged = ref.watch(todayWeightLoggedProvider);

    // Workout: mark done when completed, rest-day when rest, idle otherwise.
    final workoutStatus = schedule?['status'] as String? ?? 'planned';
    final workoutType = schedule?['type'] as String? ?? 'rest';
    final workoutDone = workoutStatus == 'completed';
    final isRestDay = workoutType != 'workout' && workoutType != 'custom_template';

    // Meals: both calories AND protein must hit target
    final proteinProgress = nutrition.proteinTarget > 0
        ? nutrition.protein / nutrition.proteinTarget
        : 0.0;
    final calorieProgress = nutrition.calorieTarget > 0
        ? nutrition.calories / nutrition.calorieTarget
        : 0.0;
    final mealsDone = proteinProgress >= 1.0 && calorieProgress >= 1.0;

    // Water: progress toward user's personal target (WaterTargetService).
    final waterGoalMl = ref.watch(waterTargetProvider);
    final waterProgress = waterMl / waterGoalMl;
    final waterDone = waterMl >= waterGoalMl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Row(
        children: [
          QuickActionButton(
            icon: Icons.fitness_center,
            label: 'Workout',
            state: workoutDone
                ? QuickActionState.completed
                : isRestDay
                    ? QuickActionState.restDay
                    : QuickActionState.idle,
            onTap: () => context.go('/train'),
          ),
          const SizedBox(width: 7),
          QuickActionButton(
            icon: Icons.restaurant,
            label: 'Meals',
            state: mealsDone
                ? QuickActionState.completed
                : QuickActionState.idle,
            progress: proteinProgress,
            progressColor: AppColors.accent,
            onTap: () => context.go('/nutrition'),
          ),
          const SizedBox(width: 7),
          QuickActionButton(
            icon: Icons.water_drop_outlined,
            label: 'Water',
            state: waterDone
                ? QuickActionState.completed
                : QuickActionState.idle,
            progress: waterProgress,
            progressColor: AppColors.info,
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => const WaterQuickSheet(),
            ),
          ),
          const SizedBox(width: 7),
          QuickActionButton(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight',
            state: weightLogged
                ? QuickActionState.completed
                : QuickActionState.idle,
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const WeightLogSheet(),
            ),
          ),
        ],
      ),
    );
  }

  // -- AI Coach Eyebrow (green dot + "AI COACH · INSIGHTS") -----------

  Widget _buildAiCoachEyebrow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        8,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.ok,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'AI COACH \u00B7 INSIGHTS',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // -- Section Label --------------------------------------------------

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: WardEyebrow(
        text,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          8,
        ),
      ),
    );
  }

  // -- AI Insight -----------------------------------------------------

  Widget _buildAiInsight(WidgetRef ref) {
    final insight = ref.watch(aiInsightProvider);
    final nutrition = ref.watch(nutritionSummaryProvider);
    final firstName = ref.watch(userFirstNameProvider);

    return AiInsightCard(
      insight: insight,
      userName: firstName,
      proteinCurrent: nutrition.protein,
      proteinTarget: nutrition.proteinTarget,
    );
  }

  // -- Today Row (Workout + Fuel + Steps) -----------------------------

  Widget _buildTodayRow(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(todayWorkoutProvider);
    final nutrition = ref.watch(nutritionSummaryProvider);

    // Day-29 dead-end fix (audit H9): if today has no scheduled entry
    // AND the Phase's plan_end_date has passed, free users see the
    // 3-door PlanExpiredCard (upgrade / template builder / re-do
    // Week 4). PRO users never land here — the app-launch bootstrap
    // auto-generates the next Phase for them before this provider
    // reads. This branch is free-only by construction.
    if (schedule == null &&
        WorkoutScheduleService.instance.isPhaseExpired()) {
      return PlanExpiredCard(
        onRedoComplete: () {
          ref.invalidate(todayWorkoutProvider);
          ref.invalidate(currentPlanProvider);
        },
      );
    }

    final type = schedule?['type'] as String? ?? 'rest';
    final status = schedule?['status'] as String? ?? 'planned';
    final isRestDay = type != 'workout' && type != 'custom_template';
    final isCompleted = status == 'completed';
    final workoutName = schedule?['workout_name'] as String? ?? 'Rest Day';
    final exercises = schedule?['exercises'] as List? ?? [];
    final week = schedule?['week'] as int? ?? 1;

    // Read current phase dynamically from progress (never hardcode phase number)
    final progress = UserRepository.instance.getProgress() ?? {};
    final currentPhase = (progress['current_phase'] as int?) ?? 1;

    // Phase-driven mode label — renders as the italic-gold second line
    // under the Fraunces workout title (handoff: "LEG DAY / _Relaxed_").
    const phaseMode = {
      1: 'Relaxed',
      2: 'Focused',
      3: 'Capacity',
      4: 'Peak',
    };
    final modeLabel = phaseMode[currentPhase] ?? 'Focused';

    if (isRestDay) {
      return TodayWorkoutCard(
        workoutTag: 'PHASE $currentPhase',
        workoutName: 'RECOVERY',
        workoutMode: 'Week $week',
        durationMin: 0,
        exerciseCount: 0,
        isRestDay: true,
        onStart: () {},
        caloriesCurrent: nutrition.calories,
        caloriesTarget: nutrition.calorieTarget,
        proteinCurrent: nutrition.protein,
        proteinTarget: nutrition.proteinTarget,
        steps: ref.watch(todayStepsProvider),
        stepsGoal: AppConstants.defaultDailyStepGoal,
      );
    }

    if (isCompleted) {
      final durationSecs = (schedule?['duration_seconds'] as int?) ?? 0;

      // Compute best lift + volume from exercise logs
      final receiptData = WorkoutReceiptData.fromExerciseLogs(DateTime.now());
      double? volume;
      String? bestLift;
      if (receiptData != null) {
        volume = receiptData.totalVolumeKg;
        // Best lift = exercise with highest weight
        double maxW = 0;
        String maxName = '';
        for (final ex in receiptData.exercises) {
          if (ex.maxWeightKg > maxW) {
            maxW = ex.maxWeightKg;
            maxName = ex.name;
          }
        }
        if (maxW > 0) {
          bestLift = '$maxName ${maxW.toStringAsFixed(0)}kg';
        }
      }

      return TodayWorkoutCard(
        workoutTag: 'PHASE $currentPhase',
        workoutName: workoutName.toUpperCase(),
        workoutMode: modeLabel,
        durationMin: durationSecs > 0 ? (durationSecs / 60).round() : 0,
        exerciseCount: exercises.length,
        isRestDay: false,
        isDone: true,
        totalVolumeKg: volume,
        bestLift: bestLift,
        onViewCard: receiptData != null
            ? () => WorkoutReceiptSheet.show(context, receiptData)
            : null,
        onStart: () {},
        caloriesCurrent: nutrition.calories,
        caloriesTarget: nutrition.calorieTarget,
        proteinCurrent: nutrition.protein,
        proteinTarget: nutrition.proteinTarget,
        steps: ref.watch(todayStepsProvider),
        stepsGoal: AppConstants.defaultDailyStepGoal,
      );
    }

    // Estimate duration: ~2.5 min per set
    int totalSets = 0;
    for (final ex in exercises) {
      if (ex is Map) {
        final sets = (ex['sets'] as int?) ??
            (ex['prescribed_sets'] as int?) ??
            (ex['default_sets'] as int?) ??
            3;
        totalSets += sets;
      }
    }
    final estDuration = totalSets > 0 ? (totalSets * 2.5).round() : 45;

    return TodayWorkoutCard(
      workoutTag: 'PHASE $currentPhase',
      workoutName: workoutName.toUpperCase(),
      workoutMode: modeLabel,
      durationMin: estDuration,
      exerciseCount: exercises.length,
      onStart: () => context.go('/train/active-workout'),
      caloriesCurrent: nutrition.calories,
      caloriesTarget: nutrition.calorieTarget,
      proteinCurrent: nutrition.protein,
      proteinTarget: nutrition.proteinTarget,
      steps: ref.watch(todayStepsProvider),
      stepsGoal: 10000,
    );
  }

  // -- Recent Logs Header ---------------------------------------------

  Widget _buildRecentLogsHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 12, AppSpacing.screenPadding, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'RECENT LOGS',
            style: AppTypography.label,
          ),
          GestureDetector(
            onTap: () => context.go('/nutrition'),
            child: Text(
              'VIEW ALL',
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Quote Card -----------------------------------------------------

  Widget _buildQuote(WidgetRef ref) {
    final quoteData = ref.watch(dailyQuoteProvider);
    return QuoteCard(
      quote: quoteData.quote,
      author: quoteData.author,
    );
  }

  // -- Weight Sparkline -----------------------------------------------

  Widget _buildWeightSparkline(WidgetRef ref) {
    final entries = ref.watch(weightHistoryProvider);
    // Obs 4 (2026-06-02) — the rich date-aware trend chart (range chips +
    // dashed goal line) replaces the old single-line sparkline, which drew a
    // misleading lone dot when only one weigh-in fell in the window. The chart
    // carries the last pre-window point in so a post-gap weigh-in always shows
    // a connecting line.
    final target =
        (UserRepository.instance.getProfile()?['target_weight_kg'] as num?)
                ?.toDouble() ??
            0;
    return WeightTrendChart(
      entries: entries
          .map((e) => WeightTrendPoint(date: e.date, weight: e.weight))
          .toList(),
      targetWeight: target,
      chartHeight: 150,
      onViewFullHistory: () => context.go('/profile/reports'),
    );
  }

  // -- Recent Food Logs -----------------------------------------------

  Widget _buildRecentFoodLogs(WidgetRef ref) {
    final logs = ref.watch(recentFoodLogsProvider);

    return RecentFoodLogs(
      entries: logs
          .map((e) => FoodLogEntry(
                name: e.name,
                protein: e.protein,
                carbs: e.carbs,
                fat: e.fat,
                calories: e.calories,
              ))
          .toList(),
    );
  }
}
