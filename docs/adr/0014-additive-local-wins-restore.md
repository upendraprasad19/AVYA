---
adr_id: 0014
title: Cloud restore is additive / local-wins for loss-sensitive log rows
status: accepted
date: 2026-06-07
deciders: Upendra
---

# ADR-0014: Additive / local-wins cloud restore

## Status

Accepted (2026-06-07). Supersedes nothing; complements ADR-0001 (Hive-first / offline-first).

## Context

The cold-start cloud restore (`SyncService.restoreFromCloudForUser`,
`since='2020-01-01'`) historically ran to completion **before** a returning user
reached /home — so it was never concurrent with user input. The slow-boot guard
(diagnose c5a1f2) flips returning users to a **background** restore (home in ~3s, the
restore finishes in the background), which makes the restore run **concurrently with the
user logging on /home**.

Several restore writers did an **unconditional `put`** of the cloud row over the local
one (`_restoreExerciseLogs`, `_restoreWorkoutLogs`, `_restoreNutritionLogs`,
`_restoreSavedMeals`). Concurrent with logging, that overwrites a just-logged local row
with the restore's stale cloud snapshot — and if the local write had not yet synced (a
network blip, the founder's original data-loss incident), the data is **truly lost**.

The app is **offline-first** (Hive is the primary store; Supabase is a backup/projection
layer). Some restore writers were already non-destructive: weight / measurements / water
skip-if-local-exists (`sync_health.dart:300`); `_restoreScheduledWorkouts`
timestamp-merges (preserve local completed status, d9b2c5).

Two conflict policies were considered:
- **A — local-wins / additive:** restore only fills gaps; never overwrites a local row.
- **B — cloud-newer-wins:** restore overwrites only when the cloud row is newer than
  local (per-domain `updated_at` comparison).

## Decision

**Adopt local-wins / additive restore for loss-sensitive log rows.** The four
unconditional-overwrite writers above guard their `put` with `if (box.get(key) != null)
continue;` — a restore can only *fill gaps*, never overwrite a present local row. This
mirrors the weight pattern the app already trusts, is safe-by-construction against any
concurrent-write timing (no window matters), and is faster for returning users (skips
redundant rewrites). `_restoreScheduledWorkouts` keeps its timestamp-merge (schedule
*status* genuinely needs cloud↔local reconciliation — additive vs merge is per-writer).

A post-restore heal (`reconcileExlogIndexes`) rebuilds each `exercise_log_index_<date>`
as the union of the `exlog_` rows actually present, as defense-in-depth for index drift.

## Consequences

- **Pro:** A background restore can never destroy a just-logged local row. Consistent
  with the existing weight/measurements/water writers. Returning-user restores are
  cheaper (gap-fill only).
- **Trade-off (accepted):** A row edited on a **second device** will not overwrite the
  local copy on this one — pure offline-first local-wins. Acceptable under the current
  single-primary-device assumption. If true multi-device editing becomes a goal,
  revisit with policy B (cloud-newer-wins) on a per-domain `updated_at` comparison.
- A fresh install (empty local) is unaffected — every cloud row is absent locally, so
  the additive guard writes all of them (full restore).

## Alternatives considered

- **Cloud-newer-wins (policy B):** preserves cross-device freshness but needs a reliable
  `updated_at` in every domain and more conditional surface to get wrong; rejected for
  the current single-device reality.
- **A shared index lock to serialize restore vs log index writes:** rejected — a control
  test (25 concurrent unlocked appends → all survived) refuted the hypothesised index
  race (Hive commits in-memory before yielding; the index read→put is atomic on the
  single isolate). The real loss vector was the row overwrite, fixed above.

## References
- Diagnose: `docs/diagnoses/2026-06-07-slow-boot-additive-restore-c5a1f2.md`
- Prior: `docs/diagnoses/2026-06-05-cold-start-blocking-restore-4e8b1d.md` (slow boot),
  `docs/diagnoses/2026-06-06-exlog-index-fire-and-forget-durability-e4a8b1.md` (data-loss class)
- Test: `test/contracts/restore_local_wins_additive_test.dart`
