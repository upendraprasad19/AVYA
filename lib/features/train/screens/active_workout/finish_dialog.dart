part of 'screen.dart';

// ── Finish + Cancel Dialogs ──────────────────────────────────────

/// [onComplete] runs in the COMPLETE handler, before the dialog closes and the
/// (un-awaited) save starts: the screen clears its UNDO toast there (batch 2).
///
/// [logMode] (flag `enable_log_exercise_button`): the count is the WORKING sets
/// the save writes, and the guard lines name what will not be saved
/// (docs/plans/log-exercise-flip.md §3). Both modes: with nothing to save,
/// COMPLETE is disabled (OI-361, §3b).
void _showFinishDialog(
    BuildContext context, WidgetRef ref, ActiveWorkoutData data,
    {bool logMode = false, VoidCallback? onComplete}) {
  // Pre-fill with current elapsed seconds — user can edit before confirming.
  final mins = data.elapsedSeconds ~/ 60;
  final secs = data.elapsedSeconds % 60;
  final minCtrl = TextEditingController(text: mins.toString());
  final secCtrl = TextEditingController(text: secs.toString().padLeft(2, '0'));
  final blocked = !data.isSaved && !data.hasSaveableSet;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      // OFF stays non-scrolling (byte-identical) unless the block line is
      // shown: at 320 dp, a large font and the keyboard up it can overflow
      // (flip R7-01).
      scrollable: logMode || blocked,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.line2),
      ),
      title: Text(
        'Complete Workout?',
        style: AppTypography.h2.copyWith(fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._finishSummaryLines(data, logMode: logMode, blocked: blocked),
          const SizedBox(height: 14),
          Text(
            'DURATION',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          // A Wrap, not a Row: at 320 dp or a large font the fixed 56 px
          // fields + label overflowed (flip R4B-05). spacing 0: the `:` padding
          // and the SizedBox(8) are the gaps, so it lays out like the Row
          // until the Row would overflow.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              // Minutes field
              SizedBox(
                width: 56,
                child: TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: AppTypography.numeric.copyWith(
                    fontSize: 22,
                    color: AppColors.accent,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.bgRaise,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(color: AppColors.line2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(color: AppColors.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  ':',
                  style: AppTypography.numeric.copyWith(
                    fontSize: 22,
                    color: AppColors.textDim,
                  ),
                ),
              ),
              // Seconds field
              SizedBox(
                width: 56,
                child: TextField(
                  controller: secCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: AppTypography.numeric.copyWith(
                    fontSize: 22,
                    color: AppColors.accent,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.bgRaise,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(color: AppColors.line2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(color: AppColors.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MIN : SEC',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            'CONTINUE',
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
              letterSpacing: 2,
            ),
          ),
        ),
        TextButton(
          // OI-361: nothing to save, nothing to complete. Cancel stays on the
          // screen; the line above says how out.
          onPressed: blocked ? null : () {
            // `blocked` is a snapshot from when the dialog opened. Re-check
            // the live state before any side effect, so a state that lost its
            // last saveable set never clears the coach snapshot or the UNDO
            // toast for a completion the notifier then refuses (flip R7-05).
            // Close the dialog rather than leave a COMPLETE that does nothing
            // (B-pass finding 7); FINISH reopens it with the current state.
            final live = ref.read(activeWorkoutProvider);
            if (!live.isSaved && !live.hasSaveableSet) {
              Navigator.of(ctx).pop();
              return;
            }
            // Apply user-edited duration before completing
            final editedMins =
                (int.tryParse(minCtrl.text) ?? mins).clamp(0, 999);
            final editedSecs =
                (int.tryParse(secCtrl.text) ?? secs).clamp(0, 59);
            final totalSeconds = editedMins * 60 + editedSecs;
            ref
                .read(activeWorkoutProvider.notifier)
                .setElapsedSeconds(totalSeconds);
            // A7: clear mid-workout state immediately on completion so
            // the AI coach snapshot reflects null (session over) right away.
            ActiveWorkoutPersistence.clearState();
            onComplete?.call();
            Navigator.of(ctx).pop();
            ref.read(activeWorkoutProvider.notifier).completeWorkout();
          },
          child: Text(
            'COMPLETE',
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              color: blocked ? AppColors.textMute : AppColors.accent,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The count line and, in LOG mode, the guard lines (flip §3); the zero-set
/// block line in both modes (OI-361), above the re-opened / typed lines.
/// Guard lines have no maxLines: the dialog scrolls in LOG mode and when
/// blocked, and `capNames` caps the length.
List<Widget> _finishSummaryLines(ActiveWorkoutData data,
    {required bool logMode, required bool blocked}) {
  Widget line(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: AppTypography.bodySm.copyWith(color: color)),
      );
  final blockedLine =
      line(WardroomCopy.activeFinishZeroSetBlocked, AppColors.warn);
  if (!logMode) {
    return [
      Text(
        '${data.completedSets}/${data.totalSets} sets logged',
        style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
      ),
      if (blocked) blockedLine,
    ];
  }
  final counts = workingSetCounts(data);
  final lines = <Widget>[
    Text(
      WardroomCopy.activeFinishCountTemplate
          .replaceAll('{saved}', '${counts.saved}')
          .replaceAll('{total}', '${counts.total}'),
      style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
    ),
  ];
  if (blocked) lines.add(blockedLine);
  final guard = finishGuard(data);
  if (guard.reopenedUnsaved.isNotEmpty) {
    lines.add(line(
        WardroomCopy.activeFinishReopenedTemplate
            .replaceAll('{names}', capNames(guard.reopenedUnsaved)),
        AppColors.warn));
  }
  if (guard.typedUnsaved.isNotEmpty) {
    lines.add(line(
        WardroomCopy.activeFinishTypedTemplate
            .replaceAll('{names}', capNames(guard.typedUnsaved)),
        AppColors.warn));
  }
  // Blocked: the re-opened / typed lines still say what is pending; the
  // skip and partial lists add nothing when nothing saves (flip R7-04).
  if (blocked) return lines;
  if (guard.skipped.isNotEmpty) {
    lines.add(line(
        WardroomCopy.activeFinishSkippedTemplate
            .replaceAll('{names}', capNames(guard.skipped)),
        AppColors.textDim));
  }
  if (guard.partial.isNotEmpty) {
    lines.add(line(
        WardroomCopy.activeFinishPartialTemplate.replaceAll(
            '{items}',
            capNames([
              for (final p in guard.partial)
                WardroomCopy.activeFinishPartialItemTemplate
                    .replaceAll('{name}', p.name)
                    .replaceAll('{saved}', '${p.saved}')
                    .replaceAll('{working}', '${p.working}'),
            ])),
        AppColors.textDim));
  }
  return lines;
}

void _showCancelDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.line2),
      ),
      title: Text(
        'Cancel Workout?',
        style: AppTypography.h2.copyWith(fontSize: 18),
      ),
      content: Text(
        'All progress will be lost.',
        style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            'KEEP GOING',
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
              letterSpacing: 2,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            // A7: clear mid-workout state immediately on abandonment.
            ActiveWorkoutPersistence.clearState();
            Navigator.of(ctx).pop();
            ref.read(activeWorkoutProvider.notifier).cancelWorkout();
            context.go('/train');
          },
          child: Text(
            'CANCEL',
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
}
