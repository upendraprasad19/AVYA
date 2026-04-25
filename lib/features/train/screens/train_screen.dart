import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
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
import '../widgets/create_custom_exercise_sheet.dart';
import '../widgets/edit_workout_log_sheet.dart';
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

                    // 3. This Week section label
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

    // Matches handoff `train.jsx` lines 14–29: eyebrow + "Week N of M"
    // Fraunces title with inline "· X/Y done" dim subtitle, progress
    // bar with trailing "NN%" gold mono label, single bottom `line2`.
    return Container(
      color: AppColors.bgDeep,
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnchorGlyph(size: 12),
              const SizedBox(width: 8),
              Text(
                'PHASE ${plan.phase} \u00B7 ${plan.phaseName.toUpperCase()}',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: AppTypography.h2.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(text: 'Week $selectedWeek of ${plan.weeks.length}'),
                TextSpan(
                  text: '  \u00B7  $completedDays/$totalWorkoutDays done',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          WardBar(
            pct: progress,
            height: 4,
            trailingLabel: '$progressPercent%',
            trailingColor: AppColors.accent,
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
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          if (isDoneToday && todayDay != null)
            _buildDoneHeroCard(todayDay)
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

    // Split workout.name so the mode label (e.g. "Relaxed", "Focused")
    // renders as an italic-gold second run under the title. Phase-driven
    // same as Home — matches handoff "Leg Day / _Relaxed_" pattern.
    final plan = ref.read(currentPlanProvider);
    final phaseMode = {
      1: 'Relaxed',
      2: 'Focused',
      3: 'Capacity',
      4: 'Peak',
    };
    final modeLabel = phaseMode[plan.phase] ?? 'Focused';

    return WardCard(
      variant: WardCardVariant.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: AppTypography.h2.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
                height: 1.1,
              ),
              children: [
                TextSpan(text: workout.name),
                const TextSpan(text: ' '),
                TextSpan(
                  text: modeLabel,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          if (focusText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              focusText,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${workout.exerciseCount} EXERCISES \u00B7 ~${workout.estimatedDuration.toString().toUpperCase()}',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          WardButton(
            label: 'START WORKOUT',
            trailing: const Icon(Icons.arrow_forward,
                size: 14, color: AppColors.bgDeep),
            onPressed: () {
              ref.read(activeWorkoutProvider.notifier).startWorkout(workout);
              context.go('/train/active-workout');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRestHeroCard() {
    return WardCard(
      onTap: () => _showRestDaySheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REST DAY',
            style: AppTypography.mono.copyWith(
              fontSize: 12,
              color: AppColors.textDim,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recovery & mobility \u2014 tap for recovery tips',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneHeroCard(WorkoutDayData workout) {
    return WardCard(
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.ok, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.name,
                  style: AppTypography.h3,
                ),
                const SizedBox(height: 2),
                Text(
                  'Completed today \u2014 great work!',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.ok,
                  ),
                ),
              ],
            ),
          ),
          const WardChip(label: 'DONE', tone: WardChipTone.ok),
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
      child: WardCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < weekDays.length; i++) ...[
              _buildCompactRow(context, weekDays[i], todayStr, i),
              // Inline expanded exercises for completed days (W5)
              if (expandedIdx == i && weekDays[i].isDone && weekDays[i].date != null)
                _buildExpandedExercises(weekDays[i]),
              // Inline expanded preview + Start Workout for today-planned
              if (expandedIdx == i &&
                  !weekDays[i].isDone &&
                  !weekDays[i].isRest &&
                  weekDays[i].date != null &&
                  _formatDateKey(weekDays[i].date!) == todayStr)
                _buildPlannedExpansion(context, weekDays[i]),
              if (i < weekDays.length - 1)
                const WardRule(margin: EdgeInsets.zero),
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
          // Today's planned workout: expand inline preview with Start Workout button
          ref.read(expandedDayProvider.notifier).toggle(dayIndex);
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
              ? const BoxDecoration(
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
                  dayLabel.toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    color: day.isRest
                        ? AppColors.textDim.withValues(alpha: 0.5)
                        : AppColors.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
              ),

              // Workout name
              Expanded(
                child: Text(
                  day.isRest ? 'Rest' : day.name,
                  style: (day.isRest
                          ? AppTypography.bodySm
                          : AppTypography.h3.copyWith(fontSize: 14))
                      .copyWith(
                    color: day.isRest
                        ? AppColors.textDim.withValues(alpha: 0.5)
                        : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Exercise count (only for workout days)
              if (!day.isRest) ...[
                Text(
                  '${day.exerciseCount} EX',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // Status indicator
              _buildStatusIndicator(
                status,
                isExpanded: (status == _RowStatus.done ||
                        status == _RowStatus.today) &&
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
            const WardChip(label: 'DONE', tone: WardChipTone.ok),
            const SizedBox(width: 2),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: AppColors.ok.withValues(alpha: 0.6),
            ),
          ],
        );
      case _RowStatus.today:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WardChip(label: 'TODAY', tone: WardChipTone.gold),
            const SizedBox(width: 2),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: AppColors.accent.withValues(alpha: 0.6),
            ),
          ],
        );
      case _RowStatus.planned:
        // Handoff: small circle outline only — no chip.
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.textGhost,
              width: 1.5,
            ),
          ),
        );
      case _RowStatus.missed:
        // Handoff: row opacity already at 60%; render a muted minus.
        return Text(
          '\u2014',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.bad.withValues(alpha: 0.6),
            letterSpacing: 1,
          ),
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
          style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
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
              color: isPr ? AppColors.proGold : AppColors.ok,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: AppTypography.bodySm.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              detail,
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textDim,
                letterSpacing: 1.2,
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
          child: WardButton(
            label: 'VIEW WORKOUT CARD',
            leading: const Icon(Icons.card_giftcard_outlined,
                size: 14, color: AppColors.accent),
            variant: WardButtonVariant.outline,
            size: WardButtonSize.small,
            onPressed: () => context.go('/train/active-workout'),
          ),
        );
      }
    }

    // Edit button — opens the same EditWorkoutLogSheet used by the receipt
    // sheet, so past completed days can also be corrected inline without
    // needing to open the receipt first.
    final editButton = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: WardButton(
        label: 'EDIT LOG',
        leading: const Icon(Icons.edit_outlined,
            size: 12, color: AppColors.textPrimary),
        variant: WardButtonVariant.ghost,
        size: WardButtonSize.small,
        onPressed: () => EditWorkoutLogSheet.show(context, day.date!),
      ),
    );

    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(50, 2, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...logRows,
          editButton,
          ?viewCardButton,
        ],
      ),
    );
  }

  String _formatDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Planned Expansion (today, not yet started) ──────────────────

  Widget _buildPlannedExpansion(BuildContext context, WorkoutDayData day) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(50, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (day.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No exercises scheduled',
                style:
                    AppTypography.bodySm.copyWith(color: AppColors.textDim),
              ),
            )
          else ...[
            // Warm-up section (collapsed by default)
            if (day.warmup.isNotEmpty) ...[
              _CollapsibleExerciseSection(
                label: 'WARM-UP',
                color: AppColors.warn,
                exercises: day.warmup,
                buildRow: (ex) => _buildPreviewExerciseRow(
                  ex, null, AppColors.warn,
                ),
              ),
              const SizedBox(height: 8),
              _buildPreviewSectionLabel('WORKOUT', AppColors.accent),
            ],
            // Main exercises
            ...List.generate(day.exercises.length, (index) {
              final ex = day.exercises[index];
              return _buildPreviewExerciseRow(
                  ex, index + 1, AppColors.accent);
            }),
            // Cool-down section (collapsed by default)
            if (day.cooldown.isNotEmpty) ...[
              const SizedBox(height: 8),
              _CollapsibleExerciseSection(
                label: 'COOL-DOWN',
                color: AppColors.info,
                exercises: day.cooldown,
                buildRow: (ex) => _buildPreviewExerciseRow(
                  ex, null, AppColors.info,
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          // START WORKOUT button — always available (Q6 made free)
          WardButton(
            label: 'START WORKOUT',
            leading: const Icon(Icons.play_arrow_rounded,
                size: 16, color: AppColors.bgDeep),
            onPressed: () {
              ref.read(activeWorkoutProvider.notifier).startWorkout(day);
              context.go('/train/active-workout');
            },
          ),
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
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
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
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '🧘 Rest Day — Recovery',
              style: AppTypography.h2,
            ),
            const SizedBox(height: 8),
            Text(
              'This is when your muscles actually grow. Use today to recover well.',
              style: AppTypography.body.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 20),
            Text(
              'RECOVERY TIPS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
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
                        style: AppTypography.body,
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
            WardButton(
              label: 'LOG WEIGHT',
              leading: const Icon(Icons.monitor_weight_outlined,
                  size: 16, color: AppColors.accent),
              variant: WardButtonVariant.outline,
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => const WeightLogSheet(),
                );
              },
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
                    color: AppColors.line2,
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
                      style: AppTypography.mono.copyWith(
                        fontSize: 13,
                        color: day.isDone
                            ? AppColors.ok
                            : AppColors.textPrimary,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Section label
              Text(
                hasActualLogs ? 'LOGGED EXERCISES' : 'PLANNED EXERCISES',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
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
                                const Icon(Icons.check_circle,
                                    color: AppColors.ok, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: AppTypography.h3
                                            .copyWith(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        detail,
                                        style: AppTypography.monoXs.copyWith(
                                          color: AppColors.textDim,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (log['is_pr'] == true)
                                  const WardChip(
                                      label: 'PR', tone: WardChipTone.gold),
                              ],
                            ),
                          );
                        }).toList()
                      : day.exercises.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                child: Text(
                                  day.isDone
                                      ? 'Logged details not saved'
                                      : 'No exercises scheduled',
                                  style: AppTypography.bodySm
                                      .copyWith(color: AppColors.textDim),
                                ),
                              ),
                            ]
                          : [
                              // Warm-up section (Bug #15a: collapsed by default)
                              if (day.warmup.isNotEmpty) ...[
                                _CollapsibleExerciseSection(
                                  label: 'WARM-UP',
                                  color: AppColors.warn,
                                  exercises: day.warmup,
                                  buildRow: (ex) => _buildPreviewExerciseRow(
                                    ex, null, AppColors.warn,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildPreviewSectionLabel(
                                    'WORKOUT', AppColors.accent),
                              ],
                              // Main exercises (always expanded — focal content)
                              ...List.generate(day.exercises.length, (index) {
                                final ex = day.exercises[index];
                                return _buildPreviewExerciseRow(
                                  ex,
                                  index + 1,
                                  AppColors.accent,
                                );
                              }),
                              // Cool-down section (Bug #15a: collapsed by default)
                              if (day.cooldown.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _CollapsibleExerciseSection(
                                  label: 'COOL-DOWN',
                                  color: AppColors.info,
                                  exercises: day.cooldown,
                                  buildRow: (ex) => _buildPreviewExerciseRow(
                                    ex, null, AppColors.info,
                                  ),
                                ),
                              ],
                            ],
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  // ── Preview sheet helpers ────────────────────────────────────

  Widget _buildPreviewSectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: AppTypography.mono.copyWith(
          color: color.withValues(alpha: 0.7),
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildPreviewExerciseRow(ExerciseData ex, int? number, Color color) {
    // Format detail based on logging type
    String detail;
    if (ex.loggingType == 'timed') {
      // ExerciseData.reps is now a clean numeric string for timed exercises
      // (set by _parseTimedDurationSecs in train_provider.dart). Defensive
      // fallback to 30s if upstream parsing somehow failed (Bug #16 guard).
      final raw = ex.reps.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedSecs = int.tryParse(raw) ?? 0;
      final secs = parsedSecs > 0 ? parsedSecs : 30;
      if (secs >= 60) {
        final mins = secs ~/ 60;
        final remainder = secs % 60;
        detail = remainder == 0 ? '${mins}m' : '${mins}m ${remainder}s';
      } else {
        detail = '${secs}s';
      }
    } else {
      final restSecs = ex.rest.replaceAll('s', '');
      detail = '${ex.sets} sets · ${ex.reps} reps · ${restSecs}s rest';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (number != null)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: AppTypography.monoXs.copyWith(
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            Icon(
              Icons.circle,
              size: 6,
              color: color.withValues(alpha: 0.5),
            ),
          SizedBox(width: number != null ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.name,
                  style: AppTypography.h3.copyWith(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  ex.muscleLabel != null
                      ? '${ex.muscleLabel} · $detail'
                      : detail,
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      child: WardCard(
        variant: WardCardVariant.hero,
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
                  style: AppTypography.mono.copyWith(
                    color: AppColors.proGold,
                    letterSpacing: 2.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canGraduate
                  ? 'You crushed Phase 1 with ${(completionRate * 100).round()}% completion! View your achievements and unlock Phase 2.'
                  : 'Great progress! Unlock Phase 2 to continue building strength with new exercises and progressive overload.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            WardButton(
              label: canGraduate
                  ? 'VIEW YOUR ACHIEVEMENT'
                  : 'UNLOCK PHASE 2',
              onPressed: () {
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
            style: AppTypography.h2.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Building a personalised workout schedule\nbased on your profile',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
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
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/train/template-builder'),
                child: const WardChip(
                  label: '+ CREATE',
                  tone: WardChipTone.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (templates.isEmpty)
            WardCard(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const Icon(Icons.fitness_center_outlined,
                      size: 28, color: AppColors.textDim),
                  const SizedBox(height: 8),
                  Text(
                    'No templates yet',
                    style: AppTypography.h3.copyWith(
                      fontSize: 13,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap Create to build a custom workout',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textDim),
                  ),
                ],
              ),
            )
          else
            ...templates.map((tmpl) {
              final name = tmpl['name'] as String? ?? 'Unnamed';
              final exercises = tmpl['exercises'] as List? ?? [];
              final templateId = tmpl['id'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: WardCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppTypography.h3.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${exercises.length} EXERCISE${exercises.length == 1 ? '' : 'S'}',
                              style: AppTypography.monoXs.copyWith(
                                color: AppColors.textDim,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            context.go('/train/template-builder', extra: {
                          'templateId': templateId,
                          'templateData': tmpl,
                        }),
                        child: const WardChip(
                          label: 'EDIT',
                          tone: WardChipTone.neutral,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _scheduleTemplate(
                            context, ref, templateId, name),
                        child: const WardChip(
                          label: 'SCHEDULE',
                          tone: WardChipTone.gold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _confirmDeleteTemplate(
                            context, ref, templateId, name),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.bgRaise,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            border:
                                Border.all(color: AppColors.line2),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTemplate(
      BuildContext context, WidgetRef ref, String templateId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'Delete "$name"?',
          style: AppTypography.h3,
        ),
        content: Text(
          'Your originally scheduled workouts will be restored on those days. Completed workouts stay in your history.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCEL',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.textDim,
                letterSpacing: 2,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'DELETE',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.bad,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(templatesProvider.notifier).deleteTemplate(templateId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Template deleted',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.card,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete template: $e',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.bad,
        ),
      );
    }
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
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
              ),
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
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Schedule "$name"',
                  style: AppTypography.h2.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap days to select. Any combination.',
                  style:
                      AppTypography.bodySm.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: 16),
                // Day headers
                Row(
                  children: dayLabels
                      .map((l) => Expanded(
                            child: Center(
                              child: Text(
                                l,
                                style: AppTypography.monoXs.copyWith(
                                  color: AppColors.textDim,
                                  letterSpacing: 1.5,
                                ),
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
                                  style: AppTypography.numeric.copyWith(
                                    fontSize: 13,
                                    color: isPast
                                        ? AppColors.textDim
                                            .withValues(alpha: 0.3)
                                        : isSelected
                                            ? AppColors.bgDeep
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
                      '${selected.length} DAY${selected.length == 1 ? '' : 'S'} SELECTED',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                // Schedule button
                WardButton(
                  label: 'SCHEDULE',
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(ctx).pop(true),
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
      await WorkoutScheduleService.instance
          .assignTemplateToDate(templateId, date);
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
          style: AppTypography.bodySm,
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Your Exercises Section (D4 / D6) ─────────────────────────────
  //
  // Replaces the pre-2026-04-24 full-width "Create Custom Exercise"
  // WardCard with a header-plus-chips layout that mirrors MY TEMPLATES.
  // Users can see every exercise they've created, with a visible
  // approval state (DRAFT / PENDING / APPROVED) so the path from
  // create -> community -> approved is legible without opening Profile.

  Widget _buildYourExercisesSection(BuildContext context) {
    final customBox = HiveService.instance.customBox;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'YOUR EXERCISES',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _openCreateCustomExerciseSheet(context),
                child: const WardChip(
                  label: '+ CREATE',
                  tone: WardChipTone.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ValueListenableBuilder rebuilds the chip row whenever the
          // Hive customBox mutates — so new exercises appear as soon as
          // CreateCustomExerciseSheet._save writes them.
          ValueListenableBuilder<Box<dynamic>>(
            valueListenable: customBox.listenable(),
            builder: (context, box, _) {
              final exercises = _collectCustomExercises(box);
              if (exercises.isEmpty) {
                return WardCard(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.fitness_center_outlined,
                        size: 28,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No custom exercises yet',
                        style: AppTypography.h3.copyWith(
                          fontSize: 13,
                          color: AppColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap + CREATE to add one',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: exercises.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) =>
                      _CustomExerciseChip(exercise: exercises[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Reads every `custom_exercise_*` entry from the Hive customBox and
  /// returns them newest-first. Filters out malformed entries.
  List<Map<String, dynamic>> _collectCustomExercises(Box<dynamic> box) {
    final out = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('custom_exercise_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['_key'] = key;
      out.add(map);
    }
    // Newest first. Hive keys are `custom_exercise_<ms>` so string
    // descending sort == recency order.
    out.sort((a, b) => (b['_key'] as String).compareTo(a['_key'] as String));
    return out;
  }

  void _openCreateCustomExerciseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CreateCustomExerciseSheet(
        onCreated: (exercise) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exercise saved. Showing in YOUR EXERCISES.',
                style: AppTypography.bodySm,
              ),
              backgroundColor: AppColors.card,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal chip for a custom exercise on the Train screen, showing
/// name + approval status. Status rules:
///   * `approved_for_library=true`          -> APPROVED (ok)
///   * `submitted_to_library=true` only     -> PENDING  (warn)
///   * neither                               -> DRAFT    (textMute)
class _CustomExerciseChip extends StatelessWidget {
  const _CustomExerciseChip({required this.exercise});

  final Map<String, dynamic> exercise;

  @override
  Widget build(BuildContext context) {
    final name = exercise['name'] as String? ?? 'Unnamed';
    final submitted = exercise['submitted_to_library'] == true;
    final approved = exercise['approved_for_library'] == true;

    final (String statusLabel, Color statusColor) = approved
        ? ('APPROVED', AppColors.ok)
        : submitted
            ? ('PENDING', AppColors.warn)
            : ('DRAFT', AppColors.textMute);

    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.h3.copyWith(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (approved) ...[
                Icon(Icons.check_circle_outline, size: 11, color: statusColor),
                const SizedBox(width: 4),
              ],
              Text(
                statusLabel,
                style: AppTypography.monoXs.copyWith(
                  color: statusColor,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _RowStatus { done, today, planned, missed, rest }

/// Bug #15a: Collapsible WARM-UP / COOL-DOWN section in the train preview.
/// Default state is collapsed — header (label + chevron) is tappable to toggle.
/// Body uses [AnimatedSize] for a smooth reveal.
class _CollapsibleExerciseSection extends StatefulWidget {
  const _CollapsibleExerciseSection({
    required this.label,
    required this.color,
    required this.exercises,
    required this.buildRow,
  });

  final String label;
  final Color color;
  final List<ExerciseData> exercises;
  final Widget Function(ExerciseData) buildRow;

  @override
  State<_CollapsibleExerciseSection> createState() =>
      _CollapsibleExerciseSectionState();
}

class _CollapsibleExerciseSectionState
    extends State<_CollapsibleExerciseSection> {
  // Default to collapsed — that's the entire point of Bug #15a.
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header — label + count + chevron, tappable
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  widget.label,
                  style: AppTypography.mono.copyWith(
                    color: widget.color.withValues(alpha: 0.7),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.exercises.length}',
                  style: AppTypography.monoXs.copyWith(
                    color: widget.color.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _expanded ? 0.5 : 0.0,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: widget.color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Body — animated reveal
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.exercises.map(widget.buildRow).toList(),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
