part of 'screen.dart';

// ── Overload Indicator ───────────────────────────────────────────
/// Shows a small indicator comparing current weight to last performance.
/// Green "PR!" if higher, orange arrow if same, red "Recovery" if lower.
class _OverloadIndicator extends ConsumerWidget {
  final String exerciseName;
  final double currentWeight;
  // ⑦(b) + ⑥ 6-B: the active session's EFFECTIVE load factor (1.0 = no cut) —
  // the LARGER of the ⑦b detraining gap-cut and the ⑥ readiness deload (min
  // factor, from ActiveWorkoutData.effectiveLoadFactor). The indicator compares
  // against the CUT TARGET (last × factor) so an unedited reduced prefill reads
  // neutral → instead of red ↓ ("never shame") — for a readiness deload too.
  final double loadFactor;

  const _OverloadIndicator({
    required this.exerciseName,
    required this.currentWeight,
    this.loadFactor = 1.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPerf = ref.watch(lastPerformanceProvider(exerciseName));
    final lastWeight = lastPerf.lastWeight;

    // No history or no weight entered — don't show indicator
    if (lastWeight == null || lastWeight <= 0 || currentWeight <= 0) {
      return const SizedBox.shrink();
    }

    // ⑦(b)/⑥: compare against the session target = last × effective cut factor,
    // computed the SAME way as the prefill (exercise_card
    // `w = lastWeight * effectiveLoadFactor(ex)`). Dart guarantees
    // double.parse(d.toString()) == d, so an unedited reduced prefill equals this
    // target exactly → reads → (neutral), never red ↓. factor 1.0 (no cut) →
    // target == lastWeight → byte-identical to pre-⑦b.
    final target = lastWeight * loadFactor;

    final Color color;
    final String icon;

    if (currentWeight > target) {
      color = AppColors.ok;
      icon = '↑'; // up arrow
    } else if (currentWeight == target) {
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
