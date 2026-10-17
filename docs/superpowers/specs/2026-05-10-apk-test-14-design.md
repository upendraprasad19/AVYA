# APK Test #14 — Calendar/restore/sync hardening + freeze ladder

**Date:** 2026-05-10
**Branch:** `feat/apk-test-14-batch` (off `main` @ `27a6f09`)
**Predecessor APK:** 1.0.0+18 (`d6a2ed33…`, MD5)
**Discipline:** Per CLAUDE.md §6.22, every bug fix here gets a `docs/diagnoses/<id>.md` and a regression test that fails on `main` without the fix and passes with it. Batch ships through the new `/build-apk` 14-gate pipeline.

---

## Goal

Make completed-workout state survive every cold-start, force-restart, logout-login, and IST-midnight-crossing case. Then expose streak-freeze inventory honestly to the user (`x/y`) with a ladder-style refill instead of a weekly reset.

---

## Forensic context (cloud + telemetry, founder user_id `d7a67a37…`)

- **`workout_logs`** for the user has rows for May 4/5/6/7/9 — exercise-level data is making it to cloud fine.
- **`scheduled_workouts.status`** for the user:
  - May 4: `completed`, `completed_at=2026-05-04T09:30Z` (15:00 IST same day)
  - May 5/6/7: `completed`, `completed_at=2026-05-07T21:19Z` (= 02:49 IST May 8 — bulk retroactive)
  - **May 8: `planned`, `completed_at=null`**
  - **May 9 (Sat): `planned`, `completed_at=null`** ← user reports they completed this; cloud never received the completion
- **`client_errors`** for the user, last 6h: 10 × `upsert_scheduled_workout` `PostgrestException 23503` between 12:45:00–12:45:05 UTC, all `scheduled_workouts_template_id_fkey` violations.

---

## Bug A — Stale-completion guard is over-eager

### What's wrong

`lib/core/services/workout_schedule_service.dart:530-568` — the `getScheduleForDate` guard downgrades any `status='completed'` row to `'planned'` when `completed_at`'s IST date ≠ `schedule_date`. Two legitimate completion patterns hit this wrongly:

1. **Retroactive logging** — user logs Tuesday's workout on Sunday night. `completed_at_dateKey != schedule_date` → downgraded.
2. **Late-night IST-midnight crossing** — user finishes at 23:55 IST and the row gets a `completed_at` that lands on the next IST date (or, more commonly, the cloud row's UTC timestamp converts to an IST date one ahead). Bulk completions on May 7 21:19 UTC = 02:49 IST May 8 are the live example.

This is a conceptual flaw, not a timezone-arithmetic flaw. Bug 5.3's earlier fix removed `.toLocal()` (correct, prevented a different double-shift) but didn't address the wrong premise.

### Fix

Relax the guard: **only flag stale if `completed_at < schedule_date`** (impossible-future-completion = real corruption from clock skew or test-data).

Pseudocode:

```dart
final completedDateStr = _dateKey(completedDate);
if (completedDateStr.compareTo(requestedDateStr) < 0) {
  // Only "stale" if completion claims a date BEFORE the schedule date
  // — which is impossible without corruption.
  return downgradedCopy(map);
}
return map; // Trust Hive. Restore is the source of truth for cleanup.
```

### Regression test

`test/contracts/stale_completion_guard_test.dart`:
- Schedule May 5, completed_at = May 7 21:19 UTC (May 8 IST) → returns `completed` (not downgraded).
- Schedule May 5, completed_at = May 5 18:00 IST → returns `completed`.
- Schedule May 5, completed_at = May 3 20:00 IST → returns `planned` (real impossible past).

---

## Bug B — Saturday completion never reaches cloud, then restore destroys it

### What's wrong

Three layered failures combine:

#### B.1 — `_syncScheduledWorkouts` push throws FK violation

`lib/core/services/sync_service.dart:3707-3755`. The push coerces local `tmpl_<ms>` → v5 UUID via `_deterministicId(rawTemplateId)`. **Despite this, 10 FKs fire on the founder's account.** The deterministic UUID being sent for Saturday's `template_id` does not exist in cloud `workout_templates`.

Three candidate root-causes (subagent investigation will pick one):

1. **Schedule-vs-template ID divergence:** Saturday's Hive `schedule_2026-05-09.template_id` references a `tmpl_<ms>` raw key for which the parent template was never synced (or sync errored silently).
2. **Race ordering:** `_syncScheduledWorkouts` ran before `_syncWorkoutTemplates` finished, so the parent row didn't exist yet when the child upsert fired.
3. **Derivation drift:** `_deterministicId` was changed at some point and old templates have v5 UUIDs derived under the old scheme while new schedule entries use the new one.

Fix proposal (encompasses all three):

- **B.1.a** Make the push self-healing: if FK fires (PostgreSQL 23503), retry once after re-running `_syncWorkoutTemplates(userId)`. If still 23503, fall back to `template_id: null` push (preserve `status='completed'`, lose the template attribution).
- **B.1.b** Always run `_syncWorkoutTemplates` before `_syncScheduledWorkouts` in any combined push path (not just restore).
- **B.1.c** Pin `_deterministicId` derivation behind a frozen contract test; surface any drift loudly.

#### B.2 — `_restoreScheduledWorkouts` overwrites local `completed` with cloud `planned`

`sync_service.dart:3758-3814`. The merge says "cloud is authoritative for status/completed_at." That's the right rule for the case the comment describes (stale local 'planned' overwriting cloud's 'completed' from another device). It is the **wrong** rule when local is fresher than cloud — exactly what happens after B.1 fails.

Fix: timestamp-aware merge.

```
if local.status == 'completed' && cloud.status == 'planned':
  if local.completed_at != null:
    keep local; queue re-push to cloud
  else:
    take cloud (defensive — local is asserting completion without timestamp)
```

#### B.3 — One-shot heal of any divergent rows

A subset of users (founder included) currently has Hive `completed` + cloud `planned` for one or more dates. Once B.1 + B.2 ship, future writes will stay consistent, but **existing divergence won't self-heal** unless we re-push.

Fix: on first cold-start after upgrade, scan local Hive `schedule_*` keys with `status='completed'`, and for each, re-trigger `_syncScheduledWorkouts` filtered to those keys. Idempotent — runs once, gated by `userBox['apk_test_14_completion_resync_done']`.

### Regression tests

- `test/contracts/scheduled_workouts_fk_resilience_test.dart` — mock cloud, simulate 23503 → assert retry, then null-template fallback.
- `test/contracts/restore_non_destructive_test.dart` — local has `completed` + `completed_at`, cloud has `planned` → after restore, local stays `completed`.
- `test/contracts/sync_template_before_schedule_order_test.dart` — combined push always sequences templates before schedules.

---

## Bug C — gold-past + green-today (no change)

Already shipped in 1.0.0+18. Decision locked: past completions render gold ✓, today's completion renders green ✓. Distinct semantics: gold = historical, green = "you closed today's loop". User confirmed.

No code change. No test change.

---

## Bug D — Streak freeze ladder

### Current behavior (verified)

- `lib/features/home/providers/home_provider.dart:239-274` — refill resets to max (1 free / 3 PRO) every Monday.
- `supabase/migrations/048_restore_completeness.sql:16` — cloud column default is **2** (was conservative pre-Test-#11 thinking).
- `sync_service.dart:4117` and `:4228` — restore fallback is **2**.
- Pill display (`streak_pill.dart` or equivalent) shows just `❄ <available>`.

### Target behavior

| Slot | Free | PRO |
|---|---|---|
| `maxFreezes` | 1 | 3 |
| Refill cadence | Weekly Monday IST | Weekly Monday IST |
| Refill semantics | `available = min(available + 1, max)` | `available = min(available + 1, max)` |
| Used-this-week reset | Yes (existing) | Yes (existing) |
| Cloud default | 1 (free baseline) | (n/a — written by client on first login) |
| Restore fallback | 1 | 1 (defensive — client refills on next launch) |
| Pill format | `❄ x/y` | `❄ x/y` |

### Change set

- **D.1** Change `_refillIfNewWeek` to ladder semantics. Add a unit test `test/home/streak_freeze_refill_ladder_test.dart` covering:
  - Free user, 0 available, Monday → 1 (capped).
  - Free user, 1 available, Monday → 1 (no over-fill).
  - PRO user, 0 available, Monday → 1 (ladder, not reset to 3).
  - PRO user, 2 available, Monday → 3 (capped at max).
  - PRO user, 3 available, Monday → 3 (no over-fill).
  - Same Monday twice → idempotent.
- **D.2** Migration 050: bump cloud `streak_freezes_available` default from 2 → 1. Reasoning: cloud default is the value a fresh `user_progress` row gets before client first login. Free is the safe baseline; PRO clients overwrite within seconds of first launch.
- **D.3** Update streak pill widget to show `x/y`. New helper `streakFreezeMaxProvider` returns 1/3 based on subscription. Pill reads `(streakFreezeProvider, streakFreezeMaxProvider)`.
- **D.4** Update `sync_service.dart:4117, 4228` restore fallbacks from 2 → 1.
- **D.5** Update CLAUDE.md "Restore-completeness sync" sub-section to reflect ladder semantics.

---

## Out of scope (deferred to next batch with explicit user nod)

- **Bug E:** AI coach fresh-per-day + lazy-load older chats. User explicitly said "separate, we will fix after this batch."

Per `feedback_no_deferrals_recurrence.md`, this is the only deferral, it's user-instructed, and it's recorded here so it doesn't get lost.

---

## Dependencies audit

Per `feedback_surface_dependencies_during_brainstorm.md`:

| Dep | Status |
|---|---|
| Migration 050 (cloud default 2→1) | Claude autonomous via Supabase MCP `apply_migration` |
| Edge function changes | None |
| Client SDK / pubspec | None |
| Razorpay / OneSignal / Firebase | None |
| ADB / on-device root | None |
| Founder action front-loaded | None |
| Test-data fixtures | Existing — `test/streak_freeze_test.dart` + integration helpers |

Single dependency is the migration. Apply via MCP. Captured.

---

## Rollout

1. Implement on `feat/apk-test-14-batch`. Subagent per task. Two-stage review per task.
2. Apply migration 050.
3. Merge `--no-ff` to `main`.
4. `/build-apk` from main with all 14 gates.
5. Founder installs, verifies against checklist:
   - Calendar shows ✓ on May 5/6/7 (Bug A).
   - Saturday survives force-restart (Bug B.1+B.2).
   - Saturday survives logout-login (Bug B.3 heals existing divergence; B.2 prevents future).
   - Streak pill shows `❄ 3/3` (PRO user).
   - Use 1 freeze → next Monday it shows `❄ 1/3` (ladder, not reset).
