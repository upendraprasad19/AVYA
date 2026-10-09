part of 'screen.dart';

// ── Active Workout Header + Progress ─────────────────────────────

String _getDayType(String name) {
  if (name.contains('CHEST') || name.contains('TRICEPS')) return 'PUSH DAY';
  if (name.contains('BACK') || name.contains('BICEPS')) return 'PULL DAY';
  if (name.contains('LEG')) return 'LEG DAY';
  if (name.contains('HIIT') || name.contains('CARDIO')) return 'CARDIO';
  return name;
}

Widget _buildHeader(BuildContext context, ActiveWorkoutData data) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    decoration: const BoxDecoration(
      color: AppColors.bgDeep,
      border: Border(
        bottom: BorderSide(color: AppColors.line2),
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              if (Navigator.canPop(context)) {
                context.pop();
              } else {
                context.go('/train');
              }
            },
            child: const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.arrow_back_ios_new,
                  color: AppColors.textPrimary, size: 18),
            ),
          ),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getDayType(data.workoutDay?.name ?? '').toUpperCase(),
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${data.completedSets} / ${data.totalSets} SETS${data.liveVolumeKg > 0 ? ' · ${data.liveVolumeKg.toStringAsFixed(0)}KG VOLUME' : ''}',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Timer badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.27),
              ),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: Column(
              children: [
                Text(
                  data.timerFormatted,
                  style: AppTypography.numeric.copyWith(
                    fontSize: 17,
                    color: AppColors.accent,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'ELAPSED',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 7,
                    color: AppColors.textDim,
                    letterSpacing: 1.5,
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

Widget _buildProgressBar(double progress, int pctInt) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 7, 16, 4),
    child: Row(
      children: [
        Expanded(child: WardBar(pct: progress, height: 4)),
        const SizedBox(width: 8),
        Text(
          '$pctInt%',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.accent,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}
