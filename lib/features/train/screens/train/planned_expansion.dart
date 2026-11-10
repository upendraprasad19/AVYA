part of 'screen.dart';

extension _PlannedExpansion on _TrainScreenState {
  // ── Planned Expansion (today, not yet started) ──────────────────

  Widget _buildPlannedExpansion(
      BuildContext context, WorkoutDayData day, bool hasLogs) {
    // Obs 5 follow-up (diagnose 6c2f91) — same resume-awareness as the hero
    // card; both route through beginWorkoutWithReadiness's discard guard.
    final active = ref.watch(activeWorkoutProvider);
    final isResuming = active.hasInProgressSession;
    final dayStr = istDateStr(day.date!);
    // Coach workout parity 1b (OI-490, decisions A + D): once something is
    // logged today, show it (LOGGED SO FAR) and offer COMPLETE WORKOUT. The
    // button follows the same rule as the tap (`canCompleteOnTap`) and hides
    // while an Active Workout session is in progress FOR TODAY (RESUME is
    // right there; finishing it completes the day). `hasInProgressSession`
    // has no date of its own, so a stale session from another day never
    // hides today's button; a session with no date does not either.
    final sessionDate = active.workoutDay?.date;
    final sessionIsToday = isResuming &&
        sessionDate != null &&
        istDateStr(sessionDate) == istTodayStr();
    final showComplete = hasLogs &&
        !sessionIsToday &&
        CoachDayCompletion.instance.canCompleteOnTap(dayStr);
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(50, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLogs) ...[
            _buildPreviewSectionLabel(
                WardroomCopy.trainLoggedSoFar, AppColors.ok),
            ..._loggedExerciseRows(dayStr),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: WardButton(
                label: 'EDIT LOG',
                leading: const Icon(Icons.edit_outlined,
                    size: 12, color: AppColors.textPrimary),
                variant: WardButtonVariant.ghost,
                size: WardButtonSize.small,
                onPressed: () => EditWorkoutLogSheet.show(context, day.date!),
              ),
            ),
          ],
          if (day.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No exercises scheduled',
                style:
                    AppTypography.bodySm.copyWith(color: AppColors.textDim),
              ),
            )
          else ...[
            // Warm-up section (collapsed by default)
            if (day.warmup.isNotEmpty) ...[
              _CollapsibleExerciseSection(
                label: 'WARM-UP',
                color: AppColors.warn,
                exercises: day.warmup,
                buildRow: (ex) => _buildPreviewExerciseRow(
                  ex, null, AppColors.warn,
                ),
              ),
              const SizedBox(height: 8),
              _buildPreviewSectionLabel('WORKOUT', AppColors.accent),
            ],
            // Main exercises
            ...List.generate(day.exercises.length, (index) {
              final ex = day.exercises[index];
              return _buildPreviewExerciseRow(
                  ex, index + 1, AppColors.accent);
            }),
            // Cool-down section (collapsed by default)
            if (day.cooldown.isNotEmpty) ...[
              const SizedBox(height: 8),
              _CollapsibleExerciseSection(
                label: 'COOL-DOWN',
                color: AppColors.info,
                exercises: day.cooldown,
                buildRow: (ex) => _buildPreviewExerciseRow(
                  ex, null, AppColors.info,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // START WORKOUT — gated on a non-empty plan so it can never no-op
            // (diagnose 2026-06-06: a content-less restored day rendered a
            // START button that started nothing — "i cant start the workout").
            // A genuinely empty day shows only the "No exercises scheduled"
            // line above. Q6 keeps it free; this only adds the content gate.
            WardButton(
              label: isResuming ? 'RESUME WORKOUT' : 'START WORKOUT',
              leading: const Icon(Icons.play_arrow_rounded,
                  size: 16, color: AppColors.bgDeep),
              onPressed: () async {
                // ⑥ Batch 6 (W2.3) — readiness check-in (flag-gated) before start.
                await beginWorkoutWithReadiness(context, ref, day);
                if (context.mounted) context.go('/train/active-workout');
              },
            ),
          ],
          if (showComplete) ...[
            const SizedBox(height: 8),
            _CompleteTodayButton(dateStr: dayStr),
          ],
        ],
      ),
    );
  }
}

/// Coach workout parity 1b (OI-490, decision D): Train's COMPLETE WORKOUT
/// button. The ONE tap path ([CoachDayCompletion.completeOnTap], door
/// `trainTap`, `completed_via: 'train_tap'`), disabled while a tap is in
/// flight; one snackbar line per result (approved copy).
class _CompleteTodayButton extends ConsumerStatefulWidget {
  const _CompleteTodayButton({required this.dateStr});
  final String dateStr;

  @override
  ConsumerState<_CompleteTodayButton> createState() =>
      _CompleteTodayButtonState();
}

class _CompleteTodayButtonState extends ConsumerState<_CompleteTodayButton> {
  bool _busy = false;

  Future<void> _complete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await CoachDayCompletion.instance.completeOnTap(
          date: widget.dateStr, door: CompletionDoor.trainTap);
      if (!mounted) return;
      if (result.isSuccess) {
        invalidateWorkoutSurfaces(ref.invalidate, source: 'train_complete');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message,
            style: AppTypography.body.copyWith(
                color: result.isSuccess ? AppColors.ok : AppColors.bad),
          ),
          backgroundColor: AppColors.card,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A WardButton label neither wraps nor ellipsizes; COMPLETE WORKOUT is
    // the longest label in this expansion, so it scales down rather than
    // overflow at 360 dp or a large text scale.
    // Full width like START WORKOUT when it fits (min width = the row);
    // scaled down only when the label would not.
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: WardButton(
            label: WardroomCopy.trainCompleteWorkout,
            leading: const Icon(Icons.check_rounded,
                size: 16, color: AppColors.accent),
            variant: WardButtonVariant.outline,
            fullWidth: false,
            onPressed: _busy ? null : _complete,
          ),
        ),
      ),
    );
  }
}
