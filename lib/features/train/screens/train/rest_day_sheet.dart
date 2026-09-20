part of 'screen.dart';

extension _RestDaySheet on _TrainScreenState {
  // ── Rest Day Sheet ────────────────────────────────────────────

  void _showRestDaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '🧘 Rest Day — Recovery',
              style: AppTypography.h2,
            ),
            const SizedBox(height: 8),
            Text(
              'This is when your muscles actually grow. Use today to recover well.',
              style: AppTypography.body.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 20),
            Text(
              'RECOVERY TIPS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            ...[
              ('🧘', 'Stretch for 10 minutes'),
              ('🚶', 'Light walk 20–30 minutes'),
              ('🔁', 'Foam roll sore muscles'),
              ('💧', 'Drink at least 3L of water'),
              ('😴', 'Aim for 7–9 hours of sleep tonight'),
            ].map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Text(tip.$1, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Text(
                        tip.$2,
                        style: AppTypography.body,
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
            WardButton(
              label: 'LOG WEIGHT',
              leading: const Icon(Icons.monitor_weight_outlined,
                  size: 16, color: AppColors.accent),
              variant: WardButtonVariant.outline,
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => const WeightLogSheet(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
