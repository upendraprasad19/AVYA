part of 'screen.dart';

extension _ScheduleTemplate on _TrainScreenState {
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

    // APK Test #15.3 / Bug 4b (closes-diagnose: 8f3d22): collect
    // rejections so we can show the user which days were skipped.
    final List<DateTime> skippedCompleted = [];
    for (final date in sortedDates) {
      final result = await WorkoutScheduleService.instance
          .assignTemplateToDate(templateId, date);
      if (result is AssignTemplateRejected &&
          result.reason == AssignTemplateRejectionReason.alreadyCompleted) {
        skippedCompleted.add(date);
      }
    }
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(currentPlanProvider);
    ref.invalidate(todayWorkoutProvider);

    if (!context.mounted) return;

    // Show the "already completed" warning first (if any), then the
    // success snackbar for the dates that were actually written.
    if (skippedCompleted.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${skippedCompleted.length} '
            '${skippedCompleted.length == 1 ? 'day' : 'days'} already completed'
            ' — can\'t reschedule a logged workout.',
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final scheduledDates = sortedDates
        .where((d) => !skippedCompleted.contains(d))
        .toList();

    if (scheduledDates.isEmpty) return; // all rejected — no success toast

    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final String dateStr;
    if (scheduledDates.length == 1) {
      dateStr =
          '${monthNames[scheduledDates.first.month - 1]} ${scheduledDates.first.day}';
    } else {
      dateStr = '${scheduledDates.length} days';
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
}
