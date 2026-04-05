import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import '../repositories/workout_repository.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import '../providers/train_provider.dart';
import 'package:icanbefitter/features/home/widgets/weight_log_sheet.dart';
import '../widgets/week_selector.dart';
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
                    // 1. Plan header with progress bar
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
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.cardPadding),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius:
                                BorderRadius.circular(AppRadius.cardM),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  selectedWeek > plan.currentWeek
                                      ? 'Week $selectedWeek hasn\'t started yet'
                                      : weekDays.isEmpty
                                          ? 'No workouts scheduled for this week'
                                          : 'Viewing Week $selectedWeek plan',
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // 3. This Week section label
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: Text(
                        'THIS WEEK',
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
                      totalWeeks: plan.weeks.length.clamp(1, 12),
                      selectedWeek: selectedWeek,
                      onSelect: (week) {
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
                  ],
                ),
              ),
      ),
    );
  }

  // ── 1. Plan Header with Progress Bar ──────────────────────────

  Widget _buildPlanHeader(
      CurrentPlanData plan, int selectedWeek, List<WorkoutDayData> weekDays) {
    // Calculate week completion
    int totalWorkoutDays = 0;
    int completedDays = 0;
    for (final day in weekDays) {
      if (!day.isRest) {
        totalWorkoutDays++;
        if (day.isDone) completedDays++;
      }
    }
    final progress =
        totalWorkoutDays > 0 ? completedDays / totalWorkoutDays : 0.0;
    final progressPercent = (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase title
          Text(
            'PHASE ${plan.phase} \u00b7 ${plan.phaseName.toUpperCase()}',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),

          // Subtitle with completion count
          Text(
            'Week $selectedWeek of ${plan.weeks.length} \u00b7 $completedDays/$totalWorkoutDays workouts done',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161d28),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$progressPercent%',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Today's Workout Hero Card ──────────────────────────────

  Widget _buildTodayHeroCard(BuildContext context, CurrentPlanData plan,
      WorkoutDayData? todayWorkout) {
    // Always use current week data for today lookup (W2 fix).
    final currentWeekDays = plan.getWeek(plan.currentWeek);
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    WorkoutDayData? todayDay;
    for (final day in currentWeekDays) {
      if (day.date != null) {
        final dayStr =
            '${day.date!.year}-${day.date!.month.toString().padLeft(2, '0')}-${day.date!.day.toString().padLeft(2, '0')}';
        if (dayStr == todayStr) {
          todayDay = day;
          break;
        }
      }
    }

    final isRestDay = todayDay?.isRest ?? (todayWorkout == null);
    final isDoneToday = todayDay?.isDone ?? false;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S WORKOUT",
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (isDoneToday)
            _buildDoneHeroCard(todayDay!)
          else if (isRestDay)
            _buildRestHeroCard()
          else if (todayWorkout != null)
            _buildWorkoutHeroCard(context, todayWorkout),
        ],
      ),
    );
  }

  Widget _buildWorkoutHeroCard(
      BuildContext context, WorkoutDayData workout) {
    // Extract focus/muscles from subtitle
    final subtitleParts = workout.subtitle.split('\u00b7');
    final focusText =
        subtitleParts.isNotEmpty ? subtitleParts[0].trim() : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workout.name,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (focusText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              focusText,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${workout.exerciseCount} exercises \u00b7 ~${workout.estimatedDuration}',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              ref
                  .read(activeWorkoutProvider.notifier)
                  .startWorkout(workout);
              context.go('/train/active-workout');
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'START WORKOUT \u2192',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestHeroCard() {
    return GestureDetector(
      onTap: () => _showRestDaySheet(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REST DAY',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Recovery & mobility \u2014 tap for recovery tips',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneHeroCard(WorkoutDayData workout) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(
          color: AppColors.green.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.name,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Completed today \u2014 great work!',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Compact Week Rows ──────────────────────────────────────

  Widget _buildCompactWeekRows(
      BuildContext context, List<WorkoutDayData> weekDays) {
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final expandedIdx = ref.watch(expandedDayProvider);

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            for (int i = 0; i < weekDays.length; i++) ...[
              _buildCompactRow(context, weekDays[i], todayStr, i),
              // Inline expanded exercises for completed days (W5)
              if (expandedIdx == i && weekDays[i].isDone && weekDays[i].date != null)
                _buildExpandedExercises(weekDays[i]),
              if (i < weekDays.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.border,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactRow(
      BuildContext context, WorkoutDayData day, String todayStr, int dayIndex) {
    // Determine if this is today
    bool isToday = false;
    if (day.date != null) {
      final dayStr =
          '${day.date!.year}-${day.date!.month.toString().padLeft(2, '0')}-${day.date!.day.toString().padLeft(2, '0')}';
      isToday = dayStr == todayStr;
    }

    // 3-letter day name
    String dayLabel = '';
    if (day.date != null) {
      const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      dayLabel = dayNames[day.date!.weekday - 1];
    } else {
      dayLabel = 'D${day.dayNumber}';
    }

    // Determine if this day is in the past
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final isPast = day.date != null && day.date!.isBefore(todayDate);

    // Status
    _RowStatus status;
    if (day.isRest) {
      status = _RowStatus.rest;
    } else if (day.isDone) {
      status = _RowStatus.done;
    } else if (isToday) {
      status = _RowStatus.today;
    } else if (isPast) {
      status = _RowStatus.missed;
    } else {
      status = _RowStatus.planned;
    }

    // Today's incomplete workout navigates to active workout;
    // completed days expand inline (W5); future/past show preview; rest days show recovery sheet
    return GestureDetector(
      onTap: () {
        if (day.isRest) {
          _showRestDaySheet(context);
        } else if (isToday && !day.isDone) {
          ref
              .read(activeWorkoutProvider.notifier)
              .startWorkout(day);
          context.go('/train/active-workout');
        } else if (day.isDone) {
          // Completed days expand inline to show logged exercises (W5)
          ref.read(expandedDayProvider.notifier).toggle(dayIndex);
        } else {
          _showExercisePreviewSheet(context, day);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: status == _RowStatus.missed ? 0.6 : 1.0,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: isToday
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: AppColors.accent,
                      width: 2,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              // Day name
              SizedBox(
                width: 36,
                child: Text(
                  dayLabel,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: day.isRest
                        ? AppColors.textSecondary.withValues(alpha: 0.5)
                        : AppColors.textSecondary,
                  ),
                ),
              ),

              // Workout name
              Expanded(
                child: Text(
                  day.isRest ? 'Rest' : day.name,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: day.isRest ? FontWeight.w400 : FontWeight.w700,
                    color: day.isRest
                        ? AppColors.textSecondary.withValues(alpha: 0.5)
                        : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Exercise count (only for workout days)
              if (!day.isRest) ...[
                Text(
                  '${day.exerciseCount} ex',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // Status indicator
              _buildStatusIndicator(
                status,
                isExpanded: status == _RowStatus.done &&
                    ref.watch(expandedDayProvider) == dayIndex,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(_RowStatus status, {bool isExpanded = false}) {
    switch (status) {
      case _RowStatus.done:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppColors.green, size: 14),
            const SizedBox(width: 4),
            Text(
              'Done',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: AppColors.green.withValues(alpha: 0.6),
            ),
          ],
        );
      case _RowStatus.today:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Today',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        );
      case _RowStatus.planned:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Planned',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      case _RowStatus.missed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\u2014',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Missed',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      case _RowStatus.rest:
        return const SizedBox.shrink();
    }
  }

  // ── Expanded Exercises (W5) ─────────────────────────────────

  Widget _buildExpandedExercises(WorkoutDayData day) {
    final logs =
        WorkoutRepository.instance.getExerciseLogsForDate(day.date!);

    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(50, 0, 14, 10),
        child: Text(
          'No exercise data logged',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    // Build exercise log rows
    final logRows = logs.map((log) {
      final name = log['exercise_name'] as String? ?? 'Exercise';
      final sets = log['sets_completed'] as int? ?? 0;
      final reps = log['reps_completed'] as int? ?? 0;
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      final duration = log['duration_seconds'] as int? ?? 0;
      final loggingType = log['logging_type'] as String? ?? 'weight_reps';
      final isPr = log['is_pr'] == true;

      String detail;
      if (loggingType == 'timed') {
        final mins = duration ~/ 60;
        final secs = duration % 60;
        detail = sets > 1
            ? '$sets sets \u00b7 ${mins > 0 ? '${mins}m ' : ''}${secs}s'
            : '${mins > 0 ? '${mins}m ' : ''}${secs}s';
      } else if (loggingType == 'cardio') {
        final dist = (log['distance_km'] as num?)?.toDouble() ?? 0;
        detail = '${duration ~/ 60} min \u00b7 ${dist.toStringAsFixed(1)} km';
      } else if (weight > 0) {
        detail =
            '$sets sets \u00b7 $reps reps \u00b7 ${weight.toStringAsFixed(1)} kg';
      } else {
        detail = '$sets sets \u00b7 $reps reps';
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(
              isPr ? Icons.emoji_events : Icons.check,
              size: 13,
              color: isPr ? AppColors.proGold : AppColors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              detail,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }).toList();

    // "View Workout Card" button — shown when today's workout is saved
    Widget? viewCardButton;
    final workout = ref.read(activeWorkoutProvider);
    if (workout.isSaved && day.date != null) {
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final dayStr =
          '${day.date!.year}-${day.date!.month.toString().padLeft(2, '0')}-${day.date!.day.toString().padLeft(2, '0')}';
      if (dayStr == todayStr) {
        viewCardButton = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(
            onTap: () => context.go('/train/active-workout'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.card_giftcard_outlined,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'View Workout Card',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(50, 2, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...logRows,
          if (viewCardButton != null) viewCardButton,
        ],
      ),
    );
  }

  // ── Rest Day Sheet ────────────────────────────────────────────

  void _showRestDaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '🧘 Rest Day — Recovery',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is when your muscles actually grow. Use today to recover well.',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'RECOVERY TIPS',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            ...[
              ('🧘', 'Stretch for 10 minutes'),
              ('🚶', 'Light walk 20–30 minutes'),
              ('🔁', 'Foam roll sore muscles'),
              ('💧', 'Drink at least 3L of water'),
              ('😴', 'Aim for 7–9 hours of sleep tonight'),
            ].map((tip) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(tip.$1, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Text(
                    tip.$2,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const WeightLogSheet(),
                  );
                },
                icon: const Icon(Icons.monitor_weight_outlined, size: 18),
                label: Text(
                  'Log Weight',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Exercise Preview Bottom Sheet ────────────────────────────

  void _showExercisePreviewSheet(BuildContext context, WorkoutDayData day) {
    // Format the date label
    String dateLabel = '';
    if (day.date != null) {
      const dayNames = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ];
      const monthNames = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      dateLabel =
          '${dayNames[day.date!.weekday - 1]}, ${monthNames[day.date!.month - 1]} ${day.date!.day}';
    }

    // Load actual exercise logs if this day is completed
    final actualLogs = day.isDone && day.date != null
        ? WorkoutRepository.instance.getExerciseLogsForDate(day.date!)
        : <Map<String, dynamic>>[];
    final hasActualLogs = actualLogs.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title row: workout name + completed badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      day.isDone
                          ? '${day.name.toUpperCase()} ✓'
                          : day.name.toUpperCase(),
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: day.isDone ? AppColors.green : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Section label
              Text(
                hasActualLogs ? 'LOGGED EXERCISES' : 'PLANNED EXERCISES',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              // Exercise list: actual logs if available, else planned
              Flexible(
                child: ListView(
                  controller: scrollCtrl,
                  shrinkWrap: true,
                  children: hasActualLogs
                      ? actualLogs.map((log) {
                          final name = log['exercise_name'] as String? ?? 'Exercise';
                          final sets = log['sets_completed'] as int? ?? 0;
                          final reps = log['reps_completed'] as int? ?? 0;
                          final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
                          final duration = log['duration_seconds'] as int? ?? 0;
                          final loggingType = log['logging_type'] as String? ?? 'weight_reps';

                          String detail;
                          if (loggingType == 'timed') {
                            final mins = duration ~/ 60;
                            final secs = duration % 60;
                            detail = sets > 1
                                ? '$sets sets · ${mins > 0 ? '${mins}m ' : ''}${secs}s'
                                : '${mins > 0 ? '${mins}m ' : ''}${secs}s';
                          } else if (loggingType == 'cardio') {
                            final dist = (log['distance_km'] as num?)?.toDouble() ?? 0;
                            detail = '${duration ~/ 60} min · ${dist.toStringAsFixed(1)} km';
                          } else if (weight > 0) {
                            detail = '$sets sets · $reps reps · ${weight.toStringAsFixed(1)} kg';
                          } else {
                            detail = '$sets sets · $reps reps';
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: AppColors.green, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.getFont(
                                          'DM Sans',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        detail,
                                        style: GoogleFonts.getFont(
                                          'DM Sans',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w400,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (log['is_pr'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.proGoldTint,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'PR',
                                      style: GoogleFonts.getFont(
                                        'DM Sans',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.proGold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList()
                      : day.exercises.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  day.isDone
                                      ? 'Logged details not saved'
                                      : 'No exercises scheduled',
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ]
                          : List.generate(day.exercises.length, (index) {
                              final ex = day.exercises[index];
                              final restSecs = ex.rest.replaceAll('s', '');
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: GoogleFonts.getFont(
                                          'DM Sans',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ex.name,
                                            style: GoogleFonts.getFont(
                                              'DM Sans',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            '${ex.sets} sets \u00b7 ${ex.reps} reps \u00b7 ${restSecs}s rest',
                                            style: GoogleFonts.getFont(
                                              'DM Sans',
                                              fontSize: 10,
                                              fontWeight: FontWeight.w400,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  // ── Phase Unlock Card ─────────────────────────────────────────

  Widget _buildPhaseUnlockCard(
      BuildContext context, CurrentPlanData plan, WidgetRef ref) {
    // Only show if user has reached week 4
    if (plan.currentWeek < 4) return const SizedBox.shrink();

    // Check completion rate for Phase 1 graduation
    final completionRate = _computePhaseCompletionRate(plan);
    final canGraduate =
        completionRate >= AppConstants.phaseUnlockCompletionRate;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
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

    for (int w = 1; w <= plan.weeks.length; w++) {
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

  Widget _buildGeneratingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Generating your plan...',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Building a personalised workout schedule\nbased on your profile',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWeek() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: const EmptyState(
        icon: Icons.fitness_center,
        title: 'No workouts scheduled',
        subtitle: 'This week has no workouts in your plan.',
      ),
    );
  }

  // ── My Templates Section ─────────────────────────────────────

  Widget _buildMyTemplatesSection(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with + button
          Row(
            children: [
              Text(
                'MY TEMPLATES',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/train/template-builder'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Create',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (templates.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.cardM),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(Icons.fitness_center_outlined,
                      size: 28, color: AppColors.textSecondary),
                  const SizedBox(height: 8),
                  Text(
                    'No templates yet',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap Create to build a custom workout',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...templates.map((tmpl) {
              final name = tmpl['name'] as String? ?? 'Unnamed';
              final exercises = tmpl['exercises'] as List? ?? [];
              final templateId = tmpl['id'] as String? ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.cardM),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}',
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
                    GestureDetector(
                      onTap: () => context.go('/train/template-builder', extra: {
                        'templateId': templateId,
                        'templateData': tmpl,
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Edit',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _scheduleTemplate(context, ref, templateId, name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accentTint,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Schedule',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _scheduleTemplate(
      BuildContext context, WidgetRef ref, String templateId, String name) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final Set<DateTime> selected = {};

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          // Build 6 weeks of dates starting from Monday of this week
          final weeks = <List<DateTime?>>[];
          var weekStart = today.subtract(Duration(days: today.weekday - 1));
          for (int w = 0; w < 6; w++) {
            final week = <DateTime?>[];
            for (int d = 0; d < 7; d++) {
              week.add(weekStart.add(Duration(days: d)));
            }
            weeks.add(week);
            weekStart = weekStart.add(const Duration(days: 7));
          }

          const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

          return Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Schedule "$name"',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap days to select. Any combination.',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                // Day headers
                Row(
                  children: dayLabels
                      .map((l) => Expanded(
                            child: Center(
                              child: Text(
                                l,
                                style: GoogleFonts.getFont('DM Sans',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                // Calendar grid
                ...weeks.map((week) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: week.map((date) {
                          if (date == null) {
                            return const Expanded(child: SizedBox());
                          }
                          final isPast = date.isBefore(today);
                          final isSelected = selected.contains(date);
                          final isToday = date == today;
                          return Expanded(
                            child: GestureDetector(
                              onTap: isPast
                                  ? null
                                  : () {
                                      setState(() {
                                        if (isSelected) {
                                          selected.remove(date);
                                        } else {
                                          selected.add(date);
                                        }
                                      });
                                    },
                              child: Container(
                                height: 36,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.accent
                                      : isToday
                                          ? AppColors.accent
                                              .withValues(alpha: 0.15)
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isToday && !isSelected
                                      ? Border.all(
                                          color: AppColors.accent, width: 1)
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${date.day}',
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isPast
                                        ? AppColors.textSecondary
                                            .withValues(alpha: 0.3)
                                        : isSelected
                                            ? Colors.black
                                            : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    )),
                const SizedBox(height: 16),
                // Selected count
                if (selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${selected.length} day${selected.length == 1 ? '' : 's'} selected',
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent),
                    ),
                  ),
                // Schedule button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: selected.isEmpty
                        ? null
                        : () => Navigator.of(ctx).pop(true),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected.isEmpty
                            ? AppColors.border
                            : AppColors.accent,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'SCHEDULE',
                        style: GoogleFonts.getFont('DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: selected.isEmpty
                                ? AppColors.textSecondary
                                : Colors.black),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true || selected.isEmpty) return;
    if (!context.mounted) return;

    final sortedDates = selected.toList()..sort();

    for (final date in sortedDates) {
      WorkoutScheduleService.instance.assignTemplateToDate(templateId, date);
    }
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(currentPlanProvider);
    ref.invalidate(todayWorkoutProvider);

    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final String dateStr;
    if (sortedDates.length == 1) {
      dateStr =
          '${monthNames[sortedDates.first.month - 1]} ${sortedDates.first.day}';
    } else {
      dateStr = '${sortedDates.length} days';
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scheduled "$name" for $dateStr',
          style: GoogleFonts.getFont('DM Sans',
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

enum _RowStatus { done, today, planned, missed, rest }
