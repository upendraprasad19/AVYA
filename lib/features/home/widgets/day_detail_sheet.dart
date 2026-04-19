import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet showing workout details for a tapped calendar day.
///
/// Shows exercises with sets/reps/rest for workout days,
/// recovery tips for rest days, and completion status.
class DayDetailSheet extends StatelessWidget {
  final DateTime date;
  final Map<String, dynamic>? schedule;

  const DayDetailSheet({
    super.key,
    required this.date,
    this.schedule,
  });

  /// Show the day detail bottom sheet.
  static void show(
    BuildContext context, {
    required DateTime date,
    Map<String, dynamic>? schedule,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DayDetailSheet(date: date, schedule: schedule),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = schedule?['type'] as String? ?? 'none';
    final status = schedule?['status'] as String? ?? 'none';
    final isWorkout = type == 'workout' || type == 'custom_template';
    final isCompleted = status == 'completed';
    final isRestDay = type == 'rest' || type == 'none';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                14,
                AppSpacing.gutter,
                0,
              ),
              child: _buildHeader(),
            ),
            const SizedBox(height: 12),
            const WardRule(margin: EdgeInsets.zero),
            // Body
            if (isRestDay)
              _buildRestBody()
            else
              Flexible(child: _buildWorkoutBody()),
            // Footer button
            _buildFooter(context, isWorkout: isWorkout, isCompleted: isCompleted),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────

  Widget _buildHeader() {
    final workoutName = schedule?['workout_name'] as String? ?? '';
    final type = schedule?['type'] as String? ?? 'none';
    final isWorkout = type == 'workout' || type == 'custom_template';
    final week = schedule?['week'] as int? ?? 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDate(date).toUpperCase(),
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDateDisplay(date),
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              if (week > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'WEEK $week',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isWorkout && workoutName.isNotEmpty)
          WardChip(
            label: workoutName,
            tone: WardChipTone.gold,
          )
        else if (!isWorkout)
          const WardChip(
            label: 'REST DAY',
            tone: WardChipTone.neutral,
          ),
      ],
    );
  }

  // ── Rest Day Body ───────────────────────────────────────────────

  Widget _buildRestBody() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(
            Icons.self_improvement_rounded,
            size: 40,
            color: AppColors.textDim.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Rest & Recovery',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Focus on light stretching, foam rolling, and staying hydrated. '
            'Sleep 7-9 hours to maximise muscle recovery and performance gains.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              color: AppColors.textDim,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Workout Body ────────────────────────────────────────────────

  Widget _buildWorkoutBody() {
    final exercises = schedule?['exercises'] as List? ?? [];

    if (exercises.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Text(
          'No exercises scheduled.',
          style: AppTypography.body.copyWith(
            color: AppColors.textDim,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: 12,
      ),
      shrinkWrap: true,
      itemCount: exercises.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final exercise = exercises[index];
        final Map<String, dynamic> ex;
        if (exercise is Map) {
          ex = Map<String, dynamic>.from(exercise);
        } else {
          return const SizedBox.shrink();
        }

        final name = ex['exercise_name'] as String? ??
            ex['name'] as String? ??
            'Unknown Exercise';
        final sets = ex['sets'] as int? ??
            ex['prescribed_sets'] as int? ??
            ex['default_sets'] as int? ??
            3;
        final reps = ex['reps'] as String? ??
            ex['prescribed_reps'] as String? ??
            ex['default_reps'] as String? ??
            '10';
        final restSecs = ex['rest_seconds'] as int? ??
            ex['default_rest_secs'] as int? ??
            60;
        final loggingType = ex['logging_type'] as String? ?? 'weight_reps';

        return WardCard(
          variant: WardCardVariant.inset,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Exercise index
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatExerciseDetail(
                        loggingType: loggingType,
                        sets: sets,
                        reps: reps,
                        restSecs: restSecs,
                      ),
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Footer ──────────────────────────────────────────────────────

  Widget _buildFooter(
    BuildContext context, {
    required bool isWorkout,
    required bool isCompleted,
  }) {
    if (!isWorkout) {
      return const SizedBox(height: 16);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(date.year, date.month, date.day);
    final isToday = targetDay == today;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: isCompleted
          ? _buildCompletedFooter(context)
          : SizedBox(
              width: double.infinity,
              height: 48,
              child: _buildStartButton(context, enabled: isToday),
            ),
    );
  }

  Widget _buildCompletedFooter(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Completed badge
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.ok.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(
                color: AppColors.ok.withValues(alpha: 0.33),
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 16, color: AppColors.ok),
                const SizedBox(width: 8),
                Text(
                  'COMPLETED',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.ok,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // View Workout Card button — sharp 2-px accent outline
        SizedBox(
          width: double.infinity,
          height: 44,
          child: Material(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            child: InkWell(
              onTap: () {
                final receiptData = WorkoutReceiptData.fromExerciseLogs(date);
                if (receiptData != null) {
                  WorkoutReceiptSheet.show(context, receiptData);
                }
              },
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.33),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'VIEW WORKOUT CARD',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.accent,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton(BuildContext context, {required bool enabled}) {
    return Material(
      color: enabled ? AppColors.accent : AppColors.textDisabled,
      borderRadius: BorderRadius.circular(AppRadius.sharp),
      child: InkWell(
        onTap: enabled ? () => Navigator.of(context).pop() : null,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        child: Center(
          child: Text(
            'START WORKOUT',
            style: AppTypography.mono.copyWith(
              color: enabled ? Colors.black : AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    const dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return dayNames[d.weekday - 1];
  }

  String _formatDateDisplay(DateTime d) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[d.month - 1]} ${d.day}';
  }

  String _formatExerciseDetail({
    required String loggingType,
    required int sets,
    required String reps,
    required int restSecs,
  }) {
    switch (loggingType) {
      case 'timed':
        return '$sets SETS \u00B7 ${reps}S \u00B7 ${restSecs}S REST';
      case 'cardio':
        return '$reps MIN \u00B7 ${restSecs}S REST';
      case 'distance':
        return '$reps \u00B7 ${restSecs}S REST';
      default:
        return '$sets SETS \u00D7 $reps REPS \u00B7 ${restSecs}S REST';
    }
  }
}
