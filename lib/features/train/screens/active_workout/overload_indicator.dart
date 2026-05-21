part of 'screen.dart';

// ── Overload Indicator ───────────────────────────────────────────
/// Shows a small indicator comparing current weight to last performance.
/// Green "PR!" if higher, orange arrow if same, red "Recovery" if lower.
class _OverloadIndicator extends ConsumerWidget {
  final String exerciseName;
  final double currentWeight;

  const _OverloadIndicator({
    required this.exerciseName,
    required this.currentWeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPerf = ref.watch(lastPerformanceProvider(exerciseName));
    final lastWeight = lastPerf.lastWeight;

    // No history or no weight entered — don't show indicator
    if (lastWeight == null || lastWeight <= 0 || currentWeight <= 0) {
      return const SizedBox.shrink();
    }

    final Color color;
    final String icon;

    if (currentWeight > lastWeight) {
      color = AppColors.ok;
      icon = '↑'; // up arrow
    } else if (currentWeight == lastWeight) {
      color = AppColors.warn;
      icon = '→'; // right arrow
    } else {
      color = AppColors.bad;
      icon = '↓'; // down arrow
    }

    return Text(
      icon,
      style: AppTypography.h2.copyWith(fontSize: 14, color: color),
    );
  }
}
