part of 'screen.dart';

extension _ExpandedExercises on _TrainScreenState {
  // ── Expanded Exercises (W5) ─────────────────────────────────

  Widget _buildExpandedExercises(WorkoutDayData day) {
    final logs =
        WorkoutRepository.instance.getExerciseLogsForDate(day.date!);

    if (logs.isEmpty) {
      // audit-2026-05-17 OI-05 — differentiate "marked done outside
      // the app" (schedule.status=completed with NO exlog rows — the
      // user used markCompleted directly without active workout) from
      // a true "no data yet" state (e.g. fresh-install restore race).
      // Pre-fix copy said only "No exercise data logged" which was
      // misleading on completed days.
      final msg = day.isDone
          ? 'Marked done outside the app — no exercises were logged.'
          : 'No exercise data logged';
      return Padding(
        padding: const EdgeInsets.fromLTRB(50, 0, 14, 10),
        child: Text(
          msg,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
            fontStyle: day.isDone ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }

    // Build exercise log rows
    final logRows = logs.map((log) {
      final name = log['exercise_name'] as String? ?? 'Exercise';
      // APK Test #12.4 / Task #2 — sibling renderer caught up to the
      // 4-source MAX policy. Pre-fix this widget read only
      // `sets_completed` (returns 0 since WriteService writes
      // `set_number`); Test #12.2 patched the bottom sheet but missed
      // this inline calendar-row expansion. Same drift class as the
      // founder's "0 sets · 26 reps · 85kg" screenshot 2026-05-06.
      final setNum = (log['set_number'] as num?)?.toInt() ?? 0;
      final setsCompleted = (log['sets_completed'] as num?)?.toInt() ?? 0;
      final setsArr = log['sets'];
      final setsArrLen = setsArr is List ? setsArr.length : 0;
      final setsDetail = log['sets_detail'];
      final setsDetailLen = setsDetail is List ? setsDetail.length : 0;
      final sets = [setNum, setsCompleted, setsArrLen, setsDetailLen]
          .reduce((a, b) => a > b ? a : b);
      final loggingType = log['logging_type'] as String? ?? 'weight_reps';
      final isPr = log['is_pr'] == true;

      // audit-2026-05-16 reader-side / Obs 3 \u2014 per-set MAX semantics.
      // Top-level `reps_completed` is SUM and `duration_seconds` is SUM
      // per Test #6 writer contract. Pre-fix this widget surfaced
      // cumulative reps (Hanging Leg Raise "7 sets \u00b7 85 reps" when the
      // user logged 5 sets of 17) and cumulative duration. Same class
      // as the PR cumulative bug in `loadAllExercisePRs`.
      //
      // For non-weighted types we now derive best-per-set from `sets[]`
      // (canonical per-set array). Top-level fallback applies only for
      // legacy single-set rows (where SUM == per-set value).
      // OI-02 / OI-08 — per-set MAX semantic centralised in WorkoutReadService.
      // closes-diagnose: 2026-05-17-oi-02-read-services
      final perSetMaxReps = WorkoutReadService.bestPerSetReps(log);
      final perSetMaxDur = WorkoutReadService.bestPerSetDuration(log);
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      // For weight_reps the writer's top-level `weight_kg` is already
      // MAX, so it's safe to use directly.
      final totalDuration = WorkoutReadService.bestPerSetDuration(log);

      String detail;
      if (loggingType == 'timed') {
        final secs = perSetMaxDur > 0 ? perSetMaxDur : totalDuration;
        final mins = secs ~/ 60;
        final tail = secs % 60;
        final dur = '${mins > 0 ? '${mins}m ' : ''}${tail}s';
        detail = sets > 1
            ? '$sets sets \u00b7 best $dur'
            : dur;
      } else if (loggingType == 'cardio') {
        final dist = (log['distance_km'] as num?)?.toDouble() ?? 0;
        detail =
            '${totalDuration ~/ 60} min \u00b7 ${dist.toStringAsFixed(1)} km';
      } else if (weight > 0) {
        detail =
            '$sets sets \u00b7 $perSetMaxReps reps \u00b7 ${weight.toStringAsFixed(1)} kg';
      } else {
        detail = '$sets sets \u00b7 $perSetMaxReps reps';
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
}
