part of 'screen.dart';

extension _HealthSyncSheet on _ProfileScreenState {

  /// Opens the full BiometricSyncCard inside a bottom sheet so the rich
  /// widget (toggle, sleep-log button, live steps/sleep readouts) stays
  /// intact after the reorg.
  void _showHealthSyncSheet(BiometricData b) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.screenPadding),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(6),
          child: BiometricSyncCard(
            stepsToday: b.stepsToday,
            sleepHours: b.sleepHours,
            isSyncEnabled: b.isSyncEnabled,
            onToggleSync: () async {
              final newValue = !b.isSyncEnabled;
              unawaited(ref.read(biometricProvider.notifier).toggleSync(newValue));
              if (newValue && mounted) {
                ref.invalidate(todayStepsProvider);
              }
            },
            onLogSleep: (hours, quality) {
              ref.read(biometricProvider.notifier).logSleep(
                    hours: hours,
                    quality: quality,
                  );
            },
          ),
        ),
      ),
    );
  }
}
