---
title: Monotonic-field recompute-from-current-state demotion
category: bug-classes
source_memory: feedback_monotonic_field_recompute_demotion.md
last_reviewed: 2026-05-28
---

# Monotonic-field recompute-from-current-state demotion

## The class

Any cloud column or Hive field whose semantic is "lifetime", "peak", "highest-ever", "longest", or "earned-and-permanent" MUST have a writer that guards `if (new > existing)` — never an unconditional `.update()` from a recompute.

- SQL writers use `GREATEST(new, existing)`.
- Client / Edge Function writers extract a pure helper (e.g. `RankService.shouldPromote(currentCode, qualified)`) so the contract is behaviorally testable without a live Supabase round-trip.

**Denormalizations of append-only event-log tables** (`rank_promotions`, `stat_snapshots`, etc.) MUST also be only-increment. If the event log is the truth, the denorm reconciles UP toward it, never resets to a recomputed current-state ceiling.

This is **not** writer/reader drift — field names match perfectly. It's a SEMANTIC mismatch between TWO writers / sources of truth: one is an event log, the other is a denorm recompute.

## How to detect

Candidate column / field names:

- `lifetime_*`, `total_*_done`, `longest_*`, `max_*`, `best_*`, `peak_*`, `highest_*`
- `current_*_code` (denorm of event log)
- `*_achieved_at`, `*_earned_at`, `*_unlocked_at`
- Badge state, PR records, deployment counts

For each, audit: is the writer guarded?

Symptoms:

- A "lifetime" rank/badge/counter visibly decreases after a user breaks a recent gate.
- Two denorms disagree on what "current X" means; UI reads the demoted one.

## Prevention

1. **Spotting candidates** — sweep the columns/fields named above; each surface needs the only-increment audit.

2. **New monotonic fields** — when introducing one, add a SoT registry entry with `class_constraints` enforcing the only-increment invariant + a behavioral test alongside the source-grep test. Source-grep alone is insufficient; ordinal-compare logic must be exercised at runtime.

3. **Fix-time sweep** — when fixing one instance of this class, ALWAYS dispatch a sibling-audit subagent. The same anti-pattern often hides in 2-3 parallel functions.

4. **Heal migrations** — use HISTORICAL timestamps from the event-log source when restoring `achieved_at` fields. `now()` would lie about when the user actually earned the achievement.

## Instances

- **2026-05-27 rank demotion (SD1 → SD2)**: client `RankService.evaluateAndPromote` checked `currentCode != qualified.code` and unconditionally overwrote `user_profile.current_rank_code` with the currently-qualifying ceiling. Server cron `evaluate-rank-promotions` had the identical bug. Migration 075 healed the denorm from the max-ordinal `rank_promotions` row using historical `achieved_at`.

- **Sibling audit caught**: `weekly-recalc/index.ts` recomputing `user_progress.total_workouts_done` (a lifetime counter) from the count of distinct workout dates in the LAST 4 WEEKS — every Sunday silently decreased the lifetime counter for any user training longer than 4 weeks. Fixed via `Math.max(recomputed, existing)`.

- **Verified clean during sweep**: `badge_service.dart` already guards `!unlocked.containsKey(id.name)`.

## Latent suspect list (revisit when next writer ships)

- `user_progress.deployments_complete` (driver for PO/CPO rank gates; no writer today — must be only-increment when implemented).
- `user_progress.longest_streak_weeks` if/when added (streak-medal reader).

## References

- Debugging skill: `.claude/skills/debugging/SKILL.md` §2.19.
- Related: [`writer-reader-drift.md`](writer-reader-drift.md), [source-grep-limits](../testing/source-grep-limits.md).
