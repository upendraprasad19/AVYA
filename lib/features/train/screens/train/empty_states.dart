part of 'screen.dart';

extension _EmptyStates on _TrainScreenState {
  Widget _buildGeneratingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Generating your plan...',
            style: AppTypography.h2.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Building a personalised workout schedule\nbased on your profile',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// [isFutureUngeneratedPhase] / [currentPhase]: a PRO user can page ahead
  /// into a phase group beyond their actual current phase
  /// (`isFutureUngeneratedPhase(selectedWeek)`, see
  /// `lib/core/utils/hold_week_labels.dart`) — that phase genuinely has no
  /// generated schedule yet, which is expected, not a glitch. Founder
  /// observation 2026-09-16: the generic "No workouts scheduled" empty
  /// state read like a bug here rather than an intentional gate; other
  /// fitness apps (Fitbod, JuggernautAI, Ladder) always pair a locked
  /// future block with a lock icon + a stated unlock condition instead of a
  /// bare empty state. Diagnose — see docs/diagnoses/.
  Widget _buildEmptyWeek({
    bool isFutureUngeneratedPhase = false,
    int currentPhase = 1,
  }) {
    final copy =
        isFutureUngeneratedPhase ? futurePhaseUnlockCopy(currentPhase) : null;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: EmptyState(
        icon: copy != null ? Icons.lock_open_outlined : Icons.fitness_center,
        title: copy?.title ?? 'No workouts scheduled',
        subtitle:
            copy?.subtitle ?? 'This week has no workouts in your plan.',
      ),
    );
  }
}
