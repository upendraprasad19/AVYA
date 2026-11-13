// Unit 2B (OI-452, docs/plans/2026-11-13-generator-step2b-day-floor.md §2, founder d30-d33): the ONE restated budget
// invariant every test reader of the weekly top and the day's time goes through, so no reader is loosened ad hoc.
//
// - Week: `week(g) <= weeklyTop(g) + the sets the 3-exercise floor seated past g's top` (each such seat names g in its
//   `FloorSeat.overTop`; 2 sets a seat, so the allowance is never below the real excess).
// - The session cap is never passed (the floor checks it; no allowance here).
// - Time: within the budget, plus the day's `countForced` seconds (pass A2, at most
//   `SessionBudget.maxForcedOverSeconds` in total), plus the seconds of the day's `overClock` floor seats (no bound,
//   d33). A floor seat is never in `countForced`.
//
// Pure Dart; it reads `AllocationStats` only, so a reader passes the stats of the variant whose week it is checking.
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

class BudgetInvariantOracle {
  BudgetInvariantOracle._();

  /// The sets the floor seated past [group]'s weekly top in this variant's week (0 when [stats] is null).
  static int floorOverTopSets(AllocationStats? stats, String group) {
    if (stats == null) return 0;
    var n = 0;
    for (final seats in stats.floorSeats.values) {
      for (final s in seats) {
        if (s.overTop.contains(group)) n += s.sets;
      }
    }
    return n;
  }

  /// The weekly ceiling a reader checks [group] against: its [top] plus [floorOverTopSets].
  static int weekCeiling(int top, AllocationStats? stats, String group) => top + floorOverTopSets(stats, group);

  /// Seconds of the rows of [exercises] the floor seated on [day] although they did not fit the day's remaining
  /// seconds (`overClock`), priced by [secondsOf]. Matched by name, like the readers' `countForced` sums.
  static double floorOverClockSeconds(
    AllocationStats? stats,
    int day,
    Iterable<PlannedExercise> exercises,
    double Function(PlannedExercise) secondsOf,
  ) {
    final seats = stats?.floorSeats[day];
    if (seats == null) return 0;
    var t = 0.0;
    for (final s in seats) {
      if (!s.overClock) continue;
      for (final e in exercises) {
        if (e.exerciseName == s.name) t += secondsOf(e);
      }
    }
    return t;
  }

  /// Seconds of the rows pass A2 count-forced on [day] (`countForced`), priced by [secondsOf], uncapped.
  static double countForcedSeconds(
    AllocationStats? stats,
    int day,
    Iterable<PlannedExercise> exercises,
    double Function(PlannedExercise) secondsOf,
  ) {
    final forced = stats?.countForced[day];
    if (forced == null) return 0;
    var t = 0.0;
    for (final f in forced) {
      for (final e in exercises) {
        if (e.exerciseName == f.name) t += secondsOf(e);
      }
    }
    return t;
  }

  /// The seconds [day] may run past its budget: the count-forced part (bounded by [maxForcedOverSeconds]) plus every
  /// `overClock` floor seat's seconds (unbounded, d33).
  static double excusedSeconds(
    AllocationStats? stats,
    int day,
    Iterable<PlannedExercise> exercises,
    double Function(PlannedExercise) secondsOf, {
    required double maxForcedOverSeconds,
  }) {
    final forced = countForcedSeconds(stats, day, exercises, secondsOf);
    return (forced > maxForcedOverSeconds ? maxForcedOverSeconds : forced) +
        floorOverClockSeconds(stats, day, exercises, secondsOf);
  }

  /// True when no floor seat on any day of [stats] is also named in `countForced` on that day (v5, round 3 P1).
  static bool floorSeatsDisjointFromCountForced(AllocationStats stats) {
    for (final e in stats.floorSeats.entries) {
      final forced = {for (final f in stats.countForced[e.key] ?? const <({String name, int sets})>[]) f.name};
      for (final s in e.value) {
        if (forced.contains(s.name)) return false;
      }
    }
    return true;
  }
}
