part of 'screen.dart';

extension _PaceDetailSheet on _ProfileScreenState {

  Future<void> _showPaceDetailSheet({
    required double currentKg,
    required double targetKg,
    required String pacePreference,
    required String goal,
  }) async {
    final p = BmrCalculator.projectGoalDate(
      currentKg: currentKg,
      targetKg: targetKg,
      pacePreference: pacePreference,
    );
    if (!mounted) return;
    unawaited(showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GOAL PROJECTION',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Current: ${currentKg.toStringAsFixed(1)} kg → Target: ${targetKg.toStringAsFixed(1)} kg',
                style: AppTypography.h3
                    .copyWith(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Pace: ${pacePreference.toUpperCase()}',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'At this pace, projected ~${p.weeks.round()} weeks to goal.',
                style: AppTypography.body.copyWith(color: AppColors.textDim),
              ),
              const SizedBox(height: 4),
              Text(
                'Based on ${_paceRateLabel(pacePreference)} body-weight change per week and 7700 kcal ≈ 1 kg.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textGhost),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go('/profile/edit');
                  },
                  child: Text(
                    'CHANGE PACE →',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  static String _paceRateLabel(String pace) {
    switch (pace) {
      case 'slow':
        return '0.25%';
      case 'aggressive':
        return '0.75%';
      case 'balanced':
      default:
        return '0.5%';
    }
  }

  Widget _targetChip(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.h3.copyWith(
              fontSize: 13,
              color: AppColors.accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
