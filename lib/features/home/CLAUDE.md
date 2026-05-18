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

(populated in Milestones 2 + 5)

## Tests pinning the rules here

(populated in Milestone 6)
