---
scope: home
parent: ../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Home Dashboard — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/home/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## Home Screen Layout (Priority Order)

```
1. Header (name + greeting + avatar + streak counter)
2. Weekly calendar strip (7 days, color-coded by completion)
3. Quick actions: Log Workout | Log Meal | Hydration | Sleep
4. Today's workout card → Start Workout (or DONE + View Card + stats if completed)
5. Nutrition snapshot (calories + protein vs target)
6. AI Coach insight (computed from local schedule data — next workout, consistency tips)
7. Weight sparkline (last 7 entries)
8. PR snapshot (dynamic — top 4 exercises by volume when key lifts empty)
9. Recent logged foods
10. Step counter (Health Connect)
```

**Today's Workout Card — Completed State:**
- Shows: DONE badge (green) + "View Card >" (gold) + best lift + total volume
- "View Card" opens `WorkoutReceiptSheet` with receipt reconstructed from Hive exercise logs
- Calendar day detail sheet also shows "View Workout Card" button for completed days

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Steps/sleep showing stale data | Filter health data by BOTH date AND type (`step_log`, `sleep_log`). Legacy `steps_today` guarded by `stepsToday == null && steps_date == todayStr`. Chat-logged sleep read from `sleep_logs` list as fallback. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Stats grid empty | Fall back to top 4 exercises from allExercisePRs when key lifts (bench/squat/deadlift/OHP) have no data. Unit derived from loggingType (kg/reps/s/km). Adaptive layout: 1→full, 2→row, 3→2+1, 4→2+2. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Prediction card truncated | Home: maxLines 4 + "Read More →" opens full bottom sheet. Shareable: capped at 500 chars. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Free user stuck on day 29 with empty schedule | Check `WorkoutScheduleService.isPhaseExpired()` returns true AND `todayWorkoutProvider` is null → `home_screen._buildTodayRow` must render `PlanExpiredCard` (3 doors: Upgrade / Build custom / Re-do Week 4). PRO users auto-generate next Phase on splash via `splash_screen._autoGenerateNextPhaseForPro()` so they never land here. Added 2026-04-18 per audit H9. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Streak banner fires at 3 PM for a morning lifter | `StreakWarningBanner.shouldShow` (and mirror in `home_provider.StreakWarningEligibilityNotifier._evaluate`) clamps threshold to `[18, 23]`. Handoff is an **evening-only** nudge. Don't re-lower the floor to 15 — an early-riser (6 AM median → raw 9 AM) would surface the banner before dinnertime. Both callsites must stay in sync. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

(populated in Milestone 6)
