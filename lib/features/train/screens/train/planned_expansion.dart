part of 'screen.dart';

extension _PlannedExpansion on _TrainScreenState {
  // ── Planned Expansion (today, not yet started) ──────────────────

  Widget _buildPlannedExpansion(BuildContext context, WorkoutDayData day) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(50, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              label: 'START WORKOUT',
              leading: const Icon(Icons.play_arrow_rounded,
                  size: 16, color: AppColors.bgDeep),
              onPressed: () async {
                // ⑥ Batch 6 (W2.3) — readiness check-in (flag-gated) before start.
                await beginWorkoutWithReadiness(context, ref, day);
                if (context.mounted) context.go('/train/active-workout');
              },
            ),
          ],
        ],
      ),
    );
  }
}
