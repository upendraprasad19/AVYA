---
scope: home
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Home Dashboard — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/home/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/home/` owns the 🏠 Home tab — the user's daily dashboard. It is
**read-only with respect to data** (every card reads from a Riverpod provider
that wraps a ReadService) but it is the *primary entry point* into other
features (Start Workout → Train, Log Meal → Nutrition, Edit Goal → Profile).

Pieces:

- `screens/home_screen.dart` — orchestrates the priority-ordered card stack.
- `widgets/` — `weekly_calendar_strip`, `today_workout_card`, `nutrition_snapshot`, `weight_sparkline`, `pr_snapshot`, `recent_logs`, `step_counter`, `day_detail_sheet`, `swap_sheet`, `streak_warning_banner`, `plan_expired_card`.
- `providers/home_provider.dart` — `todayWorkoutProvider`, `homeNutritionProvider`, `streakWarningEligibilityNotifier`.

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

## Single-source-of-truth contracts

| Concept | Writer | Reader (this dir) |
|---|---|---|
| `workout_receipt_rendering` | `workout_write_service.logExercise` | `home_screen._buildTodayRow` "View Card" handler → `WorkoutReceiptData.fromExerciseLogs(DateTime.now())`; `day_detail_sheet` "View Workout Card" entry. |
| `streaks` | `streak_progress_service.dart` (on workout complete / food log) | `streak_warning_banner.shouldShow` (clamped to [18,23] — see pitfalls). |
| `weight_logs` | `health_write_service.dart` | home `weight_sparkline` (last 7 forward-filled). |
| `day_rollover_provider_invalidation` | `day_rollover_service.dart` (cold-start day-change tick) | mount-time invalidation of `todayWorkoutProvider`, `homeNutritionProvider`, `streakProvider`. |
| Plan expiry (free day 29) | `WorkoutScheduleService.isPhaseExpired()` | `home_screen._buildTodayRow` → `PlanExpiredCard` (3 doors: Upgrade / Build custom / Re-do Week 4). PRO users auto-generate next phase on splash. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Steps/sleep showing stale data | Filter health data by BOTH date AND type (`step_log`, `sleep_log`). Legacy `steps_today` guarded by `stepsToday == null && steps_date == todayStr`. Chat-logged sleep read from `sleep_logs` list as fallback. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Stats grid empty | Fall back to top 4 exercises from allExercisePRs when key lifts (bench/squat/deadlift/OHP) have no data. Unit derived from loggingType (kg/reps/s/km). Adaptive layout: 1→full, 2→row, 3→2+1, 4→2+2. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Prediction card truncated | Home: maxLines 4 + "Read More →" opens full bottom sheet. Shareable: capped at 500 chars. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Free user stuck on day 29 with empty schedule | Check `WorkoutScheduleService.isPhaseExpired()` returns true AND `todayWorkoutProvider` is null → `home_screen._buildTodayRow` must render `PlanExpiredCard` (3 doors: Upgrade / Build custom / Re-do Week 4). PRO users auto-generate next Phase on splash via `splash_screen._autoGenerateNextPhaseForPro()` so they never land here. Added 2026-04-18 per audit H9. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Streak banner fires at 3 PM for a morning lifter | `StreakWarningBanner.shouldShow` (and mirror in `home_provider.StreakWarningEligibilityNotifier._evaluate`) clamps threshold to `[18, 23]`. Handoff is an **evening-only** nudge. Don't re-lower the floor to 15 — an early-riser (6 AM median → raw 9 AM) would surface the banner before dinnertime. Both callsites must stay in sync. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

- `test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart`
- `test/contracts/streaks_writer_to_reader_test.dart`
- `test/contracts/cold_start_day_rollover_test.dart`
- `test/contracts/streak_warning_banner_threshold_test.dart`

## See also

- `lib/features/train/CLAUDE.md` — Today's workout card targets the active workout flow.
- `lib/features/nutrition/CLAUDE.md` — nutrition snapshot card.
- `lib/features/profile/CLAUDE.md` — header avatar + streak chip.
- `lib/shared/widgets/wardroom/CLAUDE.md` — `WardTabHeader` unified tab header (Test #4 / U7).
