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
      // Unit 7 / OI-50 — the 4-source MAX described above now lives in ONE
      // place (WorkoutReadService.aggregateSetCount). Semantics identical;
      // this was the third hand-rolled copy of it.
      final isPr = log['is_pr'] == true;
      // OI-389 U7: the detail line is the pure `exerciseLogDetail`
      // (`utils/exercise_log_detail.dart`), so it is testable on its own.
      final detail = exerciseLogDetail(log);

      return ExpandedExerciseLogRow(name: name, detail: detail, isPr: isPr);
    }).toList();

    // "View Workout Card" button — shown when today's workout is saved
    Widget? viewCardButton;
    final workout = ref.read(activeWorkoutProvider);
    if (workout.isSaved && day.date != null) {
      final todayStr = istTodayStr();
      final dayStr = istDateStr(day.date!);
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

  String _formatDateKey(DateTime d) => istDateStr(d);
}

/// One logged exercise in the expanded DONE day (OI-371): the name wraps in
/// full and the detail sits on its own line under it, so neither is cut at
/// phone width or large text. TalkBack reads it as one node, PR first.
class ExpandedExerciseLogRow extends StatelessWidget {
  final String name;
  final String detail;
  final bool isPr;

  const ExpandedExerciseLogRow({
    super.key,
    required this.name,
    required this.detail,
    required this.isPr,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isPr ? Icons.emoji_events : Icons.check,
                // Scales with the text so it stays on the first line.
                size: MediaQuery.textScalerOf(context).scale(13),
                color: isPr ? AppColors.proGold : AppColors.ok,
                semanticLabel:
                    isPr ? WardroomCopy.personalRecordSemantics : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTypography.bodySm.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 2),
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
          ],
        ),
      ),
    );
  }
}
