part of 'screen.dart';

extension _BodyStats on _ProfileScreenState {

  // ── #3 Body Stats Card ──────────────────────────────────────────

  Widget _buildBodyStatsInner(double? weight, double? target, double? bmi, double? bodyFat) {
    // Format weight/target according to the user's units preference.
    String fmtWeight(double? kg) {
      if (kg == null) return '\u2014';
      if (_isMetric) return '${kg.toStringAsFixed(1)} kg';
      final lbs = kg * 2.20462;
      return '${lbs.toStringAsFixed(0)} lbs';
    }

    // Theme C \u00b7 Test #8 \u2014 inner-only: caller wraps with `_buildFlushCard`.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'BODY STATS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/profile/edit'),
              child: Text(
                'EDIT',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCell('Weight', fmtWeight(weight), AppColors.accent),
            _statCell('Target', fmtWeight(target), AppColors.ok),
            _statCell('BMI', bmi != null ? bmi.toStringAsFixed(1) : '\u2014', AppColors.info),
            _statCell('Body Fat', bodyFat != null ? '${bodyFat.toStringAsFixed(0)}%' : '\u2014', AppColors.warn),
          ],
        ),
      ],
    );
  }

  Widget _statCell(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
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
