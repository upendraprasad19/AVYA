import '../../services/regenerate_plan_planner.dart';

/// OI-189 review B-4: `RegeneratePlanDiff` and `SwitchGoalDiff` each carried
/// a byte-identical private `_phaseNote`/`_dayLabel` pair with zero test
/// coverage (neither is reachable from outside its own library-private
/// class, so nothing could pin the three message forms or the zero-week
/// branch). Extracted here as pure top-level functions so both widgets can
/// delegate to ONE implementation and a plain unit test can call them
/// directly — no widget pump required. Both widgets keep their own private
/// wrapper methods (same name, same signature) so every existing call site
/// inside each file is untouched; only the body moved.

/// Short weekday + M/D label for an ISO date string, e.g. "Mon 9/14".
String phaseDayLabel(String date) {
  final d = DateTime.parse(date);
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${names[d.weekday - 1]} ${d.month}/${d.day}';
}

/// The phase-window note — null when the block fits the phase AND nothing
/// past `plan_end` will be cleared (nothing to say).
String? phaseNote(RegeneratePlanResult plan) {
  final end = plan.phaseEndsOn;
  if (end == null) return null;
  final clears = plan.clearsPastPhaseEnd;
  final fits = plan.totalWeeks >= plan.requestedWeeks;
  if (fits && clears == 0) return null;
  final clearsLine = clears == 0
      ? ''
      : ' $clears workout${clears == 1 ? '' : 's'} scheduled after that '
          'date will be cleared.';
  if (plan.totalWeeks == 0) {
    return 'This phase ended on ${phaseDayLabel(end)} — nothing left to '
        'regenerate.$clearsLine';
  }
  if (fits) {
    return 'This phase ends on ${phaseDayLabel(end)}.$clearsLine';
  }
  return 'Stops at this phase\'s end on ${phaseDayLabel(end)}.$clearsLine';
}
