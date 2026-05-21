part of 'screen.dart';

extension _WeekRows on _TrainScreenState {
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
}
