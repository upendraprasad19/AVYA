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

  Widget _buildEmptyWeek() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: const EmptyState(
        icon: Icons.fitness_center,
        title: 'No workouts scheduled',
        subtitle: 'This week has no workouts in your plan.',
      ),
    );
  }
}
