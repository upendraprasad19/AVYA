part of 'screen.dart';

// ── Finish + Cancel Dialogs ──────────────────────────────────────

void _showFinishDialog(
    BuildContext context, WidgetRef ref, ActiveWorkoutData data) {
  // Pre-fill with current elapsed seconds — user can edit before confirming.
  final mins = data.elapsedSeconds ~/ 60;
  final secs = data.elapsedSeconds % 60;
  final minCtrl = TextEditingController(text: mins.toString());
  final secCtrl = TextEditingController(text: secs.toString().padLeft(2, '0'));

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
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
          Text(
            '${data.completedSets}/${data.totalSets} sets logged',
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 14),
          Text(
            'DURATION',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
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
          onPressed: () {
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
            Navigator.of(ctx).pop();
            ref.read(activeWorkoutProvider.notifier).completeWorkout();
          },
          child: Text(
            'COMPLETE',
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              color: AppColors.accent,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    ),
  );
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
