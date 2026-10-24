---
reviewed_at: 2026-06-18T00:00:00+05:30
staged_against: discipline-overhaul (Phase 2 streak rework — Units C/D1/D2, uncommitted working tree)
blast_radius: platform
reviewer: 2x context-blind agents (opus streak-logic + sonnet drift/migration) — pre-apply B-pass
lens_set: [streak_decay_logic, permanent_ledger_correctness, reckon_gating, restoreCompletedTick_deviation, writer_reader_drift, cross_account_guard, migration_safety, partial_unique_arbiter]
findings_count: 3 actionable (1 sequencing P0, 1 P1, 1 P2) + multiple FALSE_ALARM
verdict: accepted
---

# B-pass — discipline-overhaul Phase 2 (streak/freeze rework)

Two fresh, context-blind adversarial reviewers (one opus on streak decay/ledger logic + the deliberate plan deviation; one sonnet on writer/reader drift, cross-account, and the two migrations). Diagnose: f9d2e7.

## Findings & resolutions

### P0 (sequencing, both reviewers) — migration 095 must be applied live BEFORE the web-deploying merge — RESOLVED (process)
The client SELECTs/upserts `streak_freezes_first_pro_grant_done`. If web (auto-deploys on push to main) ships before migration 095 is live, the restore SELECT 400s and `_safeRestoreOp` silently aborts the ENTIRE freeze restore → returning PRO users lose freeze state. **Resolution:** this batch follows the founder-chosen "build → review → APPLY → merge" order — migrations 095 + 096 are applied live (with explicit per-action go) and `applied_migrations.json` + `live_schema_columns.json` updated in the merge commit, BEFORE the `--no-ff` merge that auto-deploys web. Not a code bug; a load-bearing ordering constraint now explicit.

### P1 — migration 095 backfill missed ever-PRO users with no `user_progress` row — FIXED
The original backfill `UPDATE` only touched existing rows. An ever-PRO user with a `subscriptions` row but no `user_progress` row (went PRO before logging any workout) would be left at the column DEFAULT (false) → on reinstall the grant would re-fire and could refund spent freezes. **Fix:** added an `INSERT ... SELECT ever-PRO users WHERE NOT EXISTS(user_progress row) ... ON CONFLICT DO NOTHING` to migration 095. Verified safe against the live `user_progress` schema (every NOT NULL column except `user_id` has a DEFAULT — minimal insert cannot violate NOT NULL). Untargeted `ON CONFLICT DO NOTHING` avoids the partial-unique arbiter trap (§2.4).

### P2 — `resetToFreeCapOnLapse` early-returned before `syncFreezes` — FIXED
When local `available` was already ≤ the free cap, the method returned before pushing to cloud, so a stale higher cloud `available` (from an unsynced mid-week PRO state) never converged on lapse → a reinstall could re-inflate a free user. **Fix:** `syncFreezes` now ALWAYS fires on lapse (the Hive write + telemetry still gate on an actual change). Verified: `streak_freeze_first_pro_grant_behavioral_test` lapse cases green; analyze clean.

## FALSE_ALARMs (verified, no action)
- prune horizon (365d) one day tighter than the walk — actually one day WIDER (walk reaches `today−364`; prune keeps `today−365..`), so a relevant frozen day can never be pruned out from under the walk.
- new flag `streak_freezes_first_pro_grant_done` field-name drift — spelled PLURAL identically across Hive write/read, sync push, restore read/write, AND the cloud column. The sibling `streak_freeze_used_dates` singular-Hive / plural-cloud split is pre-existing + intentional; the new flag correctly does NOT inherit it.
- `syncFreezes` only-if-true flag push — correct (never stomps a backfill-true cloud row; local-true always pushes on subsequent syncs).

## Confirmed-clean areas (both reviewers)
- D1 `mergeFreezeProgress` always-union correct on all branches (permanent ledger ⇒ union is the right op everywhere; grant flag preserved separately cloud-true-wins).
- D2 reckon gating sound: `_reckonInFlight` guard correct (fully synchronous, no cross-await window); gate-OFF returns read-only count; gate-ON persists; returning-user decay not suppressed forever (tick bumps every bg-restore; rollover re-runs reckon).
- The deliberate deviation (grant un-gated on `restoreCompletedTick`, decay gated) — sound: `bumpRestoreCompleted` has exactly one caller (returning-user bg-restore heal), so gating the grant would permanently deny a first-session purchaser; phantom-grant is idempotent-flag-guarded + restore-merge-corrected.
- completeWorkout: `markCompleted` persists today's status BEFORE reckon reads it; returned streak persisted.
- Migration 096 RPC fix: exactly the two singular `streak_freeze_used_dates` refs → plural; signature unchanged (auth.uid() guard + mig 091 ACLs preserved).
- Cross-account guards present on BOTH the grant hook and the lapse hook.

## Verdict
accepted — all 3 actionable findings resolved (2 code/migration fixes verified green; 1 sequencing constraint made explicit). Hermes (platform deep-pass) to run pre-merge.
