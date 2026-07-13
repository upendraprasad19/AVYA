/// Detraining decay factor by the day-gap since the last logged session.
///
/// ONE band table, shared (no 2nd copy of the constants — #1 bug class):
/// - ⑦(a) phase-generation decay — `ProgressionResolver._detrainingFactor`
///   converts an IST date-STRING to a day-gap, then calls this.
/// - ⑦(b) session-time resume cut — `ActiveWorkoutNotifier.startWorkout` passes
///   `WorkoutRepository.getDaysSinceLastWorkout()` (an int) directly.
///
/// Reduce-only, matching the shipped ⑦(a) bands (Batch 3b-i):
///   ≤7d → 1.0 (none) · 8–21d → 0.925 (−7.5%) · 22–35d → 0.825 (−17.5%) · >35d → 0.5.
///
/// A non-positive gap returns 1.0 (≤7 band): `getDaysSinceLastWorkout()` yields
/// `-1` for a first-ever workout and `0` for one logged today — neither is cut.
double detrainingFactorForGap(int gapDays) {
  if (gapDays <= 7) return 1.0;
  if (gapDays <= 21) return 0.925;
  if (gapDays <= 35) return 0.825;
  return 0.50;
}
