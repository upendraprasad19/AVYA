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
      builder: (sheetCtx) => Consumer(
        // Obs 5 (2026-06-05): watch the provider INSIDE the sheet so the card
        // rebuilds when toggleSync's invalidateSelf fires. Previously the sheet
        // rendered a captured BiometricData snapshot → "Connected" only showed
        // after closing + reopening the sheet.
        builder: (consumerCtx, sheetRef, _) {
          final b = sheetRef.watch(biometricProvider);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(consumerCtx).viewInsets.bottom,
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
                  // AWAIT so the permission result + invalidateSelf settle; the
                  // watched provider then rebuilds the card to its true
                  // connected state in-place (Obs 5).
                  await ref
                      .read(biometricProvider.notifier)
                      .toggleSync(newValue);
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
          );
        },
      ),
    );
  }
}
