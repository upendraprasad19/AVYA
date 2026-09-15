---
bug_id: 5e8a1c
date: 2026-05-31
batch: year-simulation-2026-05-31
status: fixed
symptom: >
  Surfaced by the year-simulation harness: after amar completed Phase 1 (15 of
  16 scheduled workouts over 4 weeks, ~85% adherence with a single missed day),
  the rank did NOT progress — it stayed at SD2 (Seaman 2nd Class) even though the
  SD1 gate is only streak>=7 + week>=1. The /dev rank panel showed "Next: SD1,
  Days to next: 0" while Current stayed SD2, and the end-of-sim report logged
  "End rank: SD2". Earlier the founder had also seen "streak only 3" despite
  completing every workout. Root cause is the same: the read-only streak walk
  collapses at any day a freeze was previously spent on.
concept: streaks
sot_registry_entry: streaks
blast_radius: account
writers:
  - { file: lib/features/train/repositories/workout_repository.dart, method: consumeMissedDayIfFreezeAvailable → _calculateStreak(consume:true) persists usedDates + freezesAvailable via StreakProgressService.commitConsume, line: 290 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method: currentStreak → _calculateStreak(consume:false) walk-back (the buggy already-frozen-day branch), line: 266 }
  - { file: lib/core/services/rank_service.dart, method: _readEvaluationState reads repo.currentStreak() as the streakDays gate input, line: 410 }
  - { file: lib/core/services/rank_service.dart, method: _qualifies rejects SD1/LS when streakDays < gate.streakAtLeast, line: 473 }
hive_key_prefix: "schedule_ (read) / streak_freeze_used_dates (state)"
hive_key_formula: "schedule_${istDateStr(date)}; freeze state in userBox['progress']['streak_freeze_used_dates']"
sync_methods: [_syncStreaks]
restore_methods: [_restoreFreezes]
cloud_table: streaks
cloud_columns: []
contract_test_path: test/contracts/streak_frozen_day_persists_protection_test.dart
ist_handling:
  - { site: _calculateStreak walk-back date key, helper: formatDateKey (== istDateStr), status: ok }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a — streak walk reads user-scoped workoutBox + userBox via the existing
  HiveUserSession guard. This is a per-user count-computation bug, not a
  cross-account exposure. No data crosses accounts.
forbidden_patterns_checked:
  - { pattern: "already-frozen missed day falls through to the streak-break else branch", absent: true }
proposed_fix: >
  In WorkoutRepository._calculateStreak the only branch that referenced
  usedDates was the consume guard `freezesAvailable > 0 &&
  !usedDates.contains(dateStr)`. A missed day that had ALREADY been covered by a
  spent freeze (freezesAvailable now 0, day already in usedDates) failed that
  guard and fell through to `else → break`, collapsing the streak at the first
  historically-frozen day on every read-only recompute. A freeze must protect
  its day permanently. Fix: add an explicit `usedDates.contains(dateStr)` branch
  BEFORE the consume branch that treats the day as covered (continue) — never
  breaks, never double-consumes. Behavior-preserving on the first walk (usedDates
  empty → identical consume-or-break); on later walks the spent-freeze day stays
  protected. Restores streak accumulation so the sailor-track rank gates (SD1
  streak>=7, LS streak>=14) can actually qualify.
regression_test_planned:
  - test/contracts/streak_frozen_day_persists_protection_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "workout_repository.dart _calculateStreak: added usedDates.contains protection branch before the consume branch; flutter analyze clean" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "streak_frozen_day_persists_protection_test.dart: walk spans an already-frozen day (streak=4 vs pre-fix 2); fresh missed day with no freeze still breaks (streak=1); read stays pure (freezes/usedDates unchanged). Existing streak_currentstreak_is_pure_test.dart still green." }
impact_analysis: >
  Account-tier. No crash, no error — a silent under-count. Every user who ever
  missed a scheduled workout that a freeze covered had their streak collapse back
  to that day on the next recompute (home streak chip, rank evaluation,
  completion surfaces all read currentStreak()). The sailor-track rank ladder is
  streak-gated (SD1>=7, LS>=14), so realistic ~85%-adherence users were frozen at
  SD2 no matter how many workouts they completed — the exact "why hasn't my rank
  moved after finishing Phase 1?" the founder asked. Static + source-grep audits
  never caught it because the consume and read walks share one method; the
  divergence only shows up across MULTIPLE recomputes after a persisted
  consumption — precisely what the multi-week simulation replay exercised. With
  the fix, a 4-week ~85%-adherence Phase 1 accrues a streak of ~15 → qualifies
  SD1 then LS, so rank progresses as designed.
---

# 5e8a1c — streak collapses at a previously-frozen day on recompute

## What happened
`WorkoutRepository._calculateStreak` walks the schedule backward from "today",
+1 per completed workout day, skipping rest days, consuming a freeze for a
missed scheduled workout. When a freeze is consumed it is **persisted**
(`freezesAvailable--`, `usedDates += missedDate`) via
`StreakProgressService.commitConsume`.

The walk had exactly one branch referencing `usedDates` — the consume guard:

```dart
} else if (freezesAvailable > 0 && !usedDates.contains(dateStr)) {
  // consume a freeze, continue
} else {
  break;   // ← an ALREADY-frozen day lands here
}
```

On any **later** recompute the previously-frozen day now has `freezesAvailable
== 0` and `usedDates.contains(dateStr) == true`, so it fails the guard and falls
into `else → break`. The freeze protected the day exactly once (the consuming
walk) and then permanently collapsed the streak at that day on every future
read.

## Why it mattered
`currentStreak()` (read-only) feeds the home streak chip AND
`RankService._readEvaluationState`. The sailor-track gates are streak-based
(SD1 streak≥7, LS streak≥14). So a realistic ~85%-adherence user — one missed
day, freeze spent — saw their streak snap back to a tiny number and their rank
frozen at SD2 even after completing all of Phase 1. This is the founder's
"streak only 3 despite full adherence" and "rank hasn't progressed after Phase
1" in one root cause.

## Fix
Add an explicit already-protected branch before the consume branch:

```dart
} else if (usedDates.contains(dateStr)) {
  continue;                 // spent freeze protects this day forever
} else if (freezesAvailable > 0) {
  // consume a fresh freeze, continue
} else {
  break;
}
```

Behavior-preserving on the first walk (usedDates empty); on later walks the
spent-freeze day stays protected instead of breaking.

## Verification
`test/contracts/streak_frozen_day_persists_protection_test.dart`: a 5-day window
where day-2 is missed but already in `usedDates` → streak walks across it (4,
pre-fix 2); a fresh missed day with no freeze still breaks (1); the read stays
pure. `streak_currentstreak_is_pure_test.dart` still green. Live: re-driving the
free 4-week Phase 1 now accrues a streak that clears SD1/LS so rank progresses.
