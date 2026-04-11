import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import '../providers/home_provider.dart';
import '../widgets/streak_badge.dart';
import '../widgets/weekly_calendar.dart';
import '../widgets/day_detail_sheet.dart';
import '../widgets/quick_action_button.dart';
import '../widgets/quote_card.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/today_workout_card.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_sheet.dart';
import '../widgets/pr_snapshot.dart';
import '../widgets/recent_food_logs.dart';
import '../widgets/swap_sheet.dart';
import '../widgets/water_quick_sheet.dart';
import '../widgets/weight_log_sheet.dart';
import '../widgets/weight_sparkline.dart';
import 'package:icanbefitter/shared/widgets/streak_warning_banner.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isLoading = true;
  String? _error;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitialized) {
      // Refresh name/greeting when user returns to home tab (e.g. after
      // editing profile). These providers are cheap Hive reads.
      ref.invalidate(userFirstNameProvider);
      ref.invalidate(userInitialProvider);
      ref.invalidate(userGreetingProvider);
    }
    _hasInitialized = true;
  }

  @override
  void initState() {
    super.initState();
    // Brief loading shimmer on first build before Hive data is read.
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
      // Check if a streak freeze was just consumed and notify the user
      _checkStreakFreezeUsed();
    });
    // After background sync completes (~5s), re-read step data from Hive.
    // HealthSyncService writes steps asynchronously — this ensures the UI
    // picks up the data once it's available.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) ref.invalidate(todayStepsProvider);
    });
  }

  // Bug #14 — Prediction polling moved to ProfileScreen alongside the
  // Future Prediction card. Home no longer renders the prediction.

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
          style: GoogleFonts.getFont('DM Sans', fontSize: 13, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.blue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    });
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    ref.invalidate(userFirstNameProvider);
    ref.invalidate(userInitialProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(weightHistoryProvider);
    ref.invalidate(aiInsightProvider);
    ref.invalidate(recentFoodLogsProvider);
    ref.invalidate(dailyQuoteProvider);
    ref.invalidate(todayStepsProvider);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
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
        _buildHeader(ref),
        _buildDateDisplay(),
        _buildStreakWarning(ref),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: WeeklyCalendar(
            onDayTap: (date, schedule) {
              DayDetailSheet.show(
                context,
                date: date,
                schedule: schedule,
              );
            },
            onDayLongPress: (date, schedule) {
              SwapSheet.show(context, sourceDate: date);
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
        // AI Coach insight
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

  // -- Header ---------------------------------------------------------

  Widget _buildHeader(WidgetRef ref) {
    final firstName = ref.watch(userFirstNameProvider);
    final initial = ref.watch(userInitialProvider);
    final streak = ref.watch(streakProvider);
    final profile = ref.watch(userProfileProvider);
    final avatarUrl = profile['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 14, AppSpacing.screenPadding, 10),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      avatarUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, err, stack) => Text(
                        initial,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  )
                : Text(
                    initial,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // Welcome text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WELCOME BACK,',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '$firstName \u{1F44B}',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Streak badge with freeze count
          StreakBadge(
            days: streak,
            freezesAvailable: ref.watch(streakFreezeProvider),
          ),
        ],
      ),
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

  // -- Date Display ---------------------------------------------------

  Widget _buildDateDisplay() {
    final now = DateTime.now();
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthNames = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];

    final dayName = dayNames[now.weekday - 1];
    final dateNum = now.day.toString();
    final monthName = monthNames[now.month - 1];

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: dayName,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
                height: 1,
              ),
            ),
            TextSpan(
              text: ' $dateNum ',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: AppColors.border,
                height: 1,
              ),
            ),
            TextSpan(
              text: monthName,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Quick Actions --------------------------------------------------

  Widget _buildQuickActions(BuildContext context) {
    final schedule = ref.watch(todayWorkoutProvider);
    final nutrition = ref.watch(nutritionSummaryProvider);
    final waterMl = ref.watch(waterIntakeProvider);
    final weightLogged = ref.watch(todayWeightLoggedProvider);

    // Workout: only mark done when the user actually completed it.
    // Rest days stay idle — showing green on a rest day is misleading.
    final workoutStatus = schedule?['status'] as String? ?? 'planned';
    final workoutDone = workoutStatus == 'completed';

    // Meals: both calories AND protein must hit target
    final proteinProgress = nutrition.proteinTarget > 0
        ? nutrition.protein / nutrition.proteinTarget
        : 0.0;
    final calorieProgress = nutrition.calorieTarget > 0
        ? nutrition.calories / nutrition.calorieTarget
        : 0.0;
    final mealsDone = proteinProgress >= 1.0 && calorieProgress >= 1.0;

    // Water: progress toward 3L goal
    const waterGoalMl = 3000;
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
            progressColor: AppColors.blue,
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

  // -- Section Label --------------------------------------------------

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 12, AppSpacing.screenPadding, 8),
      child: Text(
        text,
        style: AppTypography.label,
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

    final type = schedule?['type'] as String? ?? 'rest';
    final status = schedule?['status'] as String? ?? 'planned';
    final isRestDay = type != 'workout' && type != 'custom_template';
    final isCompleted = status == 'completed';
    final workoutName = schedule?['workout_name'] as String? ?? 'Rest Day';
    final exercises = schedule?['exercises'] as List? ?? [];
    final week = schedule?['week'] as int? ?? 1;

    if (isRestDay) {
      return TodayWorkoutCard(
        workoutTag: 'REST DAY \u00B7 WEEK $week',
        workoutName: 'RECOVERY\n& MOBILITY',
        durationMin: 0,
        exerciseCount: 0,
        isRestDay: true,
        onStart: () {},
        caloriesCurrent: nutrition.calories,
        caloriesTarget: nutrition.calorieTarget,
        proteinCurrent: nutrition.protein,
        proteinTarget: nutrition.proteinTarget,
        steps: ref.watch(todayStepsProvider),
        stepsGoal: 10000,
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
        workoutTag: '${workoutName.toUpperCase()} \u00B7 PHASE 1',
        workoutName: workoutName.toUpperCase(),
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
        stepsGoal: 10000,
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
      workoutTag: '${workoutName.toUpperCase()} \u00B7 PHASE 1',
      workoutName: workoutName.toUpperCase(),
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
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
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
    return WeightSparkline(
      entries: entries
          .map((e) => WeightEntry(date: e.date, weight: e.weight))
          .toList(),
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
