import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import '../providers/home_provider.dart';

/// Horizontal 7-day calendar strip synced with workout plan from Hive.
///
/// Reads scheduled_workouts via [WorkoutScheduleService] so Dashboard
/// and Workout screen always show the same data. Uses [calendarWeekProvider]
/// to rebuild automatically when schedule data changes.
///
/// States (Wardroom):
///   - today: sharp 2-px gold outline, accent day initial
///   - completed: accent tint bg + gold tick
///   - planned: sharp outline, small dumbbell
///   - rest: muted, em-dash
///   - travel: gold tint, suitcase glyph
///   - missed: bad-tinted, minus glyph
class WeeklyCalendar extends ConsumerWidget {
  final void Function(DateTime date, Map<String, dynamic>? schedule)? onDayTap;
  final void Function(DateTime date, Map<String, dynamic>? schedule)?
      onDayLongPress;

  const WeeklyCalendar({super.key, this.onDayTap, this.onDayLongPress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the calendar provider so this widget rebuilds when schedule changes.
    ref.watch(calendarWeekProvider);

    // APK Test #6 spec §3.1 — calendar boundaries derive from IST.
    // istMidnight strips time-of-day; mondayOfIst yields the IST Monday.
    final now = DateTime.now();
    final todayDate = istMidnight(now);
    final weekStart = mondayOfIst(now);
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final service = WorkoutScheduleService.instance;
    final schedules = <Map<String, dynamic>?>[];
    for (final day in days) {
      schedules.add(service.getScheduleForDate(day));
    }

    return Row(
      children: List.generate(7, (index) {
        final day = days[index];
        final schedule = schedules[index];
        final isToday = day == todayDate;
        final isPast = day.isBefore(todayDate);

        final type = schedule?['type'] as String? ?? 'none';
        final status = schedule?['status'] as String? ?? 'none';
        final reason = schedule?['reason'] as String? ?? '';
        final isSwapped = schedule?['is_swapped'] as bool? ?? false;

        final isCompleted = status == 'completed';
        final isWorkout = type == 'workout';
        final isCustomTemplate = type == 'custom_template';
        final isRest = type == 'rest';
        final isTravel = status == 'travel';
        final isPlanned =
            (isWorkout || isCustomTemplate) && status == 'planned';
        final isMissed = isPast && !isCompleted && (isWorkout || isCustomTemplate);
        // APK Test #6 obs #7 — pre-onboarding days (joined later in
        // the calendar week) render distinctly: light-grey 'Joined later'
        // glyph, NOT the standard rest em-dash. Distinct from isMissed
        // (which uses bad-tinted minus glyph) because the user wasn't
        // on the platform — it's not a failure.
        final isPreOnboarding = isRest && reason == 'pre_onboarding';

        Color bgColor;
        Color borderColor;
        Color labelColor;
        Color dateColor;

        if (isToday) {
          // Sharp 2-px gold outline — today marker
          bgColor = AppColors.accentSoft;
          borderColor = AppColors.accent;
          labelColor = AppColors.accent;
          dateColor = AppColors.accent;
        } else if (isCompleted) {
          bgColor = AppColors.accentSoft;
          borderColor = AppColors.accent.withValues(alpha: 0.33);
          labelColor = AppColors.accent.withValues(alpha: 0.8);
          dateColor = AppColors.textPrimary;
        } else if (isTravel) {
          bgColor = AppColors.proGoldTint;
          borderColor = AppColors.proGold.withValues(alpha: 0.33);
          labelColor = AppColors.proGold;
          dateColor = AppColors.textPrimary;
        } else if (isPlanned) {
          bgColor = Colors.transparent;
          borderColor = AppColors.line2;
          labelColor = AppColors.textMute;
          dateColor = AppColors.textPrimary;
        } else if (isPreOnboarding) {
          // Light-grey 'Joined later' treatment — visually de-emphasised
          // since the user wasn't on the platform. Border slightly fainter
          // than line2.
          bgColor = Colors.transparent;
          borderColor = AppColors.line2.withValues(alpha: 0.5);
          labelColor = AppColors.textGhost;
          dateColor = AppColors.textGhost;
        } else if (isMissed) {
          bgColor = AppColors.bad.withValues(alpha: 0.08);
          borderColor = AppColors.bad.withValues(alpha: 0.25);
          labelColor = AppColors.bad.withValues(alpha: 0.7);
          dateColor = AppColors.textDim;
        } else {
          // Rest or no plan
          bgColor = Colors.transparent;
          borderColor = AppColors.line2;
          labelColor = AppColors.textMute;
          dateColor = AppColors.textDim;
        }

        return Expanded(
          child: GestureDetector(
            onTap: () => onDayTap?.call(day, schedule),
            onLongPress: () => onDayLongPress?.call(day, schedule),
            child: Container(
              margin: EdgeInsets.only(
                left: index == 0 ? 0 : 2,
                right: index == 6 ? 0 : 2,
              ),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                  color: borderColor,
                  width: isToday ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels[index],
                    style: AppTypography.monoXs.copyWith(
                      color: labelColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: AppTypography.body.copyWith(
                      color: dateColor,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 13,
                    child: _buildIndicator(
                      isToday: isToday,
                      isCompleted: isCompleted,
                      isPlanned: isPlanned,
                      isRest: isRest,
                      isTravel: isTravel,
                      isSwapped: isSwapped,
                      isMissed: isMissed,
                      isPreOnboarding: isPreOnboarding,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildIndicator({
    required bool isToday,
    required bool isCompleted,
    required bool isPlanned,
    required bool isRest,
    required bool isTravel,
    required bool isSwapped,
    required bool isMissed,
    required bool isPreOnboarding,
  }) {
    if (isSwapped) {
      return const Text('\u{1F504}', style: TextStyle(fontSize: 8));
    }
    // Bug a9f3d2 (APK Test #13): when both isToday and isCompleted are true,
    // the full-gold today-border makes a gold checkmark invisible. Use
    // AppColors.ok (green) so the two signals are visually independent:
    //   gold border = "this is today"
    //   green check = "workout completed"
    if (isCompleted && isToday) {
      return const Icon(Icons.check, size: 10, color: AppColors.ok);
    }
    if (isCompleted) {
      return const Icon(Icons.check, size: 10, color: AppColors.accent);
    }
    if (isTravel) {
      return const Text('\u{1F9F3}', style: TextStyle(fontSize: 8));
    }
    if (isToday && isPlanned) {
      return const Icon(
        Icons.fitness_center,
        size: 9,
        color: AppColors.accent,
      );
    }
    if (isToday) {
      return Text(
        '\u2014',
        style: AppTypography.monoXs.copyWith(
          color: AppColors.accent,
        ),
      );
    }
    if (isPlanned) {
      return Icon(
        Icons.fitness_center,
        size: 9,
        color: AppColors.textMute,
      );
    }
    if (isPreOnboarding) {
      // 'Joined later' glyph \u2014 small dot in textGhost so the cell reads
      // as 'no activity, but not a failure'. Tooltip-equivalent surfaces
      // via the day-detail sheet on tap.
      return Icon(
        Icons.circle,
        size: 4,
        color: AppColors.textGhost,
      );
    }
    if (isMissed) {
      return Icon(
        Icons.remove,
        size: 8,
        color: AppColors.bad.withValues(alpha: 0.6),
      );
    }
    if (isRest) {
      return Text(
        '\u2014',
        style: AppTypography.monoXs.copyWith(
          color: AppColors.textDisabled,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
