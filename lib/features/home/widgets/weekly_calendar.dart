import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

/// Horizontal 7-day calendar strip synced with workout plan from Hive.
///
/// Reads scheduled_workouts via [WorkoutScheduleService] so Dashboard
/// and Workout screen always show the same data.
///
/// States:
///   - completed: cyan tint bg, check icon
///   - today: solid cyan bg, dash indicator
///   - planned (workout): border, small dot
///   - rest: gray, no indicator
///   - travel: amber tint, suitcase icon
///   - swapped: has 🔄 indicator
class WeeklyCalendar extends StatelessWidget {
  final void Function(DateTime date, Map<String, dynamic>? schedule)? onDayTap;
  final void Function(DateTime date, Map<String, dynamic>? schedule)? onDayLongPress;

  const WeeklyCalendar({super.key, this.onDayTap, this.onDayLongPress});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final weekStart = todayDate.subtract(Duration(days: now.weekday - 1));
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
        final isSwapped = schedule?['is_swapped'] as bool? ?? false;

        // Determine visual state
        final isCompleted = status == 'completed';
        final isWorkout = type == 'workout';
        final isRest = type == 'rest';
        final isTravel = status == 'travel';
        final isPlanned = isWorkout && status == 'planned';

        Color bgColor;
        Color borderColor;
        Color labelColor;
        Color dateColor;

        if (isToday) {
          bgColor = AppColors.accent;
          borderColor = AppColors.accent;
          labelColor = Colors.black.withValues(alpha: 0.6);
          dateColor = Colors.black;
        } else if (isCompleted) {
          bgColor = AppColors.accent.withValues(alpha: 0.07);
          borderColor = AppColors.accent.withValues(alpha: 0.28);
          labelColor = AppColors.accent.withValues(alpha: 0.7);
          dateColor = AppColors.textPrimary;
        } else if (isTravel) {
          bgColor = AppColors.proGold.withValues(alpha: 0.07);
          borderColor = AppColors.proGold.withValues(alpha: 0.28);
          labelColor = AppColors.proGold.withValues(alpha: 0.7);
          dateColor = AppColors.textPrimary;
        } else if (isPlanned) {
          bgColor = Colors.transparent;
          borderColor = AppColors.accent.withValues(alpha: 0.2);
          labelColor = AppColors.accent.withValues(alpha: 0.5);
          dateColor = AppColors.textPrimary;
        } else {
          // Rest or no plan
          bgColor = Colors.transparent;
          borderColor = AppColors.border;
          labelColor = AppColors.textSecondary;
          dateColor = AppColors.textSecondary;
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
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels[index],
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: dateColor,
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
                      isPast: isPast,
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
    required bool isPast,
  }) {
    if (isSwapped) {
      return Text(
        '\u{1F504}',
        style: GoogleFonts.getFont('DM Sans', fontSize: 8),
      );
    }
    if (isCompleted) {
      return Icon(
        Icons.check,
        size: 10,
        color: isToday ? Colors.black.withValues(alpha: 0.5) : AppColors.accent.withValues(alpha: 0.7),
      );
    }
    if (isTravel) {
      return Text(
        '\u{1F9F3}',
        style: GoogleFonts.getFont('DM Sans', fontSize: 8),
      );
    }
    if (isToday) {
      return Text(
        '\u2014',
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.black.withValues(alpha: 0.4),
        ),
      );
    }
    if (isPlanned) {
      return Icon(
        Icons.fitness_center,
        size: 9,
        color: isToday
            ? Colors.black.withValues(alpha: 0.5)
            : AppColors.accent.withValues(alpha: 0.5),
      );
    }
    if (isPast && !isRest) {
      // Past workout that wasn't completed = missed
      return Icon(
        Icons.remove,
        size: 8,
        color: AppColors.textSecondary.withValues(alpha: 0.3),
      );
    }
    if (isRest) {
      return Text(
        '\u2014',
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 8,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary.withValues(alpha: 0.3),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
