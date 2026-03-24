import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

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
    final isWorkout = type == 'workout';
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
            top: Radius.circular(AppRadius.cardL),
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
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                14,
                AppSpacing.cardPadding,
                0,
              ),
              child: _buildHeader(),
            ),
            const SizedBox(height: 12),
            // Divider
            Container(
              height: 1,
              color: AppColors.border.withValues(alpha: 0.5),
            ),
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
    final isWorkout = type == 'workout';
    final week = schedule?['week'] as int? ?? 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDate(date),
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (week > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'WEEK $week',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isWorkout && workoutName.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.badge),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              workoutName.toUpperCase(),
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.accent,
              ),
            ),
          ),
        if (!isWorkout)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.badge),
              border: Border.all(
                color: AppColors.textSecondary.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              'REST DAY',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  // ── Rest Day Body ───────────────────────────────────────────────

  Widget _buildRestBody() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(
            Icons.self_improvement_rounded,
            size: 40,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Rest & Recovery',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Focus on light stretching, foam rolling, and staying hydrated. '
            'Sleep 7-9 hours to maximise muscle recovery and performance gains.',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
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
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Text(
          'No exercises scheduled.',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
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

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.row),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Exercise index
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
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
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
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
        AppSpacing.cardPadding,
        4,
        AppSpacing.cardPadding,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: isCompleted
            ? _buildCompletedBadge()
            : _buildStartButton(context, enabled: isToday),
      ),
    );
  }

  Widget _buildCompletedBadge() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: AppColors.green.withValues(alpha: 0.25),
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.green),
          const SizedBox(width: 6),
          Text(
            'COMPLETED',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: AppColors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(BuildContext context, {required bool enabled}) {
    return Material(
      color: enabled ? AppColors.accent : AppColors.textDisabled,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: enabled ? () => Navigator.of(context).pop() : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Center(
          child: Text(
            'START WORKOUT',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: enabled ? Colors.black : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dayNames[d.weekday - 1]}, ${monthNames[d.month - 1]} ${d.day}';
  }

  String _formatExerciseDetail({
    required String loggingType,
    required int sets,
    required String reps,
    required int restSecs,
  }) {
    switch (loggingType) {
      case 'timed':
        return '$sets sets \u00B7 ${reps}s \u00B7 ${restSecs}s rest';
      case 'cardio':
        return '$reps min \u00B7 ${restSecs}s rest';
      case 'distance':
        return '$reps \u00B7 ${restSecs}s rest';
      default:
        return '$sets sets \u00D7 $reps reps \u00B7 ${restSecs}s rest';
    }
  }
}
