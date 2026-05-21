part of 'screen.dart';

// ── Workout Completion Screen ────────────────────────────────────
// Shown when data.isComplete == true. Surfaces PRs, share-receipt
// CTA, and a "Back to Workouts" exit button.

Widget _buildCompleteScreen(
  BuildContext context,
  WidgetRef ref,
  ActiveWorkoutData data,
) {
  final prs = data.detectedPRs;

  return Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.ok.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    color: AppColors.ok, size: 48),
              ),
              const SizedBox(height: 20),
              Text(
                'Workout Complete!',
                style: AppTypography.h1.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                '${data.completedSets} SETS LOGGED · ${data.timerFormatted}',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () =>
                    ref.read(activeWorkoutProvider.notifier).reopenWorkout(),
                child: Text(
                  'REVIEW WORKOUT',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 2,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent,
                  ),
                ),
              ),

              // PR callout
              if (prs.isNotEmpty) ...[
                const SizedBox(height: 16),
                WardCard(
                  variant: WardCardVariant.hero,
                  child: Column(
                    children: [
                      Text(
                        'NEW PERSONAL RECORDS!',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.proGold,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...prs.map((pr) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              pr,
                              style:
                                  AppTypography.h3.copyWith(fontSize: 13),
                            ),
                          )),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Share Your Session button — opens Workout Receipt sheet
              WardButton(
                label: 'SHARE YOUR SESSION',
                variant: WardButtonVariant.outline,
                onPressed: () => _showWorkoutReceipt(context, data),
              ),
              const SizedBox(height: AppSpacing.inlineGap),

              // Share as Video — hidden until Remotion/Lambda infra is live
              // _buildVideoShareRow(data),

              WardButton(
                label: 'BACK TO WORKOUTS',
                onPressed: () {
                  ref.read(activeWorkoutProvider.notifier).cancelWorkout();
                  context.go('/train');
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showWorkoutReceipt(BuildContext context, ActiveWorkoutData data) {
  // APK Test #12.6 — prefer the Hive-backed receipt builder when
  // [completeWorkout] has already persisted the logs. It populates
  // perSetBreakdown (giving WardSetChips real per-set chips) and
  // computes volume from the exact per-set sum the cloud projection
  // ships. Falls back to the in-memory builder when Hive somehow
  // lacks the logs (e.g. write-failure or no workoutDay date).
  final workoutDate = data.workoutDay?.date;
  WorkoutReceiptData? receiptData;
  if (workoutDate != null) {
    receiptData = WorkoutReceiptData.fromExerciseLogs(workoutDate);
  }
  receiptData ??= WorkoutReceiptData.fromActiveWorkout(data);
  WorkoutReceiptSheet.show(context, receiptData);
}
