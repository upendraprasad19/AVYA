import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import '../providers/train_provider.dart';
import '../widgets/today_workout_card.dart';
import '../widgets/week_selector.dart';
import '../widgets/expandable_day_card.dart';
import '../widgets/stats_grid.dart';


class TrainScreen extends ConsumerStatefulWidget {
  const TrainScreen({super.key});

  @override
  ConsumerState<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends ConsumerState<TrainScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _retry() {
    setState(() => _isLoading = true);
    ref.invalidate(currentPlanProvider);
    ref.invalidate(selectedWeekProvider);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const ScreenLoadingSkeleton(cardCount: 4),
      );
    }

    try {
      return _buildContent(context);
    } catch (e) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: ErrorState(
              title: 'Failed to load workouts',
              subtitle: 'Tap to retry',
              onRetry: _retry,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final plan = ref.watch(currentPlanProvider);
    final selectedWeek = ref.watch(selectedWeekProvider);
    final weekDays = plan.getWeek(selectedWeek);
    final todayWorkout = plan.todayWorkout;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(plan, selectedWeek),

          // Scrollable content
          Expanded(
            child: !plan.hasPlan
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    child: EmptyState(
                      icon: Icons.fitness_center,
                      title: 'No workout plan yet',
                      subtitle: 'Complete onboarding to generate your personalised plan.',
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Today's workout preview card
                      if (todayWorkout != null)
                        TodayWorkoutCard(
                          workout: todayWorkout,
                          onStart: () {
                            ref
                                .read(activeWorkoutProvider.notifier)
                                .startWorkout(todayWorkout);
                            context.go('/train/active-workout');
                          },
                        ),

                      const SizedBox(height: 12),

                      // SCHEDULE section label
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                        child: Text(
                          'SCHEDULE',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Week selector tabs
                      WeekSelector(
                        totalWeeks: 4,
                        selectedWeek: selectedWeek,
                        onSelect: (week) =>
                            ref.read(selectedWeekProvider.notifier).select(week),
                      ),
                      const SizedBox(height: 10),

                      // Expandable day cards
                      if (weekDays.isEmpty)
                        _buildEmptyWeek()
                      else
                        ...weekDays.asMap().entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: ExpandableDayCard(
                              dayData: entry.value,
                              dayIndex: entry.key,
                              onStartWorkout: () {
                                ref
                                    .read(activeWorkoutProvider.notifier)
                                    .startWorkout(entry.value);
                                context.go('/train/active-workout');
                              },
                            ),
                          );
                        }),

                      const SizedBox(height: 12),

                      // Phase unlock card -- show after week 4
                      if (plan.phase == 1 && plan.hasPlan)
                        _buildPhaseUnlockCard(context, plan, ref),

                      const SizedBox(height: 12),

                      // YOUR STATS section
                      const StatsGrid(),

                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(CurrentPlanData plan, int selectedWeek) {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        decoration: const BoxDecoration(
          color: AppColors.header,
          border: Border(
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WORKOUT',
              textAlign: TextAlign.left,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Phase ${plan.phase} \u00b7 Week $selectedWeek of 4',
              textAlign: TextAlign.left,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseUnlockCard(BuildContext context, CurrentPlanData plan, WidgetRef ref) {
    // Only show if user has reached week 4
    if (plan.currentWeek < 4) return const SizedBox.shrink();

    // Check completion rate for Phase 1 graduation
    final completionRate = _computePhaseCompletionRate(plan);
    final canGraduate = completionRate >= AppConstants.phaseUnlockCompletionRate;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.proGold.withValues(alpha: 0.06),
              AppColors.proGold.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(
            color: AppColors.proGold.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  canGraduate ? Icons.emoji_events : Icons.lock,
                  size: 16,
                  color: AppColors.proGold,
                ),
                const SizedBox(width: 8),
                Text(
                  canGraduate ? 'PHASE 1 COMPLETE!' : 'PHASE 2 AVAILABLE',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.proGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canGraduate
                  ? 'You crushed Phase 1 with ${(completionRate * 100).round()}% completion! View your achievements and unlock Phase 2.'
                  : 'Great progress! Unlock Phase 2 to continue building strength with new exercises and progressive overload.',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                if (canGraduate) {
                  context.go('/train/graduation');
                  return;
                }
                SubscriptionService.instance.gate(
                  AppConstants.featurePhases2To12,
                  onPro: () {
                    context.go('/train/graduation');
                  },
                  onFree: () => showPaywallSheet(
                    context,
                    feature: 'Phases 2-12',
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.proGold,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Center(
                  child: Text(
                    canGraduate ? 'View Your Achievement' : 'Unlock Phase 2',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compute Phase 1 completion rate across all 4 weeks.
  double _computePhaseCompletionRate(CurrentPlanData plan) {
    int totalWorkoutDays = 0;
    int completedDays = 0;

    for (int w = 1; w <= 4; w++) {
      final weekDays = plan.getWeek(w);
      for (final day in weekDays) {
        if (!day.isRest) {
          totalWorkoutDays++;
          if (day.isDone) completedDays++;
        }
      }
    }

    if (totalWorkoutDays == 0) return 0.0;
    return completedDays / totalWorkoutDays;
  }

  Widget _buildEmptyWeek() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: const EmptyState(
        icon: Icons.fitness_center,
        title: 'No workouts scheduled',
        subtitle: 'This week has no workouts in your plan.',
      ),
    );
  }
}
