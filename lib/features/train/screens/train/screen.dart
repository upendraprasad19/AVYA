import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/mixins/hive_tab_scaffold.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import '../../repositories/workout_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import '../../providers/train_provider.dart';
import 'package:icanbefitter/features/home/widgets/weight_log_sheet.dart';
import '../../widgets/create_custom_exercise_sheet.dart';
import '../../widgets/edit_workout_log_sheet.dart';
import '../../widgets/week_selector.dart';
import '../../widgets/stats_grid.dart';
import 'package:icanbefitter/features/home/widgets/streak_explainer_sheet.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';


part 'plan_header.dart';
part 'hero_cards.dart';
part 'week_rows.dart';
part 'expanded_exercises.dart';
part 'planned_expansion.dart';
part 'rest_day_sheet.dart';
part 'exercise_preview_sheet.dart';
part 'phase_unlock_card.dart';
part 'empty_states.dart';
part 'templates_section.dart';
part 'schedule_template.dart';
part 'your_exercises_section.dart';
part 'collapsible_section.dart';

class TrainScreen extends ConsumerStatefulWidget {
  const TrainScreen({super.key});

  @override
  ConsumerState<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends ConsumerState<TrainScreen>
    with HiveTabScaffoldMixin<TrainScreen> {
  @override
  void invalidateOnRetry(WidgetRef ref) {
    ref.invalidate(currentPlanProvider);
    ref.invalidate(selectedWeekProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const ScreenLoadingSkeleton(cardCount: 4),
      );
    }

    try {
      return _buildContent(context);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('train_screen_build_failed',
          message: clipped));
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: ErrorState(
              title: 'Failed to load workouts',
              subtitle: 'Tap to retry',
              onRetry: retry,
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
      body: SafeArea(
        bottom: false,
        child: !plan.hasPlan
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: plan.isGenerating
                    ? _buildGeneratingState()
                    : EmptyState(
                        icon: Icons.fitness_center,
                        title: 'No workout plan yet',
                        subtitle:
                            'Complete onboarding to generate your personalised plan.',
                      ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Plan D D-6 — Train uses _buildPlanHeader as its
                    // letterhead (TRAIN · WK N OF M eyebrow + phase name
                    // Fraunces title + status strip + progress bar).
                    // No WardTabHeader / RankChipFullWidth — rank info lives
                    // on the dedicated /train/roadmap screen per Q10.
                    _buildPlanHeader(plan, selectedWeek, weekDays),

                    const SizedBox(height: 14),

                    // 2. Today's workout hero card
                    // Only show when viewing current week; use currentWeek
                    // data for today-lookup so it's always accurate (W2+W6).
                    if (selectedWeek == plan.currentWeek)
                      _buildTodayHeroCard(context, plan, todayWorkout)
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.screenPadding),
                        child: WardCard(
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 16, color: AppColors.textDim),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  selectedWeek > plan.currentWeek
                                      ? 'Week $selectedWeek hasn\'t started yet'
                                      : weekDays.isEmpty
                                          ? 'No workouts scheduled for this week'
                                          : 'Viewing Week $selectedWeek plan',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.textDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // APK Test #3 / Obs 1: deployment header above
                    // Roadmap pill. Communicates that THIS WEEK is one
                    // chapter of a 12-week deployment, not the whole story.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: Text(
                        'DEPLOYMENT 01 — FOUNDATION  (WEEK ${plan.currentWeek} OF 12)',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // VIEW ROADMAP pill — Q7 surface A entry point
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 10),
                      child: GestureDetector(
                        onTap: () => context.push('/train/roadmap'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.input,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.accent),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.map_outlined,
                                  size: 16, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Text(
                                'VIEW THE 12-WEEK ROADMAP',
                                style: AppTypography.mono.copyWith(
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.arrow_forward,
                                  size: 14, color: AppColors.accent),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 3. This Week section label — moved BELOW Roadmap
                    // pill per APK Test #3 / Obs 1 ordering decision.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: Text(
                        'THIS WEEK',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Week selector tabs
                    WeekSelector(
                      totalWeeks: plan.weeks.length.clamp(1, 12),
                      selectedWeek: selectedWeek,
                      // Real current phase from user_progress (via
                      // CurrentPlanData.phase) — drives dynamic phase labels so
                      // the strip never shows a duplicate "PHASE I". Fix
                      // 2026-06-02 (two-Phase-1 bug).
                      currentPhase: plan.phase,
                      onSelect: (week) {
                          // H-2 (audit-2026-05-11) — read the reactive
                          // subscription provider instead of the snapshot
                          // `SubscriptionService.isPro()`. Stale snapshot
                          // class APK Test #12 / C-2 — a free user who
                          // upgrades mid-session would still be routed to
                          // the preview screen until the next rebuild.
                          // `ref.read` here is fine: the surrounding
                          // build already watches `subscriptionInfoProvider`
                          // (or its descendants) so this callback re-binds
                          // when the provider invalidates.
                          final isProUser =
                              ref.read(subscriptionInfoProvider).isPro;
                          // Weeks 5-12 are PRO-only. Free users tapping a
                          // locked week chip are routed to the read-only
                          // preview screen (Q7 surface C) instead of
                          // selecting a week they can't access.
                          if (!isProUser && week >= 5) {
                            final phase = week <= 8 ? 'II' : 'III';
                            context.push(
                                '/train/preview?phase=$phase&week=$week&day=1');
                            return;
                          }
                          ref.read(selectedWeekProvider.notifier).select(week);
                          ref.read(expandedDayProvider.notifier).collapse();
                        },
                    ),
                    const SizedBox(height: 10),

                    // Compact week rows
                    if (weekDays.isEmpty)
                      _buildEmptyWeek()
                    else
                      _buildCompactWeekRows(context, weekDays),

                    const SizedBox(height: 14),

                    // Phase unlock card -- show after week 4
                    if (plan.phase == 1 && plan.hasPlan)
                      _buildPhaseUnlockCard(context, plan, ref),

                    const SizedBox(height: 14),

                    // YOUR PRs section
                    const StatsGrid(),

                    const SizedBox(height: 20),

                    // MY TEMPLATES section
                    _buildMyTemplatesSection(context, ref),

                    const SizedBox(height: 20),

                    // YOUR EXERCISES section — header + CREATE pill +
                    // horizontal chip row showing all custom exercises
                    // with their approval status. Replaces the older
                    // full-width "Create Custom Exercise" card (saves
                    // vertical space and surfaces DRAFT/PENDING
                    // state visibly, per APK-test-1-batch D4/D6).
                    _buildYourExercisesSection(context),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}

// OI-02 / OI-08 (closes-diagnose: 2026-05-17-oi-02-read-services) —
// file-private `_bestPerSetReps` / `_bestPerSetDuration` helpers
// migrated to `WorkoutReadService.bestPerSetReps` /
// `.bestPerSetDuration` in `lib/core/services/workout_read_service.dart`.
// All callsites in this file now delegate to the canonical service.
