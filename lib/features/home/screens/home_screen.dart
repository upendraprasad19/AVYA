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
import '../widgets/pr_snapshot.dart';
import '../widgets/recent_food_logs.dart';
import '../widgets/swap_sheet.dart';
import '../widgets/water_quick_sheet.dart';
import '../widgets/weight_log_sheet.dart';
import '../widgets/weight_sparkline.dart';
import 'package:icanbefitter/shared/widgets/streak_warning_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Brief loading shimmer on first build before Hive data is read.
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
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
            child: Text(
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
          // Streak badge
          StreakBadge(weeks: streak),
        ],
      ),
    );
  }

  // -- Streak Warning -------------------------------------------------

  Widget _buildStreakWarning(WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    // Only show on day 6-7 of week when streak is active
    // Use a simple heuristic: if streak > 0 and it's Sat/Sun
    final dayOfWeek = DateTime.now().weekday;
    if (streak == 0 || dayOfWeek < 6) return const SizedBox.shrink();

    return StreakWarningBanner(
      streakWeeks: streak,
      workoutsRemaining: 1,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Row(
        children: [
          QuickActionButton(
            icon: Icons.fitness_center,
            label: 'Workout',
            initiallyActive: true,
            onTap: () => context.go('/train'),
          ),
          const SizedBox(width: 7),
          QuickActionButton(
            icon: Icons.restaurant,
            label: 'Meals',
            onTap: () => context.go('/nutrition'),
          ),
          const SizedBox(width: 7),
          QuickActionButton(
            icon: Icons.water_drop_outlined,
            label: 'Water',
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
    final isRestDay = type != 'workout';
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
    final weights = ref.watch(weightHistoryProvider);
    return WeightSparkline(weights: weights);
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
